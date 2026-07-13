/// JoyComic 字体层级 token。
///
/// 深色底的文字依靠字号/字重差与对比度建立层级，
/// 而非加彩色。语义命名，便于全局调字号档位。
///
/// 字体方案：
/// - 默认使用系统字体（iOS PingFang SC / Android Noto Sans CJK）
/// - 启用 LXGW WenKai：将下方 [kFontFamily] 改为 'LXGWWenKai'，
///   并在 pubspec.yaml 取消注释 fonts 段落后添加字体文件。
library app_typography;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 全局字体族。设为 'LXGWWenKai' 启用霞鹜文楷。
const String? kFontFamily = 'LXGWWenKai';

/// 等宽字体。
const String? kMonoFontFamily = 'LXGWWenKaiMono';

class AppTypography {
  AppTypography._();

  static TextStyle _withFont(TextStyle style) {
    if (kFontFamily == null) return style;
    return style.copyWith(fontFamily: kFontFamily);
  }

  /// Hero 标题（详情页主标题），22 / w700。
  static TextStyle hero(BuildContext _) => _withFont(const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: AppColors.textHigh,
      ));

  /// 区块大标题（"简介""章节""评论"），18 / w700。
  static TextStyle section(BuildContext _) => _withFont(const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: AppColors.textHigh,
      ));

  /// 区块标题旁的动作文字（"更多 >""换一换"），14 / w600。
  static TextStyle sectionAction(BuildContext _) => _withFont(const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textMedium,
      ));

  /// 正文（简介、评论体），15 / w400，行距宽松。
  static TextStyle body(BuildContext _) => _withFont(const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.6,
        color: AppColors.textMedium,
      ));

  /// 次标题/译名（标题下方两行小字），13 / w400。
  static TextStyle subtitle(BuildContext _) => _withFont(const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: AppColors.textLow,
      ));

  /// 元标签（作者名带跳转、tags、热度数），13 / w500。
  static TextStyle meta(BuildContext _) => _withFont(const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textMedium,
      ));

  /// 大号数字评分，26 / w800。
  static TextStyle ratingNumber(BuildContext _) => _withFont(const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w800,
        height: 1.0,
        color: AppColors.textHigh,
      ));

  /// 评分人数细字，11 / w400。
  static TextStyle ratingCount(BuildContext _) => _withFont(const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.textLow,
      ));

  /// 主按钮主标题（"开始阅读"），16 / w700，色由按钮渐变决定（用白）。
  static const TextStyle buttonMainTitle = TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      );

  /// 主按钮副提示（"最新 第12话"），12 / w400。
  static const TextStyle buttonMainHint = TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: Color(0xCCFFFFFF),
      );

  /// 次级按钮（收藏"已收藏"/"收藏"），14 / w600。
  static const TextStyle buttonSecondary = TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textHigh,
      );

  /// 卡片标题（漫画卡作品名），14 / w600。
  static TextStyle cardTitle(BuildContext _) => TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: AppColors.textHigh,
      );

  /// 卡片副信息（作者/更新时间），12 / w400。
  static TextStyle cardMeta(BuildContext _) => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textLow,
      );

  /// 章节卡名称，13 / w500 单行省略。
  static TextStyle chapterName(BuildContext _) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textMedium,
      );

  /// 角标（NEW、热度），10 / w700。
  static const TextStyle badge = TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 0.5,
      );
}
