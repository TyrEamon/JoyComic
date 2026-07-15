/// 登录页。
///
/// 结构：
/// 1. 顶部源选择：禁漫 / 哔咔 chip 切换（选中源决定下方表单与登录调用）
/// 2. 账号 / 密码 输入框（带图标）
/// 3. 显示密码开关
/// 4. 登录按钮（品牌渐变胶囊）
/// 5. 底部：注册官网 / 忘记密码 链接
///
/// 功能集成说明：
/// - 登录调 `source.account.login!(account, pwd)`：
///   禁漫登录前会自动 selectDomain 探测 + fetchSetting 拉图床（见 jm.dart）；
///   哔咔登录拿 token + getProfile。
/// - 登录态写 `source.data['account']` 持久化，reLogin 复用。
/// - 测速选源入口 push /settings/source（禁漫 6 图床测速 + express 快速通道）。
/// - 当前已集成真实登录。
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/log.dart';

import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_spacing.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.initialSourceKey = 'jm'});

  final String initialSourceKey;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late String _sourceKey = widget.initialSourceKey;
  final _account = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  static const _sources = [
    _SourceOpt(key: 'jm', name: '禁漫', website: 'https://jmcomic1.cc'),
    _SourceOpt(key: 'picacg', name: '哔咔', website: 'https://picacomic.com'),
  ];

  _SourceOpt get _source => _sources.firstWhere((s) => s.key == _sourceKey);

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_account.text.isEmpty || _password.text.isEmpty) return;
    setState(() => _loading = true);
    final s = ComicSource.find(_sourceKey);
    if (s?.account?.login == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('该源不支持登录')));
      }
      return;
    }
    final res = await s!.account!.login!(_account.text, _password.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res.error) {
      Log.e('Login failed', error: '$_sourceKey: ${res.errorMessage}');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(res.errorMessage ?? '登录失败')));
      }
    } else {
      if (context.mounted) context.pop();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${_source.name} 登录成功')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text('登录'),
        backgroundColor: context.pageBackground,
        actions: [
          if (_sourceKey == 'jm')
            IconButton(
              icon: const Icon(Icons.speed_rounded),
              onPressed: () =>
                  context.push('/settings/source?source=$_sourceKey'),
              tooltip: '测速选源',
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            // 源标识
            Container(
              height: 80,
              width: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colorScheme.primaryContainer,
                border: Border.all(color: context.borderColor),
              ),
              child: Text(
                _source.name[0],
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: context.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // 源切换
            Row(
              children: [
                for (final s in _sources)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.xs),
                    child: _SourceChip(
                      label: s.name,
                      active: s.key == _sourceKey,
                      onTap: () => setState(() => _sourceKey = s.key),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            _InputField(
              controller: _account,
              icon: Icons.person_outline_rounded,
              hint: _sourceKey == 'jm' ? '用户名' : '邮箱',
            ),
            const SizedBox(height: AppSpacing.md),
            _InputField(
              controller: _password,
              icon: Icons.lock_outline_rounded,
              hint: '密码',
              obscure: _obscure,
              suffix: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: context.tertiaryTextColor,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // 登录按钮
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _loading ? null : _login,
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: context.colorScheme.onPrimary,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text('登录'),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () async {
                    final uri = Uri.parse(_source.website);
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  },
                  child: Text(
                    '注册账号',
                    style: TextStyle(color: context.secondaryTextColor),
                  ),
                ),
                Text('·', style: TextStyle(color: context.tertiaryTextColor)),
                TextButton(
                  onPressed: () async {
                    final uri = Uri.parse('${_source.website}/forgot');
                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                  },
                  child: Text(
                    '忘记密码',
                    style: TextStyle(color: context.secondaryTextColor),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceOpt {
  const _SourceOpt({
    required this.key,
    required this.name,
    required this.website,
  });
  final String key;
  final String name;
  final String website;
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? context.colorScheme.primaryContainer
              : context.surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active
                ? context.colorScheme.onPrimaryContainer
                : context.secondaryTextColor,
          ),
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.icon,
    required this.hint,
    this.obscure = false,
    this.suffix,
  });
  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final bool obscure;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(color: context.primaryTextColor, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.tertiaryTextColor),
        prefixIcon: Icon(icon, color: context.tertiaryTextColor, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: context.surfaceColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
