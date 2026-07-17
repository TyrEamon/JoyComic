import 'package:flutter/foundation.dart';

/// Broadcasts successful source account login/logout changes to mounted pages.
class SourceSessionNotifier extends ChangeNotifier {
  SourceSessionNotifier._();

  static final SourceSessionNotifier instance = SourceSessionNotifier._();

  String? _lastChangedSourceKey;
  String? get lastChangedSourceKey => _lastChangedSourceKey;

  int _revision = 0;
  int get revision => _revision;

  void notifyChanged(String sourceKey) {
    _lastChangedSourceKey = sourceKey;
    _revision++;
    notifyListeners();
  }
}
