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

const double _distributionPageDonutAspectRatio = 1.32;
const double _distributionPageDonutRadiusFactor = 0.44;

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
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
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
          final selected = _selectedValue(values);
          final total = stats.totalFavorites;
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
                      compact: true,
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
                      compact: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _Panel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Column(
                  children: <Widget>[
                    DistributionDonut(
                      values: values,
                      selectedName: selected.name,
                      displayValue: selected,
                      unit: '本',
                      percentageTotal: total,
                      percentageLabel: '占全部收藏',
                      aspectRatio: _distributionPageDonutAspectRatio,
                      radiusFactor: _distributionPageDonutRadiusFactor,
                      onSelected: (value) =>
                          setState(() => _selectedName = value.name),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '圆环按全部${widget.isArtist ? '画师署名' : '标签出现'}次数分配，已展开所有${widget.isArtist ? '画师' : '标签'}；收藏占比仍以 $total 本总收藏为基数。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: context.tertiaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                widget.isArtist ? '画师分布详情' : '标签偏好详情',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              _Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: <Widget>[
                    for (var index = 0; index < values.length; index++)
                      _DistributionRow(
                        value: values[index],
                        total: total,
                        unit: '本',
                        color: distributionColor(context, index),
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

  RankedStat _selectedValue(List<RankedStat> values) {
    final name = _selectedName;
    if (name != null) {
      for (final value in values) {
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
    this.percentageTotal,
    this.percentageLabel,
    this.aspectRatio = 1.15,
    this.radiusFactor = 0.34,
    required this.onSelected,
  });

  final List<RankedStat> values;
  final String selectedName;
  final RankedStat? displayValue;
  final String unit;
  final int? percentageTotal;
  final String? percentageLabel;
  final double aspectRatio;
  final double radiusFactor;
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
    final colors = <Color>[
      for (var index = 0; index < values.length; index++)
        distributionColor(context, index),
    ];
    final externalTotal = percentageTotal;
    final externalLabel = percentageLabel;
    final displayTotal = externalTotal ?? total;
    final semanticsPrefix = externalLabel == null ? '' : '$externalLabel，';
    return Semantics(
      label: '${selected.name}，${selected.count}$unit，'
          '$semanticsPrefix${_percent(selected.count, displayTotal)}',
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final hit = _hitDonut(
                details.localPosition,
                constraints.biggest,
                values,
                radiusFactor,
              );
              if (hit != null) onSelected(hit);
            },
            child: CustomPaint(
              painter: _DonutPainter(
                values: values,
                colors: colors,
                selectedName: segmentSelected.name,
                trackColor: context.borderColor.withValues(alpha: 0.55),
                radiusFactor: radiusFactor,
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
                          fontSize: 17,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '${selected.count} $unit',
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        externalTotal == null || externalLabel == null
                            ? _percent(selected.count, total)
                            : '$externalLabel ${_percent(selected.count, externalTotal)}',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: context.tertiaryTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (externalTotal != null && externalLabel != null)
                        Text(
                          '圆环份额 ${_percent(selected.count, total)}',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.25,
                            color: context.tertiaryTextColor,
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
    required this.radiusFactor,
  });

  final List<RankedStat> values;
  final List<Color> colors;
  final String selectedName;
  final Color trackColor;
  final double radiusFactor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * radiusFactor;
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
    final minimumCount = values.fold<int>(
      values.first.count,
      (minimum, value) => math.min(minimum, value.count),
    );
    final averageSweep = math.pi * 2 / values.length;
    final minimumSweep = math.pi * 2 * minimumCount / total;
    final gap = math.min(
      0.018,
      math.min(averageSweep * 0.08, minimumSweep * 0.35),
    );
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
      oldDelegate.colors != colors ||
      oldDelegate.selectedName != selectedName ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.radiusFactor != radiusFactor;
}

RankedStat? _hitDonut(
  Offset position,
  Size size,
  List<RankedStat> values,
  double radiusFactor,
) {
  final center = size.center(Offset.zero);
  final delta = position - center;
  final radius = math.min(size.width, size.height) * radiusFactor;
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

Color distributionColor(BuildContext context, int index) {
  final lightness = Theme.of(context).brightness == Brightness.dark ? 0.64 : 0.48;
  final hue = (4 + index * 137.508) % 360;
  return HSLColor.fromAHSL(1, hue, 0.62, lightness).toColor();
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.stats});

  final CollectionStatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final coral = context.colorScheme.primary;
    final mint = context.successColor;
    final softPink = Color.lerp(coral, context.secondaryTextColor, 0.24)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardHeight = (constraints.maxWidth * 0.31)
            .clamp(100.0, 112.0)
            .toDouble();
        Widget largeCard({
          required String label,
          required String value,
          required IconData icon,
          required Color emphasisColor,
        }) => Expanded(
          child: SizedBox(
            height: cardHeight,
            child: _MetricCard(
              label: label,
              value: value,
              icon: icon,
              emphasisColor: emphasisColor,
            ),
          ),
        );

        return Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                largeCard(
                  label: '总收藏',
                  value: '${stats.totalFavorites}',
                  icon: Icons.library_books_rounded,
                  emphasisColor: coral,
                ),
                const SizedBox(width: AppSpacing.sm),
                largeCard(
                  label: '已读',
                  value: '${stats.read}',
                  icon: Icons.check_circle_outline_rounded,
                  emphasisColor: mint,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: <Widget>[
                largeCard(
                  label: '未读',
                  value: '${stats.unread}',
                  icon: Icons.visibility_off_outlined,
                  emphasisColor: softPink,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SizedBox(
                    height: cardHeight,
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: _CompactMetricCard(
                            label: '画师',
                            value: '${stats.artistCount}',
                            accentColor: coral,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Expanded(
                          child: _CompactMetricCard(
                            label: '标签',
                            value: '${stats.tagCount}',
                            accentColor: softPink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CompactMetricCard extends StatelessWidget {
  const _CompactMetricCard({
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    borderRadius: AppRadius.brMd,
    borderColor: accentColor.withValues(alpha: 0.10),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: accentColor.withValues(alpha: 0.88),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          value,
          maxLines: 1,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.icon,
    this.accent = false,
    this.compact = false,
    this.emphasisColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool accent;
  final bool compact;
  final Color? emphasisColor;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: compact
        ? const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: AppSpacing.sm,
          )
        : const EdgeInsets.all(AppSpacing.md),
    borderColor: emphasisColor?.withValues(alpha: 0.14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: 18,
                color:
                    emphasisColor ??
                    (accent
                        ? context.successColor
                        : context.colorScheme.primary),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 13 : null,
                color: context.secondaryTextColor,
              ),
            ),
          ],
        ),
        if (compact) const SizedBox(height: 6) else const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: compact ? 26 : 30,
            fontWeight: FontWeight.w700,
            color: emphasisColor,
          ),
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
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xxs,
          ),
          color: selected ? context.colorScheme.primaryContainer.withValues(alpha: 0.22) : null,
          child: Row(
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  value.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${value.count}$unit',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 50,
                child: Text(
                  _percent(value.count, total),
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.secondaryTextColor,
                    fontWeight: FontWeight.w500,
                  ),
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
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.borderRadius = AppRadius.brLg,
    this.borderColor,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: context.surfaceColor,
      borderRadius: borderRadius,
      border: Border.all(color: borderColor ?? context.borderColor),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

String _percent(int value, int total) =>
    total == 0 ? '0%' : '${(value * 100 / total).toStringAsFixed(1)}%';
