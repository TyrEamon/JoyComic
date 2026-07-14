/// WebDAV 同步设置页面。
library webdav_settings_page;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../foundation/log.dart';
import '../../foundation/webdav_client.dart';
import '../../foundation/webdav_sync.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key});

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _testing = false;
  bool _syncing = false;
  String? _testResult;
  String? _syncMessage;
  double? _syncProgress;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  WebDavConfig? get _config {
    if (_urlCtrl.text.isEmpty) return null;
    return WebDavConfig(
      url: _urlCtrl.text,
      username: _userCtrl.text,
      password: _passCtrl.text,
    );
  }

  Future<void> _testConnection() async {
    final cfg = _config;
    if (cfg == null) return;
    setState(() => _testing = true);

    final client = WebDavClient(cfg);
    final res = await client.testConnection();

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = res.isSuccess ? '✅ 连接成功' : '❌ ${res.error}';
    });
  }

  Future<void> _backup() async {
    final cfg = _config;
    if (cfg == null) return;
    setState(() {
      _syncing = true;
      _syncMessage = null;
      _syncProgress = 0;
    });

    final client = WebDavClient(cfg);
    final sync = WebDavSync(client);
    final error = await sync.backup(onProgress: (msg, progress) {
      if (!mounted) return;
      setState(() {
        _syncMessage = msg;
        _syncProgress = progress;
      });
    });

    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncMessage = error ?? '✅ 备份完成';
      _syncProgress = error != null ? null : 1.0;
    });
    if (error == null) Log.i('WebDAV backup ok', cfg.url);
  }

  Future<void> _restore() async {
    final cfg = _config;
    if (cfg == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text('恢复数据', style: TextStyle(color: context.primaryTextColor)),
        content: Text('将从 WebDAV 下载最新备份并覆盖本地数据，继续吗？',
            style: TextStyle(color: context.secondaryTextColor)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: context.tertiaryTextColor)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: context.colorScheme.primary),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _syncing = true;
      _syncMessage = null;
      _syncProgress = 0;
    });

    final client = WebDavClient(cfg);
    final sync = WebDavSync(client);
    final error = await sync.restore(onProgress: (msg, progress) {
      if (!mounted) return;
      setState(() {
        _syncMessage = msg;
        _syncProgress = progress;
      });
    });

    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncMessage = error ?? '✅ 恢复完成';
      _syncProgress = error != null ? null : 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text('WebDAV 同步'),
        backgroundColor: context.pageBackground,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text('服务器地址',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.primaryTextColor)),
          const SizedBox(height: 8),
          TextField(
            controller: _urlCtrl,
            decoration: _input('https://nextcloud.example.com/remote.php/dav/files/用户名/'),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('用户名',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.primaryTextColor)),
          const SizedBox(height: 8),
          TextField(controller: _userCtrl, decoration: _input('用户名')),
          const SizedBox(height: AppSpacing.md),
          Text('密码',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.primaryTextColor)),
          const SizedBox(height: 8),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            decoration: _input('应用密码'),
          ),
          const SizedBox(height: AppSpacing.xl),

          // 测试连接
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _testing ? null : _testConnection,
              child: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('测试连接'),
            ),
          ),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_testResult!,
                  style: TextStyle(
                      color: _testResult!.startsWith('✅')
                          ? AppColors.success
                          : Colors.redAccent)),
            ),

          const SizedBox(height: AppSpacing.xl),

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _syncing ? null : _backup,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('备份'),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _syncing ? null : _restore,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('恢复'),
                ),
              ),
            ],
          ),

          if (_syncMessage != null) ...[
            const SizedBox(height: AppSpacing.lg),
            if (_syncProgress != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(
                  value: _syncProgress,
                  backgroundColor: context.elevatedSurfaceColor,
                  color: context.colorScheme.primary,
                ),
              ),
            Text(_syncMessage!,
                style: TextStyle(color: context.secondaryTextColor)),
          ],
        ],
      ),
    );
  }

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.tertiaryTextColor, fontSize: 13),
        filled: true,
        fillColor: context.surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );
}
