/// Reverse-image search with SauceNAO originals and separate source matches.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/sauce_nao_config_store.dart';
import '../../foundation/sauce_nao_search.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_safe_area.dart';
import '../common/widgets/comic_grid.dart';
import '../common/widgets/empty_state.dart';

typedef ImageSearchPicker = Future<XFile?> Function(ImageSource source);
typedef SauceNaoPageSearch =
    Future<List<SauceResult>> Function(File image, String apiKey);
typedef InternalImageMatcher =
    Future<List<ComicGridItem>> Function(String title);
typedef ImageSearchExternalLauncher = Future<bool> Function(Uri uri);

Future<List<ComicGridItem>> searchInternalImageMatches(
  String title, {
  Iterable<ComicSource>? sources,
}) async {
  final matches = <String, ComicGridItem>{};
  var attempted = 0;
  var failed = 0;
  for (final source in sources ?? ComicSource.sources) {
    if (source.key != 'jm' && source.key != 'picacg') continue;
    final loader = source.searchPageData?.loadPage;
    if (loader == null) continue;
    attempted++;
    try {
      final result = await loader(title, 1, const <String>[]);
      if (result.error) {
        failed++;
        continue;
      }
      for (final comic in result.data) {
        matches['${source.key}:${comic.id}'] = ComicGridItem(
          id: comic.id,
          title: comic.title,
          coverUrl: comic.cover,
          subtitle: comic.subTitle,
          sourceKey: source.key,
        );
      }
    } catch (_) {
      failed++;
    }
  }
  if (attempted > 0 && failed == attempted) {
    throw StateError('all internal image-search sources failed');
  }
  return List<ComicGridItem>.unmodifiable(matches.values);
}

class ImageSearchPage extends StatefulWidget {
  const ImageSearchPage({
    super.key,
    this.configStore,
    this.pickImage,
    this.sauceSearch,
    this.internalMatcher,
    this.externalLauncher,
  });

  final SauceNaoConfigStore? configStore;
  final ImageSearchPicker? pickImage;
  final SauceNaoPageSearch? sauceSearch;
  final InternalImageMatcher? internalMatcher;
  final ImageSearchExternalLauncher? externalLauncher;

  @override
  State<ImageSearchPage> createState() => _ImageSearchPageState();
}

class _ImageSearchPageState extends State<ImageSearchPage> {
  late final SauceNaoConfigStore _configStore =
      widget.configStore ?? SauceNaoConfigStore();
  final TextEditingController _keyController = TextEditingController();

  String? _apiKey;
  File? _picked;
  bool _loadingConfig = true;
  bool _searching = false;
  int _searchGeneration = 0;
  List<SauceResult> _sauceResults = const <SauceResult>[];
  List<ComicGridItem> _internalResults = const <ComicGridItem>[];
  bool _hasSearched = false;

  ImageSearchPicker get _picker =>
      widget.pickImage ??
      (source) => ImagePicker().pickImage(source: source, imageQuality: 85);

  SauceNaoPageSearch get _search =>
      widget.sauceSearch ??
      (image, key) => SauceNaoSearch().search(image, apiKey: key);

  InternalImageMatcher get _matcher =>
      widget.internalMatcher ?? (title) => searchInternalImageMatches(title);

  ImageSearchExternalLauncher get _launcher =>
      widget.externalLauncher ??
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final key = await _configStore.readApiKey();
      if (!mounted) return;
      setState(() {
        _apiKey = key;
        _loadingConfig = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingConfig = false);
      _showMessage('无法读取 SauceNAO API Key，请重新设置');
    }
  }

  Future<void> _pick(ImageSource source) async {
    if (_loadingConfig) return;
    final key = _apiKey?.trim();
    if (key == null || key.isEmpty) {
      _showMessage('请先设置 SauceNAO API Key');
      await _showKeyDialog();
      return;
    }

    XFile? selected;
    try {
      selected = await _picker(source);
    } on PlatformException catch (error) {
      _showMessage(_messageForPickerPlatformError(source, error.code));
      return;
    } catch (_) {
      _showMessage(source == ImageSource.camera ? '无法拍摄图片' : '无法选择图片');
      return;
    }
    if (selected == null || !mounted) return;

    final generation = ++_searchGeneration;
    final image = File(selected.path);
    setState(() {
      _picked = image;
      _searching = true;
      _hasSearched = false;
      _sauceResults = const <SauceResult>[];
      _internalResults = const <ComicGridItem>[];
    });

    try {
      final originals = await _search(image, key);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _sauceResults = originals;
        _hasSearched = true;
      });

      final title = SauceNaoSearch.bestTitle(originals);
      if (title != null) {
        try {
          final matches = await _matcher(title);
          if (!mounted || generation != _searchGeneration) return;
          setState(() => _internalResults = matches);
        } catch (_) {
          if (mounted && generation == _searchGeneration) {
            _showMessage('站内漫画匹配失败，已保留 SauceNAO 结果');
          }
        }
      }
    } on SauceNaoException catch (error) {
      if (mounted && generation == _searchGeneration) {
        _showMessage(_messageForSauceError(error.kind));
      }
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        _showMessage('SauceNAO 搜索失败，请稍后重试');
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _showKeyDialog() async {
    _keyController.text = '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('设置 SauceNAO API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('在 saucenao.com 注册后，从搜索 API 页面复制 Key。'),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('saucenao-key-field'),
              controller: _keyController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API Key'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final value = _keyController.text.trim();
              if (value.isEmpty) return;
              try {
                await _configStore.saveApiKey(value);
              } catch (_) {
                if (mounted) _showMessage('无法保存 SauceNAO API Key，请稍后重试');
                return;
              }
              if (!mounted || !dialogContext.mounted) return;
              setState(() => _apiKey = value);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('保存 Key'),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternal(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      _showMessage('外部链接无效');
      return;
    }
    try {
      if (!await _launcher(uri)) _showMessage('无法打开外部链接');
    } catch (_) {
      _showMessage('无法打开外部链接');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text('以图搜图'),
        backgroundColor: context.pageBackground,
        actions: <Widget>[
          TextButton.icon(
            onPressed: _showKeyDialog,
            icon: const Icon(Icons.vpn_key_outlined),
            label: const Text('设置 Key'),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(child: _buildPickerArea()),
          if (_searching)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          if (_hasSearched) ...<Widget>[
            _sectionTitle('SauceNAO 原始结果'),
            if (_sauceResults.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: EmptyState(title: 'SauceNAO 未找到相似结果'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                sliver: SliverList.builder(
                  itemCount: _sauceResults.length,
                  itemBuilder: (_, index) => _SauceResultCard(
                    result: _sauceResults[index],
                    onOpen: _openExternal,
                  ),
                ),
              ),
            _sectionTitle('内部漫画匹配'),
            SliverToBoxAdapter(
              child: _internalResults.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.lg),
                      child: EmptyState(title: '暂无站内匹配'),
                    )
                  : ComicGrid(
                      items: _internalResults,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      onItemTap: (item) => context.push(
                        '/detail/${item.sourceKey ?? 'jm'}/${item.id}',
                      ),
                    ),
            ),
          ],
          SliverToBoxAdapter(
            child: SizedBox(height: bottomContentInset(context)),
          ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _sectionTitle(String title) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    ),
  );

  Widget _buildPickerArea() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                _apiKey == null ? Icons.key_off_outlined : Icons.key_outlined,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(_apiKey == null ? 'SauceNAO Key 未配置' : 'SauceNAO Key 已配置'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: AppRadius.brLg,
                border: Border.all(color: context.borderColor),
              ),
              child: _picked == null
                  ? Center(
                      child: Text(
                        '选择一张漫画截图',
                        style: TextStyle(color: context.tertiaryTextColor),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: AppRadius.brLg,
                      child: Image.file(
                        _picked!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_outlined),
                label: const Text('从相册选择'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _pick(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('拍摄'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openExternal('https://soutubot.moe/'),
                icon: const Icon(Icons.open_in_browser_outlined),
                label: const Text('soutubot'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SauceResultCard extends StatelessWidget {
  const _SauceResultCard({required this.result, required this.onOpen});

  final SauceResult result;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final external = result.extUrls.isEmpty ? null : result.extUrls.first;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 80,
              height: 80,
              child: result.thumbnail.isEmpty
                  ? const Icon(Icons.image_search_outlined)
                  : Image.network(
                      result.thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '相似度 ${result.similarity.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: context.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (result.source.isNotEmpty) Text(result.source),
                  if (result.title != null)
                    Text(
                      result.title!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  if (result.author != null) Text('作者：${result.author}'),
                  if (external != null)
                    TextButton.icon(
                      onPressed: () => onOpen(external),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('查看来源'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _messageForPickerPlatformError(ImageSource source, String code) {
  final normalizedCode = code.toLowerCase();
  final isPermissionError =
      normalizedCode.contains('denied') ||
      normalizedCode.contains('restricted') ||
      normalizedCode.contains('permission');
  if (isPermissionError) {
    return source == ImageSource.camera ? '请允许使用相机后重试' : '请允许访问相册后重试';
  }
  return source == ImageSource.camera ? '相机不可用，请改用相册选择' : '无法访问相册';
}

String _messageForSauceError(SauceNaoErrorKind kind) => switch (kind) {
  SauceNaoErrorKind.missingKey => '请先设置 SauceNAO API Key',
  SauceNaoErrorKind.invalidKey => 'SauceNAO API Key 无效，请重新设置',
  SauceNaoErrorKind.rateLimited => 'SauceNAO 请求过于频繁，请稍后重试',
  SauceNaoErrorKind.network => 'SauceNAO 网络连接失败，请稍后重试',
  SauceNaoErrorKind.malformed => 'SauceNAO 返回数据格式错误',
};
