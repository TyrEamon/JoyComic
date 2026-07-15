/// Neutral elevation tokens for covers, cards, and floating actions.
library;

import 'package:flutter/material.dart';

class AppShadows {
  AppShadows._();

  static const List<BoxShadow> coverElevation = [
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 24,
      spreadRadius: -6,
      offset: Offset(0, 12),
    ),
    BoxShadow(
      color: Color(0x26000000),
      blurRadius: 40,
      spreadRadius: -12,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 12,
      spreadRadius: -4,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> actionBar = [
    BoxShadow(
      color: Color(0x55000000),
      blurRadius: 20,
      spreadRadius: -2,
      offset: Offset(0, -6),
    ),
  ];

  /// Temporary compatibility for [PillBadge] during its Task 3 migration.
  static List<BoxShadow> pillGlow(Color _) => const [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 10,
      spreadRadius: -3,
      offset: Offset(0, 2),
    ),
  ];

  static List<BoxShadow> brandPillGlow() => pillGlow(Colors.black);
}
