/// 阶段3 详情页样板的演示数据。
///
/// 用 picsum.photos 占位图 + 中文文案构造 [ComicInfoData]，让详情页
/// 在无网络登录的情况下也能完整展示沉浸头 / 取色 / 章节网格 /
/// 推荐 / 悬浮底栏的全部设计。真实场景由源 `loadComicInfo` 提供。
library detail_demo_data;

import '../../comic_source/comic_source.dart';

ComicInfoData buildDemoComicInfo() {
  const cover = 'https://picsum.photos/seed/joycomic-cover/600/800';
  return ComicInfoData(
    title: '星屑协奏曲',
    subTitle: 'Stardust Concerto · 星屑の協奏曲',
    cover: cover,
    description: '少女在末世的废墟中拾起一把旧吉他，琴弦震动间，沉睡的星屑被唤醒。'
        '这是一段关于失落文明、记忆与救赎的旅程——当最后一个音符落下，'
        '世界是否会重新亮起？\n\n作者以细腻笔触描绘了末世背景下少女的成长，'
        '每一话都像一首短诗。画风清澈透明，分镜节奏舒缓而富有张力，'
        '是近年来难得的治愈系末日题材作品。本作已连载至第 48 话，'
        '在读者中口碑极佳，评分长居榜首。',
    tags: {
      '作者': ['星野澪'],
      '热度': ['9.6 万'],
      '收藏': ['12.3 万'],
      '评分': ['9.4'],
      '评价人数': ['2,861'],
      '标签': ['治愈', '末世', '少女', '冒险', '奇幻'],
    },
    chapters: {
      'ep01': '第1话 星屑',
      'ep02': '第2话 旧吉他',
      'ep03': '第3话 沉睡的旋律',
      'ep04': '第4话 觉醒',
      'ep05': '第5话 远方的光',
      'ep06': '第6话 同伴',
      'ep07': '第7话 废墟之城',
      'ep08': '第8话 协奏',
      'ep09': '第9话 雨夜',
      'ep10': '第10话 抉择',
      'ep11': '第11话 归途',
      'ep12': '第12话 星河',
    },
    thumbnails: [
      'https://picsum.photos/seed/jc-ep01/320/180',
      'https://picsum.photos/seed/jc-ep02/320/180',
      'https://picsum.photos/seed/jc-ep03/320/180',
      'https://picsum.photos/seed/jc-ep04/320/180',
      'https://picsum.photos/seed/jc-ep05/320/180',
      'https://picsum.photos/seed/jc-ep06/320/180',
      'https://picsum.photos/seed/jc-ep07/320/180',
      'https://picsum.photos/seed/jc-ep08/320/180',
      'https://picsum.photos/seed/jc-ep09/320/180',
      'https://picsum.photos/seed/jc-ep10/320/180',
      'https://picsum.photos/seed/jc-ep11/320/180',
      'https://picsum.photos/seed/jc-ep12/320/180',
    ],
    suggestions: [
      _DemoBaseComic(
        id: 'rec-1',
        title: '黄昏电车',
        subTitle: '星野澪',
        cover: 'https://picsum.photos/seed/jc-rec1/600/800',
      ),
      _DemoBaseComic(
        id: 'rec-2',
        title: '雨季手帖',
        subTitle: '宫下槙',
        cover: 'https://picsum.photos/seed/jc-rec2/600/800',
      ),
      _DemoBaseComic(
        id: 'rec-3',
        title: '深海图书馆',
        subTitle: '青木潤',
        cover: 'https://picsum.photos/seed/jc-rec3/600/800',
      ),
      _DemoBaseComic(
        id: 'rec-4',
        title: '霓虹纪行',
        subTitle: '佐藤明',
        cover: 'https://picsum.photos/seed/jc-rec4/600/800',
      ),
      _DemoBaseComic(
        id: 'rec-5',
        title: '云端邮差',
        subTitle: '中村柚',
        cover: 'https://picsum.photos/seed/jc-rec5/600/800',
      ),
    ],
    sourceKey: 'jm',
    comicId: 'demo-comic-id',
    isFavorite: false,
  );
}

class _DemoBaseComic implements BaseComic {
  const _DemoBaseComic({
    required this.id,
    required this.title,
    required this.subTitle,
    required this.cover,
  });

  @override
  final String id;
  @override
  final String title;
  @override
  final String subTitle;
  @override
  final String cover;

  @override
  List<String> get tags => const [];

  @override
  String get description => '';

  @override
  bool get enableTagsTranslation => true;
}
