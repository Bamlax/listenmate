import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../data/changelog.dart';

class AppUpdateInfo {
  final String latestVersion;
  final String releaseNotes;
  final String releasePageUrl;
  final String? apkDownloadUrl;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    required this.releasePageUrl,
    this.apkDownloadUrl,
  });
}

class UpdateService {
  static const String authorUrl = 'https://github.com/Bamlax';
  static const String repoUrl = 'https://github.com/Bamlax/listenmate';
  static const String _latestReleaseApi =
      'https://api.github.com/repos/Bamlax/listenmate/releases/latest';

  static String get currentLocalVersion => appVersionHistory.isNotEmpty
      ? appVersionHistory.first.version
      : 'v0.1.0';

  /// 启动或手动检测 GitHub 是否有新版本
  static Future<void> checkForUpdate(
    BuildContext context, {
    bool silent = true,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(_latestReleaseApi),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        if (!silent && context.mounted) {
          _showSnack(context, '检查更新失败（HTTP ${response.statusCode}）');
        }
        return;
      }

      final Map<String, dynamic> data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      final tagName = (data['tag_name'] as String? ?? '').trim();
      if (tagName.isEmpty) return;

      final localVersion = currentLocalVersion;
      if (!_isRemoteNewer(tagName, localVersion)) {
        if (!silent && context.mounted) {
          _showSnack(context, '当前已是最新版本 ($localVersion)');
        }
        return;
      }

      final body = (data['body'] as String? ?? '').trim();
      final htmlUrl =
          (data['html_url'] as String? ?? '$repoUrl/releases').trim();

      String? apkUrl;
      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String?;
            break;
          }
        }
      }

      if (!context.mounted) return;
      await _showUpdateDialog(
        context,
        AppUpdateInfo(
          latestVersion: tagName.startsWith('v') ? tagName : 'v$tagName',
          releaseNotes: body.isEmpty ? '修复已知问题并优化使用体验。' : body,
          releasePageUrl: htmlUrl,
          apkDownloadUrl: apkUrl,
        ),
      );
    } catch (_) {
      if (!silent && context.mounted) {
        _showSnack(context, '无法连接 GitHub，请检查网络后重试');
      }
    }
  }

  /// 语义化版本号比对（例如 v0.1.1 > v0.1.0）
  static bool _isRemoteNewer(String remoteRaw, String localRaw) {
    List<int> parseParts(String raw) {
      final cleaned =
          raw.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
      return cleaned
          .split('.')
          .map((seg) => int.tryParse(seg.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    final r = parseParts(remoteRaw);
    final l = parseParts(localRaw);
    final maxLen = r.length > l.length ? r.length : l.length;

    for (int i = 0; i < maxLen; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv > lv) return true;
      if (rv < lv) return false;
    }
    return false;
  }

  static Future<void> _showUpdateDialog(
    BuildContext context,
    AppUpdateInfo info,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.system_update_rounded, color: colorScheme.primary),
              const SizedBox(width: 8),
              const Text('发现新版本'),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  info.latestVersion,
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前版本：$currentLocalVersion → 最新版本：${info.latestVersion}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      info.releaseNotes,
                      style: textTheme.bodySmall?.copyWith(height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('稍后再说'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                openExternalUrl(
                  context,
                  info.apkDownloadUrl ?? info.releasePageUrl,
                );
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('前往下载'),
            ),
          ],
        );
      },
    );
  }

  /// 在外部浏览器打开链接（失败时自动复制链接作为兜底）
  static Future<void> openExternalUrl(
    BuildContext context,
    String urlString,
  ) async {
    final uri = Uri.parse(urlString);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        await Clipboard.setData(ClipboardData(text: urlString));
        if (context.mounted) {
          _showSnack(context, '未检测到可用浏览器，已复制链接：$urlString');
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: urlString));
      if (context.mounted) {
        _showSnack(context, '已复制链接到剪贴板：$urlString');
      }
    }
  }

  static void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}