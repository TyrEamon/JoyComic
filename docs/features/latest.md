# 最新（最近更新）功能设计

> 阶段3 功能集成参考文档。UI 已落地（首页"最近更新"网格 + 排行榜"最新" Tab），
> 本文档记录真实数据来源与集成方式。

## 功能定位

展示两源（禁漫 / 哔咔）最近更新的漫画流，支持分页加载与下拉刷新。

## 数据来源

### 禁漫

禁漫无独立的"最新列表"端点，但 `search` 接口支持 `order` 排序参数：

| order 值 | 含义 |
|---------|------|
| `mr` | 最新（按更新时间倒序）|
| `mp` | 最多（按人气）|
| `mv` | 评分 |

**最新流实现**：`JmNetwork().search('', 1, 'mr')`，空关键词返回全站最新。

> 注意：禁漫搜索返回的 `JmComicBrief` 不含封面缩略之外的元数据，
> 热度/收藏等需进详情页 `getComicInfo` 才有。列表页只展示 title / author / cover。

### 哔咔

哔咔无"最新"专用端点，但有 `categories` + `advanced-search`。最新流可用：

- 方案 A：`search('', 'dd', page)` —— `dd` 是按最新排序（`ua`=默认/`aa`=最多/`dd`=最新）。
- 方案 B：遍历分类页 `getCategories()` 后逐分类加载，但开销大，不推荐。

推荐**方案 A**，与禁漫统一用 search 空 keyword + 最新排序兜底。

## 集成点

| UI 位置 | 组件 | 调用 |
|---------|------|------|
| 首页"最近更新" | `ComicGrid` | `ComicSource.sources` 遍历，每源 search('',1,最新排序) 合并去重 |
| 排行榜"最新" Tab | `ComicGrid`（单源或合并）| 同上，支持切源筛选 |

## ViewModel 契约

```dart
abstract class LatestRepository {
  Future<Res<List<BaseComic>>> load(int page);
}
```

功能集成时实现为：遍历 `ComicSource.sources`，并行调各源 `searchPageData.loadPage('', page, [])`，
合并结果按源 chip 标识。

## 去重策略

两源同一作品 id 不同（禁漫数字 id / 哔咔 `_id`），无法按 id 去重。按 `title` 去重
（相似度高的保留热度更高者），或直接分源展示（保留 sourceKey，详情页路由时用对应源）。

## 待定问题

- 哔咔 search 空关键词是否返回全站最新，需实跑验证（可能返回空或推荐）。
- 若空 keyword 不可行，哔咔改用 `getCategories` + 每分类首项拼接，作为"发现"流。
