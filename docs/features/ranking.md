# 热门排行功能设计

> 阶段3 功能集成参考文档。UI 已落地（排行榜页：最新/热门/评分 3 Tab + 日/周/月/总榜筛选），
> 本文档记录真实数据来源与集成方式。

## 功能定位

按热度 / 评分维度，分时间窗口（日 / 周 / 月 / 总）展示两源排行。

## 数据来源

### 禁漫

`search(keyword, page, order)` 的 order 参数：
- `mp` = 最多（人气榜，按 likes/views 综合）
- `mv` = 评分

**禁漫无"时间窗口"概念**（无日榜/周榜），日/周/月筛选在禁漫侧无法实现。
禁漫侧只支持"总榜"，时间窗口筛选仅对哔咔生效（或禁漫侧灰显时间选项）。

### 哔咔

`RankingData` 契约（`ComicSource.categoryComicsData.rankingData`）提供排行端点：

```dart
class RankingData {
  final Map<String, String> options; // 时间窗口选项 key→label
  final Future<Res<List<BaseComic>>> Function(String option, int page) load;
}
```

哔咔的 `options` 即时间窗口（如 H24=24小时/D7=7天/D30=30天），`load(option, page)` 返回排行列表。

> ⚠️ 当前 `built_in/picacg.dart` 未声明 `categoryComicsData`，需补 `RankingData` 声明。
> 哔咔排行端点路径需参考  原版（`/comics/...`），集成时核实。

## 时间窗口映射

| UI 选项 | 禁漫 | 哔咔 |
|---------|------|------|
| 日榜 | 不支持（灰显或回落总榜）| RankingData options 选 H24 |
| 周榜 | 不支持 | options 选 D7 |
| 月榜 | 不支持 | options 选 D30 |
| 总榜 | search('',1,'mp') | options 选 ALL/总 |

## 集成点

| UI 位置 | 组件 | 调用 |
|---------|------|------|
| 首页工具栏"热门排行" | → push `/ranking?tab=hot` | 同排行榜页 |
| 排行榜页"热门" Tab | `ComicGrid` | 禁漫 search(...,'mp') + 哔咔 RankingData.load |
| 排行榜页"评分" Tab | `ComicGrid` | 禁漫 search(...,'mv') + 哔咔（需核实评分端点）|

## ViewModel 契约

```dart
abstract class RankingRepository {
  Future<Res<List<BaseComic>>> load({
    required String dimension, // 'hot' | 'rating' | 'latest'
    required String range,     // 'day' | 'week' | 'month' | 'total'
    required int page,
  });
}
```

## 待定问题

- 哔咔评分排行端点存在性需核实（ 原版未必有评分榜）。
- 时间窗口在禁漫侧的兜底：选日/周/月时，禁漫结果用总榜填充（标注"禁漫无时间榜"），
  或禁漫侧禁用时间筛选选项。
