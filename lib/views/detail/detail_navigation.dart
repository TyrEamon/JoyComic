import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

String detailSearchRoute({required String sourceKey, required String keyword}) {
  return Uri(
    path: '/search/${Uri.encodeComponent(sourceKey)}',
    queryParameters: <String, String>{'q': keyword.trim()},
  ).toString();
}

String detailCategoryRoute({
  required String sourceKey,
  required String category,
}) =>
    '/category/${Uri.encodeComponent(sourceKey)}/${Uri.encodeComponent(category.trim())}';

void openDetailKeywordSearch(
  BuildContext context, {
  required String sourceKey,
  required String keyword,
}) {
  context.push(detailSearchRoute(sourceKey: sourceKey, keyword: keyword));
}

void openDetailCategory(
  BuildContext context, {
  required String sourceKey,
  required String category,
}) {
  context.push(detailCategoryRoute(sourceKey: sourceKey, category: category));
}
