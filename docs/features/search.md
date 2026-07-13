# 搜索功能设计

> 阶段3 功能集成参考文档。UI 已落地（搜索页：搜索框 + 历史 + 热门词 + 结果网格），
> 本文档记录真实数据来源与集成方式。

## 功能定位

跨两源（禁漫 / 哔咔）并行搜索，结果合并去重展示，支持源筛选与搜索历史。

## 数据来源

### 禁漫

`JmNetwork().search(keyword, page, order)`，**免登录可搜**（token 仅 `md5(时间戳+盐)`，非 session）。
返回 `List<JmComicBrief>`，含 id / name / author / categories。

order 参数：`mr`=最新 / `mp`=最多 / `mv`=评分。

### 哔咔

`PicacgNetwork().search(keyword, sort, page)`，**需登录**（token 校验）。
返回 `List<ComicItemBrief>`，含 id / title / author / tags / likes。

sort 参数：`ua`=默认 / `aa`=最多 / `dd`=最新。

## 集成点

| UI 位置 | 组件 | 调用 |
|---------|------|------|
| 首页右上搜索图标 | → push `/search/all` | 搜索页（全部源）|
| 分类页搜索框 | → push `/search/all` | 同上 |
| 搜索页结果区 | `ComicGrid` | 多源并行 search |
| 搜索页"搜索历史" | chip 列表 | 本地 shared_preferences |
| 搜索页"热门搜索" | chip 列表 | 哔咔 `getHotTags()` + 禁漫本地预设 |

## 多源并行搜索

```dart
Future<List<ComicGridItem>> searchAcrossSources(String keyword, int page) async {
  final futures = ComicSource.sources
      .where((s) => s.searchPageData?.loadPage != null)
      .map((s) async {
        final res = await s.searchPageData!.loadPage!(keyword, page, const []);
        if (res.error) return <ComicGridItem>[];
        return res.data.map((b) => ComicGridItem(
          id: b.id,
          title: b.title,
          coverUrl: b.cover,
          subtitle: b.subTitle,
          sourceKey: s.key,
        )).toList();
      });
  final results = await Future.wait(futures);
  return results.expand((e) => e).toList();
}
```

> 每项带 `sourceKey`，点击跳 `/detail/{sourceKey}/{id}` 详情页。

## 源筛选

搜索页顶部加源筛选 chip：全部 / 禁漫 / 哔咔。选中单源时只调该源。

## 搜索历史

- 存储：`shared_preferences`，key `search_history`，JSON 数组，最多 20 条。
- 去重：新搜索词置顶，重复的移到首位。
- 清空：搜索首页历史区右上"垃圾桶"按钮。

## 热门搜索词

- 哔咔：`PicacgNetwork().getHotTags()` → `List<String>`。
- 禁漫：无热门词端点，用本地预设词兜底（恋爱/同人/校园 等）。
- 合并展示，标注来源不必要（用户只关心词本身）。

## ViewModel 契约

```dart
class SearchViewModel extends ChangeNotifier {
  String keyword = '';
  List<ComicGridItem> results = [];
  bool loading = false;
  String? filterSource;  // null=全部, 'jm'/'picacg'=单源

  Future<void> search(String kw);
  Future<void> loadMore();  // page++ 继续搜
}
```

## 已知约束

- 哔咔搜索需登录：未登录时跳登录页或灰显哔咔源。
- 禁漫搜索空关键词返回全站最新（可用于"发现"兜底）。
- 两源分页 maxPage：禁漫 search 不返回 maxPage（需靠"空结果"判定到底），
  哔咔 search 的 `Res.subData` 含 maxPage。
