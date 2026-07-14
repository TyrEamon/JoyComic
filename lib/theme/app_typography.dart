/// JoyComic 字体层级 token。
library app_typography;

import 'package:flutter/material.dart';

import 'app_theme_context.dart';

const String? kFontFamily = 'LXGWWenKai';
const String? kMonoFontFamily = 'LXGWWenKaiMono';

class AppTypography {
  AppTypography._();

  static TextStyle _style(
    BuildContext context, {
    required double size,
    required FontWeight weight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: kFontFamily,
    fontSize: size,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? context.primaryTextColor,
  );

  static TextStyle hero(BuildContext context) =>
      _style(context, size: 22, weight: FontWeight.w700, height: 1.25);

  static TextStyle section(BuildContext context) =>
      _style(context, size: 18, weight: FontWeight.w700, height: 1.3);

  static TextStyle sectionAction(BuildContext context) => _style(
    context,
    size: 14,
    weight: FontWeight.w600,
    color: context.secondaryTextColor,
  );

  static TextStyle body(BuildContext context) => _style(
    context,
    size: 15,
    weight: FontWeight.w400,
    height: 1.6,
    color: context.secondaryTextColor,
  );

  static TextStyle subtitle(BuildContext context) => _style(
    context,
    size: 13,
    weight: FontWeight.w400,
    height: 1.4,
    color: context.tertiaryTextColor,
  );

  static TextStyle meta(BuildContext context) => _style(
    context,
    size: 13,
    weight: FontWeight.w500,
    color: context.secondaryTextColor,
  );

  static TextStyle ratingNumber(BuildContext context) =>
      _style(context, size: 26, weight: FontWeight.w800, height: 1);

  static TextStyle ratingCount(BuildContext context) => _style(
    context,
    size: 11,
    weight: FontWeight.w400,
    color: context.tertiaryTextColor,
  );

  static const TextStyle buttonMainTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  static const TextStyle buttonMainHint = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: Color(0xCCFFFFFF),
  );

  static TextStyle buttonSecondary(BuildContext context) =>
      _style(context, size: 14, weight: FontWeight.w600);

  static TextStyle cardTitle(BuildContext context) =>
      _style(context, size: 14, weight: FontWeight.w600, height: 1.35);

  static TextStyle cardMeta(BuildContext context) => _style(
    context,
    size: 12,
    weight: FontWeight.w400,
    color: context.tertiaryTextColor,
  );

  static TextStyle chapterName(BuildContext context) => _style(
    context,
    size: 13,
    weight: FontWeight.w500,
    color: context.secondaryTextColor,
  );

  static const TextStyle badge = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 0.5,
  );
}
