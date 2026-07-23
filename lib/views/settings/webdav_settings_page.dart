/// WebDAV synchronization configuration and actions.
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../foundation/log.dart';
import '../../foundation/webdav_client.dart';
import '../../foundation/webdav_config_store.dart';
import '../../foundation/webdav_sync.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_safe_area.dart';

class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key, this.configStore});

  final WebDavConfigStore? configStore;

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  late final Future<WebDavConfigStore> _configStore;
  bool _loadingConfig = true;
  bool _saving = false;
  bool _testing = false;
  bool _syncing = false;
  String? _testResult;
  String? _syncMessage;
  double? _syncProgress;

  @override
  void initState() {
    super.initState();
    _configStore = widget.configStore == null
        ? WebDavConfigStore.create()
        : Future<WebDavConfigStore>.value(widget.configStore!);
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final store = await _configStore;
    if (!mounted) return;
    final config = await store.read();
    if (!mounted) return;
    if (config != null) {
      _urlCtrl.text = config.url;
      _userCtrl.text = config.username;
      _passCtrl.text = config.password;
    }
    setState(() => _loadingConfig = false);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  WebDavConfig? get _config {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return null;
    return WebDavConfig(
      url: url,
      username: _userCtrl.text,
      password: _passCtrl.text,
    );
  }

  Future<bool> _saveConfig({bool showMessage = true}) async {
    final config = _config;
    if (config == null) {
      if (showMessage && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请填写服务器地址')));
      }
      return false;
    }
    if (!mounted) return false;
    setState(() => _saving = true);
    final store = await _configStore;
    if (!mounted) return false;
    final saved = await store.save(config);
    if (!mounted) return saved;
    setState(() => _saving = false);
    if (showMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(saved ? 'WebDAV 配置已保存' : '保存配置失败')),
      );
    }
    return saved;
  }

  Future<void> _testConnection() async {
    final config = _config;
    if (config == null) return;
    final saved = await _saveConfig(showMessage: false);
    if (!mounted || !saved) return;
    setState(() => _testing = true);
    final result = await WebDavClient(config).testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result.isSuccess ? '✅ 连接成功' : '❌ ${result.error}';
    });
  }

  Future<void> _backup() async {
    final config = _config;
    if (config == null) return;
    final saved = await _saveConfig(showMessage: false);
    if (!mounted || !saved) return;
    setState(() {
      _syncing = true;
      _syncMessage = null;
      _syncProgress = 0;
    });
    final error = await WebDavSync(
      WebDavClient(config),
    ).backup(onProgress: _updateProgress);
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncMessage = error ?? '✅ 备份完成';
      _syncProgress = error == null ? 1 : null;
    });
    if (error == null) Log.i('WebDAV backup ok', config.url);
  }

  Future<void> _restore() async {
    final config = _config;
    if (config == null) return;
    final saved = await _saveConfig(showMessage: false);
    if (!mounted || !saved) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text('恢复数据', style: TextStyle(color: context.primaryTextColor)),
        content: Text(
          '将从 WebDAV 下载最新备份并覆盖本地数据，继续吗？',
          style: TextStyle(color: context.secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _syncing = true;
      _syncMessage = null;
      _syncProgress = 0;
    });
    final error = await WebDavSync(
      WebDavClient(config),
    ).restore(onProgress: _updateProgress);
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncMessage = error ?? '✅ 恢复完成';
      _syncProgress = error == null ? 1 : null;
    });
  }

  void _updateProgress(String message, double progress) {
    if (!mounted) return;
    setState(() {
      _syncMessage = message;
      _syncProgress = progress;
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
      body: _loadingConfig
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                bottomContentInset(context),
              ),
              children: [
                const _FieldLabel('服务器地址'),
                TextField(
                  key: const Key('webdav-url'),
                  controller: _urlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: _input(
                    'https://nextcloud.example.com/remote.php/dav/files/用户名/',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const _FieldLabel('用户名'),
                TextField(
                  key: const Key('webdav-user'),
                  controller: _userCtrl,
                  decoration: _input('用户名'),
                ),
                const SizedBox(height: AppSpacing.md),
                const _FieldLabel('密码'),
                TextField(
                  key: const Key('webdav-password'),
                  controller: _passCtrl,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: _input('应用密码'),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  key: const Key('webdav-save'),
                  onPressed: _saving ? null : _saveConfig,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('保存配置'),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  onPressed: _testing ? null : _testConnection,
                  child: _testing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('测试连接'),
                ),
                if (_testResult != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testResult!.startsWith('✅')
                            ? context.successColor
                            : context.colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _syncing ? null : _backup,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('备份'),
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
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: LinearProgressIndicator(value: _syncProgress),
                    ),
                  Text(
                    _syncMessage!,
                    style: TextStyle(color: context.secondaryTextColor),
                  ),
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.primaryTextColor,
      ),
    ),
  );
}
