/// 搜索历史数据库操作。
library search_history_helper;

import '../../foundation/log.dart';
import 'joy_database.dart';

class SearchHistoryHelper {
  static const _maxHistory = 20;

  /// 获取搜索历史（最近在前）。
  List<String> getHistory() {
    final result = JoyDatabase.instance.core.select(
      'SELECT keyword FROM search_history ORDER BY created_at DESC LIMIT $_maxHistory',
    );
    return result.map((r) => r['keyword'] as String).toList();
  }

  /// 添加或更新搜索词（去重置顶）。
  void addKeyword(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // 删除已存在的相同词
    JoyDatabase.instance.core.execute(
      'DELETE FROM search_history WHERE keyword = ?',
      [trimmed],
    );

    // 插入新记录
    JoyDatabase.instance.core.execute(
      'INSERT INTO search_history (keyword, created_at) VALUES (?, ?)',
      [trimmed, now],
    );

    // 超出上限删最旧的
    _trimExcess();

    Log.d('Search history added', trimmed);
  }

  /// 清空历史。
  void clear() {
    JoyDatabase.instance.core.execute('DELETE FROM search_history');
    Log.d('Search history cleared');
  }

  /// 删除单条。
  void remove(String keyword) {
    JoyDatabase.instance.core.execute(
      'DELETE FROM search_history WHERE keyword = ?',
      [keyword],
    );
  }

  void _trimExcess() {
    JoyDatabase.instance.core.execute(
      'DELETE FROM search_history WHERE id NOT IN '
      '(SELECT id FROM search_history ORDER BY created_at DESC LIMIT $_maxHistory)',
    );
  }
}
