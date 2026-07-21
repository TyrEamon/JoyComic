# 收藏库功能设计

> 阶段3 功能集成参考文档。UI 已落地（收藏页：多文件夹 + 排序 + 网格 + 空态），
> 数据来源参考 `clone/joycomic-ios` 的 `LibraryScreen.tsx`。

## 功能定位

展示与管理两源（禁漫 / 哔咔）的云端收藏 + 本地收藏，支持多文件夹、排序、离线访问。

## 数据来源

### 禁漫（参考 ios `favorite` 端点）

joycomic-ios `api/endpoints.ts`：

```ts
// 收藏列表（带文件夹、分页、排序）
fetchFavorite({ page, o, folder_id })
  → encryptedGet('favorite', { page, o, folder_id })  // o='mr'最新/'mp'最多

// 收藏文件夹列表
fetchFavoriteFolders()
  → encryptedGet('favorite_folder')

// 添加/取消收藏
fetchFavoriteAlbum({ aid }) // 切换收藏态
// 创建/删除/重命名文件夹
fetchFavoriteFolderCreate({ name })
fetchFavoriteFolderDel({ folder_id })
fetchFavoriteFolderEdit({ folder_id, name })
// 移动到文件夹
fetchFavoriteMove({ folder_id, aid })
```

**禁漫支持多文件夹**（`favorite_folder` 增删改 + `favorite_move`）。

### 哔咔

`ComicSource.favoriteData` 契约已声明，`PicacgNetwork` 已实现：

```dart
// picacg_network.dart
favouriteOrUnfavourite(id) // 切换收藏
// 收藏列表需补 load 方法
```

> ⚠️ 哔咔 `favoriteData.load` / `loadFolders` / `addOrDelFavorite` 在
> `built_in/picacg.dart` 尚未声明，集成时补全 `favoriteData` 字段。
> 哔咔收藏是否多文件夹取决于 API（ 原版有 folder 概念）。

## 集成点

| UI 位置 | 组件 | 调用 |
|---------|------|------|
| 底部 Tab"收藏" | `ComicGrid` + 文件夹 tab | 两源 favorite 合并 |
| 收藏页文件夹 tab | chip 横滑 | `loadFolders` + 切换 folder_id |
| 收藏页排序条 | 文字按钮 | sort 参数切换 |
| 详情页收藏按钮 | `StickyActionBar` | `addOrDelFavorite` |
| 我的页"我的收藏" | → push /favorites | 同收藏页 |

## 双源收藏合并

joycomic-ios `LibraryScreen` 按 source 切换（jm/pica），不混合展示。
joycomic 建议：

- **默认全部源合并**：两源收藏并行加载，结果带 `sourceKey`。
- **源筛选 chip**：顶部加"全部 / 禁漫 / 哔咔"切换（参考 ios 的 source 参数）。

```dart
Future<List<ComicGridItem>> loadFavorites(int page, {String? folder}) async {
  final futures = ComicSource.sources
      .where((s) => s.favoriteData != null && s.isLogin)
      .map((s) async {
        final res = await s.favoriteData!.load(page, folder);
        return res.data.map((b) => ComicGridItem(
          id: b.id, title: b.title, coverUrl: b.cover,
          subtitle: b.subTitle, sourceKey: s.key,
        )).toList();
      });
  final results = await Future.wait(futures);
  return results.expand((e) => e).toList();
}
```

## 文件夹管理

| 操作 | 禁漫 | 哔咔 |
|------|------|------|
| 列文件夹 | `favorite_folder` | `loadFolders`（待补声明）|
| 新建 | `favorite_folder` POST | `addFolder` |
| 重命名 | `favorite_folder_edit` | （待核实）|
| 删除 | `favorite_folder_del` | `deleteFolder` |
| 移动 | `favorite_move` | （待核实）|

joycomic 收藏页"新建文件夹"图标按钮（`+`）→ 弹出输入框 → 调对应源 API。

## 本地收藏（阶段4）

阶段4 本地 sqlite3 DB 接入后，增加**本地收藏**层：

- 未登录源的漫画可本地收藏（不依赖源登录）。
- 本地收藏与云端收藏合并展示，本地项标注"离线"角标。
- 历史记录同样落本地 DB（`ComicReadRecord`）。

## 排序

| UI 选项 | 禁漫 order | 哔咔 sort |
|---------|-----------|-----------|
| 最近 | `mr` | `dd` |
| 收藏时间 | `mr`（禁漫无独立"收藏时间"，近似）| `dd` |
| 标题 | 客户端排序 | 客户端排序 |

禁漫无"收藏时间"维度，"收藏时间"选项对禁漫回落到 `mr`（最新更新）。

## ViewModel 契约

```dart
class FavoritesViewModel extends ChangeNotifier {
  String? filterSource;       // null=全部
  String? folderId;
  String sort = 'recent';
  List<ComicGridItem> items = [];
  List<FolderItem> folders = [];

  Future<void> load();
  Future<void> toggleFavorite(ComicGridItem item);
  Future<void> createFolder(String name);
}
```

## 待定问题

- 哔咔 `favoriteData` 完整契约需在 `built_in/picacg.dart` 补全（load/loadFolders/addOrDelFavorite/multiFolder）。
- 禁漫 `favorite` 系列端点（folder 增删改 + move）需在 `JmNetwork` 补方法。
- 收藏态同步：详情页 `isFavorite` 与收藏页列表需双向刷新（阶段4 Provider 接入后统一）。
