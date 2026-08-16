/// Personal collection analytics pages.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../common/widgets/empty_state.dart';
import 'collection_stats.dart';

class CollectionStatsPage extends StatefulWidget {
  const CollectionStatsPage({super.key});

  @override
  State<CollectionStatsPage> createState() => _CollectionStatsPageState();
}

class _CollectionStatsPageState extends State<CollectionStatsPage> {
  late final CollectionStatsController _controller =
      CollectionStatsController()..load();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text('数据统计'),
        actions: <Widget>[
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => IconButton(
              tooltip: _controller.enriching ? '正在补全统计数据' : '补全统计数据',
              onPressed: _controller.canEnrich
                  ? _controller.enrichMissingMetadata
                  : null,
              icon: _controller.enriching
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_graph_rounded),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final stats = _controller.snapshot;
          if (_controller.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (stats.totalFavorites == 0) {
            return const EmptyState(
              icon: Icons.insights_outlined,
              title: '还没有可统计的收藏',
              subtitle: '先收藏一些作品，再回来看看你的偏好画像',
            );
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
            ),
            children: <Widget>[
              _SummaryGrid(stats: stats),
              const SizedBox(height: AppSpacing.md),
              if (stats.metadataComplete < stats.totalFavorites) ...<Widget>[
                _MetadataCoverageCard(
                  controller: _controller,
                  onEnrich: _controller.enrichMissingMetadata,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _ReadingCard(stats: stats),
              const SizedBox(height: AppSpacing.xl),
              _RankingCard(
                title: '画师排行',
                values: stats.artists.take(5).toList(growable: false),
                unit: '本',
                onViewAll: stats.artists.isEmpty
                    ? null
                    : () => context.push('/stats/artists'),
              ),
              const SizedBox(height: AppSpacing.xl),
              _RankingCard(
                title: '标签偏好',
                values: stats.tags.take(5).toList(growable: false),
                unit: '次',
                onViewAll: stats.tags.isEmpty
                    ? null
                    : () => context.push('/stats/tags'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ArtistStatsPage extends StatelessWidget {
  const ArtistStatsPage({super.key});

  @override
  Widget build(BuildContext context) => const _DistributionPage(isArtist: true);
}

class TagStatsPage extends StatelessWidget {
  const TagStatsPage({super.key});

  @override
  Widget build(BuildContext context) => const _DistributionPage(isArtist: false);
}

class _DistributionPage extends StatefulWidget {
  const _DistributionPage({required this.isArtist});

  final bool isArtist;

  @override
  State<_DistributionPage> createState() => _DistributionPageState();
}

class _DistributionPageState extends State<_DistributionPage> {
  late final CollectionStatsController _controller =
      CollectionStatsController()..load();
  String? _selectedName;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isArtist ? '画师收藏分布' : '标签偏好分布';
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(title: Text(title)),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = _controller.snapshot;
          final values = widget.isArtist ? stats.artists : stats.tags;
          if (values.isEmpty) {
            return EmptyState(
              icon: widget.isArtist
                  ? Icons.brush_outlined
                  : Icons.sell_outlined,
              title: widget.isArtist ? '暂无画师数据' : '暂无标签数据',
              subtitle: widget.isArtist
                  ? '收藏详情中还没有可用的画师信息'
                  : '返回数据统计页补全收藏详情后再试',
            );
          }
          final donutValues = collapseDistribution(values, limit: 7);
          final selected = _selectedValue(values, donutValues);
          final total = values.fold(0, (sum, value) => sum + value.count);
          return ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
            ),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _MetricCard(
                      label: widget.isArtist ? '总收藏' : '标签数',
                      value: widget.isArtist
                          ? '${stats.totalFavorites}'
                          : '${stats.tagCount}',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _MetricCard(
                      label: widget.isArtist ? '画师总数' : '出现次数',
                      value: widget.isArtist
                          ? '${stats.artistCount}'
                          : '${stats.tagOccurrences}',
                      accent: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _Panel(
                child: DistributionDonut(
                  values: donutValues,
                  selectedName: selected.name,
                  displayValue: selected,
                  unit: widget.isArtist ? '本' : '次',
                  onSelected: (value) =>
                      setState(() => _selectedName = value.name),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                widget.isArtist ? '画师分布详情' : '标签偏好详情',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.sm),
              _Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    for (var index = 0; index < values.length; index++)
                      _DistributionRow(
                        value: values[index],
                        total: total,
                        unit: widget.isArtist ? '本' : '次',
                        color: chartColors(context)[
                            math.min(index, chartColors(context).length - 1)],
                        selected: selected.name == values[index].name,
                        showDivider: index != values.length - 1,
                        onTap: () =>
                            setState(() => _selectedName = values[index].name),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  RankedStat _selectedValue(
    List<RankedStat> values,
    List<RankedStat> donutValues,
  ) {
    final name = _selectedName;
    if (name != null) {
      for (final value in <RankedStat>[...values, ...donutValues]) {
        if (value.name == name) return value;
      }
    }
    return values.first;
  }
}

class DistributionDonut extends StatelessWidget {
  const DistributionDonut({
    super.key,
    required this.values,
    required this.selectedName,
    this.displayValue,
    required this.unit,
    required this.onSelected,
  });

  final List<RankedStat> values;
  final String selectedName;
  final RankedStat? displayValue;
  final String unit;
  final ValueChanged<RankedStat> onSelected;

  @override
  Widget build(BuildContext context) {
    final total = values.fold(0, (sum, value) => sum + value.count);
    final segmentSelected = values.firstWhere(
      (value) => value.name == selectedName,
      orElse: () => values.firstWhere(
        (value) => value.name == '其他',
        orElse: () => values.first,
      ),
    );
    final selected = displayValue ?? segmentSelected;
    final colors = chartColors(context);
    return Semantics(
      label: '${selected.name}，${selected.count}$unit，'
          '${_percent(selected.count, total)}',
      child: AspectRatio(
        aspectRatio: 1.15,
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final hit = _hitDonut(
                details.localPosition,
                constraints.biggest,
                values,
              );
              if (hit != null) onSelected(hit);
            },
            child: CustomPaint(
              painter: _DonutPainter(
                values: values,
                colors: colors,
                selectedName: segmentSelected.name,
                trackColor: context.borderColor.withValues(alpha: 0.55),
              ),
              child: Center(
                child: SizedBox(
                  width: constraints.maxWidth * 0.42,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        selected.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colorScheme.primary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text('${selected.count} $unit'),
                      Text(
                        _percent(selected.count, total),
                        style: TextStyle(
                          color: context.secondaryTextColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.values,
    required this.colors,
    required this.selectedName,
    required this.trackColor,
  });

  final List<RankedStat> values;
  final List<Color> colors;
  final String selectedName;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * 0.34;
    const width = 18.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
    final total = values.fold(0, (sum, value) => sum + value.count);
    if (total == 0) return;
    var start = -math.pi / 2;
    const gap = 0.018;
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      final rawSweep = math.pi * 2 * value.count / total;
      final sweep = math.max(0.0, rawSweep - gap);
      canvas.drawArc(
        rect,
        start + gap / 2,
        sweep,
        false,
        Paint()
          ..color = colors[math.min(index, colors.length - 1)]
          ..style = PaintingStyle.stroke
          ..strokeWidth = value.name == selectedName ? width + 5 : width
          ..strokeCap = StrokeCap.butt,
      );
      start += rawSweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.selectedName != selectedName ||
      oldDelegate.trackColor != trackColor;
}

RankedStat? _hitDonut(Offset position, Size size, List<RankedStat> values) {
  final center = size.center(Offset.zero);
  final delta = position - center;
  final radius = math.min(size.width, size.height) * 0.34;
  final distance = delta.distance;
  if (distance < radius - 26 || distance > radius + 26) return null;
  var angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
  if (angle < 0) angle += math.pi * 2;
  final total = values.fold(0, (sum, value) => sum + value.count);
  var cursor = 0.0;
  for (final value in values) {
    cursor += math.pi * 2 * value.count / total;
    if (angle <= cursor) return value;
  }
  return values.last;
}

List<Color> chartColors(BuildContext context) => <Color>[
  context.colorScheme.primary,
  context.successColor,
  const Color(0xFFD69A9B),
  const Color(0xFFB99A9F),
  const Color(0xFF71CFAE),
  const Color(0xFFA8A7AC),
  const Color(0xFF77757D),
  context.borderColor,
];

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.stats});

  final CollectionStatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String, IconData, bool)>[
      ('总收藏', '${stats.totalFavorites}', Icons.library_books_rounded, false),
      ('已读', '${stats.read}', Icons.check_circle_outline_rounded, true),
      ('未读', '${stats.unread}', Icons.visibility_off_outlined, false),
      ('画师', '${stats.artistCount}', Icons.brush_outlined, false),
      ('标签', '${stats.tagCount}', Icons.sell_outlined, false),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - AppSpacing.sm) / 2;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final item in items)
              SizedBox(
                width: width,
                child: _MetricCard(
                  label: item.$1,
                  value: item.$2,
                  icon: item.$3,
                  accent: item.$4,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.icon,
    this.accent = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: 18,
                color: accent
                    ? context.successColor
                    : context.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(label, style: TextStyle(color: context.secondaryTextColor)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          value,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _MetadataCoverageCard extends StatelessWidget {
  const _MetadataCoverageCard({
    required this.controller,
    required this.onEnrich,
  });

  final CollectionStatsController controller;
  final VoidCallback onEnrich;

  @override
  Widget build(BuildContext context) {
    final stats = controller.snapshot;
    final label = controller.enriching
        ? '正在补全 ${controller.enrichmentDone}/${controller.enrichmentTotal}'
        : '标签数据已补全 ${stats.metadataComplete}/${stats.totalFavorites}';
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.data_usage_rounded, color: context.colorScheme.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              TextButton(
                onPressed: controller.canEnrich ? onEnrich : null,
                child: const Text('补全数据'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          LinearProgressIndicator(
            value: controller.enriching && controller.enrichmentTotal > 0
                ? controller.enrichmentDone / controller.enrichmentTotal
                : stats.metadataRatio,
            minHeight: 6,
            borderRadius: AppRadius.brSm,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            controller.enrichmentFailed == 0
                ? '画师可直接统计；完整标签需要读取作品详情，结果会保存到本地。'
                : '${controller.enrichmentFailed} 项暂时读取失败，可以稍后重试。',
            style: TextStyle(fontSize: 12, color: context.tertiaryTextColor),
          ),
        ],
      ),
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.stats});

  final CollectionStatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final values = <RankedStat>[
      RankedStat('已读', stats.read),
      RankedStat('未读', stats.unread),
    ];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('阅读状态', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          Row(
            children: <Widget>[
              Expanded(
                child: DistributionDonut(
                  values: values,
                  selectedName: '已读',
                  unit: '本',
                  onSelected: (_) {},
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Legend(label: '已读', value: stats.read, color: context.colorScheme.primary),
                  const SizedBox(height: AppSpacing.md),
                  _Legend(label: '未读', value: stats.unread, color: context.successColor),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: AppSpacing.xs),
      Text('$label  $value'),
    ],
  );
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.title,
    required this.values,
    required this.unit,
    required this.onViewAll,
  });

  final String title;
  final List<RankedStat> values;
  final String unit;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
            if (onViewAll != null)
              TextButton.icon(
                onPressed: onViewAll,
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
                label: const Text('查看全部'),
              ),
          ],
        ),
        if (values.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: Text('暂无数据', style: TextStyle(color: context.tertiaryTextColor))),
          )
        else
          for (var index = 0; index < values.length; index++) ...<Widget>[
            if (index > 0) const SizedBox(height: AppSpacing.md),
            _RankingBar(
              value: values[index],
              max: values.first.count,
              unit: unit,
              color: chartColors(context)[math.min(index, chartColors(context).length - 1)],
            ),
          ],
      ],
    ),
  );
}

class _RankingBar extends StatelessWidget {
  const _RankingBar({required this.value, required this.max, required this.unit, required this.color});
  final RankedStat value;
  final int max;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(child: Text(value.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: AppSpacing.sm),
          Text('${value.count}$unit', style: TextStyle(color: context.secondaryTextColor)),
        ],
      ),
      const SizedBox(height: AppSpacing.xs),
      ClipRRect(
        borderRadius: AppRadius.brSm,
        child: LinearProgressIndicator(
          value: max == 0 ? 0 : value.count / max,
          minHeight: 10,
          color: color,
          backgroundColor: context.borderColor.withValues(alpha: 0.45),
        ),
      ),
    ],
  );
}

class _DistributionRow extends StatelessWidget {
  const _DistributionRow({
    required this.value,
    required this.total,
    required this.unit,
    required this.color,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });
  final RankedStat value;
  final int total;
  final String unit;
  final Color color;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          color: selected ? context.colorScheme.primaryContainer.withValues(alpha: 0.22) : null,
          child: Row(
            children: <Widget>[
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(value.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500))),
              const SizedBox(width: AppSpacing.sm),
              Text('${value.count}$unit'),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 54,
                child: Text(
                  _percent(value.count, total),
                  textAlign: TextAlign.end,
                  style: TextStyle(color: context.secondaryTextColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
      if (showDivider)
        const Divider(
          height: 1,
          indent: AppSpacing.md,
          endIndent: AppSpacing.md,
        ),
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(AppSpacing.md)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: context.surfaceColor,
      borderRadius: AppRadius.brLg,
      border: Border.all(color: context.borderColor),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

String _percent(int value, int total) =>
    total == 0 ? '0%' : '${(value * 100 / total).toStringAsFixed(1)}%';
