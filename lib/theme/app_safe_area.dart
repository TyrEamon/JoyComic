import 'package:flutter/widgets.dart';

import 'app_spacing.dart';

/// Bottom system inset plus the page's design spacing.
double bottomContentInset(
  BuildContext context, {
  double spacing = AppSpacing.xl,
}) => MediaQuery.viewPaddingOf(context).bottom + spacing;
