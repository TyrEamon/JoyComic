import 'package:flutter/material.dart';

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.pageBackground,
    required this.surfaceMuted,
    required this.surfaceRaised,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.info,
    required this.onInfo,
    required this.rating,
    required this.onImage,
    required this.imageScrimStrong,
    required this.imageScrimSoft,
    required this.imageScrimClear,
    required this.readerScrimStrong,
    required this.readerControlForeground,
    required this.readerCanvas,
    required this.shimmerBase,
    required this.shimmerHighlight,
  });

  final Color pageBackground;
  final Color surfaceMuted;
  final Color surfaceRaised;
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color info;
  final Color onInfo;
  final Color rating;
  final Color onImage;
  final Color imageScrimStrong;
  final Color imageScrimSoft;
  final Color imageScrimClear;
  final Color readerScrimStrong;
  final Color readerControlForeground;
  final Color readerCanvas;
  final Color shimmerBase;
  final Color shimmerHighlight;

  static const light = AppSemanticColors(
    pageBackground: Color(0xFFF7F5F2),
    surfaceMuted: Color(0xFFF0EDE8),
    surfaceRaised: Color(0xFFE9E5DF),
    success: Color(0xFF2F6B4F),
    onSuccess: Color(0xFFFFFFFF),
    warning: Color(0xFF8A5A00),
    onWarning: Color(0xFFFFFFFF),
    info: Color(0xFF3F5F88),
    onInfo: Color(0xFFFFFFFF),
    rating: Color(0xFF8A5A00),
    onImage: Color(0xFFFFFFFF),
    imageScrimStrong: Color(0xD9000000),
    imageScrimSoft: Color(0x7A000000),
    imageScrimClear: Color(0x00000000),
    readerScrimStrong: Color(0xB3000000),
    readerControlForeground: Color(0xFFFFFFFF),
    readerCanvas: Color(0xFF000000),
    shimmerBase: Color(0xFFE8E3DD),
    shimmerHighlight: Color(0xFFF7F4F0),
  );

  static const dark = AppSemanticColors(
    pageBackground: Color(0xFF111315),
    surfaceMuted: Color(0xFF202428),
    surfaceRaised: Color(0xFF272C31),
    success: Color(0xFF8BD3AB),
    onSuccess: Color(0xFF0F3322),
    warning: Color(0xFFF1C56D),
    onWarning: Color(0xFF3A2900),
    info: Color(0xFFAAC7F0),
    onInfo: Color(0xFF17314D),
    rating: Color(0xFFF1C56D),
    onImage: Color(0xFFFFFFFF),
    imageScrimStrong: Color(0xD9000000),
    imageScrimSoft: Color(0x7A000000),
    imageScrimClear: Color(0x00000000),
    readerScrimStrong: Color(0xB3000000),
    readerControlForeground: Color(0xFFFFFFFF),
    readerCanvas: Color(0xFF000000),
    shimmerBase: Color(0xFF24282C),
    shimmerHighlight: Color(0xFF30363B),
  );

  static AppSemanticColors fallback(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  @override
  AppSemanticColors copyWith({
    Color? pageBackground,
    Color? surfaceMuted,
    Color? surfaceRaised,
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? info,
    Color? onInfo,
    Color? rating,
    Color? onImage,
    Color? imageScrimStrong,
    Color? imageScrimSoft,
    Color? imageScrimClear,
    Color? readerScrimStrong,
    Color? readerControlForeground,
    Color? readerCanvas,
    Color? shimmerBase,
    Color? shimmerHighlight,
  }) => AppSemanticColors(
    pageBackground: pageBackground ?? this.pageBackground,
    surfaceMuted: surfaceMuted ?? this.surfaceMuted,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    info: info ?? this.info,
    onInfo: onInfo ?? this.onInfo,
    rating: rating ?? this.rating,
    onImage: onImage ?? this.onImage,
    imageScrimStrong: imageScrimStrong ?? this.imageScrimStrong,
    imageScrimSoft: imageScrimSoft ?? this.imageScrimSoft,
    imageScrimClear: imageScrimClear ?? this.imageScrimClear,
    readerScrimStrong: readerScrimStrong ?? this.readerScrimStrong,
    readerControlForeground:
        readerControlForeground ?? this.readerControlForeground,
    readerCanvas: readerCanvas ?? this.readerCanvas,
    shimmerBase: shimmerBase ?? this.shimmerBase,
    shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
  );

  @override
  AppSemanticColors lerp(covariant AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      rating: Color.lerp(rating, other.rating, t)!,
      onImage: Color.lerp(onImage, other.onImage, t)!,
      imageScrimStrong: Color.lerp(
        imageScrimStrong,
        other.imageScrimStrong,
        t,
      )!,
      imageScrimSoft: Color.lerp(imageScrimSoft, other.imageScrimSoft, t)!,
      imageScrimClear: Color.lerp(imageScrimClear, other.imageScrimClear, t)!,
      readerScrimStrong: Color.lerp(
        readerScrimStrong,
        other.readerScrimStrong,
        t,
      )!,
      readerControlForeground: Color.lerp(
        readerControlForeground,
        other.readerControlForeground,
        t,
      )!,
      readerCanvas: Color.lerp(readerCanvas, other.readerCanvas, t)!,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight: Color.lerp(
        shimmerHighlight,
        other.shimmerHighlight,
        t,
      )!,
    );
  }
}
