package com.bamlax.listenmate // <-- 请保留与你 MainActivity.kt 一致的 package 名称

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.floor
import kotlin.math.roundToInt
import kotlin.math.roundToLong

object AudioConverter {

    /**
     * 将任意 Android 支持的音频流式解码并重采样为 16-bit 单声道 PCM WAV
     * 严格锚定 MediaCodec.BufferInfo.presentationTimeUs，确保长音频时间轴零漂移
     */
    fun convertToWav(
        inputPath: String,
        outputPath: String,
        targetSampleRate: Int = 16000
    ) {
        val inputFile = File(inputPath)
        if (!inputFile.exists()) {
            throw IllegalArgumentException("输入音频文件不存在: $inputPath")
        }

        val outputFile = File(outputPath)
        outputFile.parentFile?.mkdirs()
        if (outputFile.exists()) {
            outputFile.delete()
        }

        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var rawOut: FileOutputStream? = null
        var bufferedOut: BufferedOutputStream? = null

        try {
            extractor.setDataSource(inputPath)

            var audioTrackIndex = -1
            var inputFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    inputFormat = format
                    break
                }
            }

            if (audioTrackIndex < 0 || inputFormat == null) {
                throw IllegalArgumentException("未在文件中检测到有效音频轨道")
            }

            extractor.selectTrack(audioTrackIndex)
            val mime = inputFormat.getString(MediaFormat.KEY_MIME)!!

            var srcSampleRate = if (inputFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            } else {
                44100
            }
            var srcChannels = if (inputFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            } else {
                1
            }
            var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT

            codec = MediaCodec.createDecoderByType(mime)
            codec.configure(inputFormat, null, null, 0)
            codec.start()

            rawOut = FileOutputStream(outputFile)
            bufferedOut = BufferedOutputStream(rawOut, 65536)

            bufferedOut.write(ByteArray(44))

            val bufferInfo = MediaCodec.BufferInfo()
            var isInputDone = false
            var isOutputDone = false
            var totalPcmBytesWritten = 0L

            var lastSamplePrevChunk = 0f
            var cursor = 0.0
            val driftToleranceSamples = targetSampleRate / 20L // 50ms 容差

            while (!isOutputDone) {
                if (!isInputDone) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val inBuffer = codec.getInputBuffer(inIndex)!!
                        val sampleSize = extractor.readSampleData(inBuffer, 0)
                        if (sampleSize < 0) {
                            codec.queueInputBuffer(
                                inIndex, 0, 0, 0L,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            isInputDone = true
                        } else {
                            codec.queueInputBuffer(
                                inIndex, 0, sampleSize, extractor.sampleTime, 0
                            )
                            extractor.advance()
                        }
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)
                when {
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val newFormat = codec.outputFormat
                        if (newFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                            srcSampleRate = newFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        }
                        if (newFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                            srcChannels = newFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        }
                        if (newFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                            pcmEncoding = newFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        }
                    }

                    outIndex >= 0 -> {
                        val outBuffer = codec.getOutputBuffer(outIndex)
                        if (outBuffer != null && bufferInfo.size > 0) {
                            // 对齐原始媒体播放时钟 (PTS)，防止编码器前导静音或采样率切换造成时间漂移
                            if (bufferInfo.presentationTimeUs >= 0L) {
                                val expectedSamples =
                                    ((bufferInfo.presentationTimeUs / 1_000_000.0) * targetSampleRate).roundToLong()
                                val actualSamples = totalPcmBytesWritten / 2L
                                val lagSamples = expectedSamples - actualSamples
                                if (lagSamples > driftToleranceSamples) {
                                    for (s in 0 until lagSamples) {
                                        bufferedOut.write(0)
                                        bufferedOut.write(0)
                                        totalPcmBytesWritten += 2L
                                    }
                                    cursor = 0.0
                                }
                            }

                            outBuffer.position(bufferInfo.offset)
                            outBuffer.limit(bufferInfo.offset + bufferInfo.size)

                            val monoSamples = decodeToMonoFloats(
                                buffer = outBuffer,
                                byteCount = bufferInfo.size,
                                channels = srcChannels,
                                pcmEncoding = pcmEncoding
                            )

                            if (monoSamples.isNotEmpty()) {
                                val step = srcSampleRate.toDouble() / targetSampleRate.toDouble()
                                val count = monoSamples.size

                                while (cursor < count - 1) {
                                    val idx = floor(cursor).toInt()
                                    val frac = (cursor - idx).toFloat()
                                    val s0 = if (idx < 0) lastSamplePrevChunk else monoSamples[idx]
                                    val s1 = monoSamples[idx + 1]
                                    val sampleInt = (s0 + (s1 - s0) * frac)
                                        .roundToInt()
                                        .coerceIn(-32768, 32767)

                                    bufferedOut.write(sampleInt and 0xFF)
                                    bufferedOut.write((sampleInt shr 8) and 0xFF)
                                    totalPcmBytesWritten += 2L
                                    cursor += step
                                }

                                lastSamplePrevChunk = monoSamples[count - 1]
                                cursor -= count
                            }
                        }

                        codec.releaseOutputBuffer(outIndex, false)
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            isOutputDone = true
                        }
                    }
                }
            }

            bufferedOut.flush()
            bufferedOut.close()
            bufferedOut = null
            rawOut.close()
            rawOut = null

            writeWavHeader(
                file = outputFile,
                totalAudioLen = totalPcmBytesWritten,
                sampleRate = targetSampleRate,
                channels = 1,
                bitsPerSample = 16
            )
        } catch (e: Exception) {
            if (outputFile.exists()) {
                outputFile.delete()
            }
            throw e
        } finally {
            try {
                bufferedOut?.close()
                rawOut?.close()
                codec?.stop()
                codec?.release()
                extractor.release()
            } catch (_: Exception) {
            }
        }
    }

    private fun decodeToMonoFloats(
        buffer: ByteBuffer,
        byteCount: Int,
        channels: Int,
        pcmEncoding: Int
    ): FloatArray {
        val safeChannels = channels.coerceAtLeast(1)
        val ordered = buffer.slice().order(ByteOrder.LITTLE_ENDIAN)

        return if (pcmEncoding == AudioFormat.ENCODING_PCM_FLOAT) {
            val totalFloats = byteCount / 4
            val frameCount = totalFloats / safeChannels
            FloatArray(frameCount) {
                var sum = 0f
                for (ch in 0 until safeChannels) {
                    sum += ordered.float * 32767f
                }
                sum / safeChannels
            }
        } else {
            val totalShorts = byteCount / 2
            val frameCount = totalShorts / safeChannels
            FloatArray(frameCount) {
                var sum = 0f
                for (ch in 0 until safeChannels) {
                    sum += ordered.short.toFloat()
                }
                sum / safeChannels
            }
        }
    }

    private fun writeWavHeader(
        file: File,
        totalAudioLen: Long,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int
    ) {
        val totalDataLen = totalAudioLen + 36
        val byteRate = sampleRate.toLong() * channels * bitsPerSample / 8
        val blockAlign = (channels * bitsPerSample / 8).toShort()

        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray(Charsets.US_ASCII))
        header.putInt(totalDataLen.toInt())
        header.put("WAVE".toByteArray(Charsets.US_ASCII))
        header.put("fmt ".toByteArray(Charsets.US_ASCII))
        header.putInt(16)
        header.putShort(1)
        header.putShort(channels.toShort())
        header.putInt(sampleRate)
        header.putInt(byteRate.toInt())
        header.putShort(blockAlign)
        header.putShort(bitsPerSample.toShort())
        header.put("data".toByteArray(Charsets.US_ASCII))
        header.putInt(totalAudioLen.toInt())

        RandomAccessFile(file, "rw").use { raf ->
            raf.seek(0)
            raf.write(header.array())
        }
    }
}