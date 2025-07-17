import 'package:flutter/foundation.dart';

final List<String> _recentErrors = [];

void logError(String errorMessage) {
  debugPrint(errorMessage);
  _recentErrors.add(errorMessage);
  if (_recentErrors.length > 50) {
    _recentErrors.removeAt(0);
  }
}

List<String> get recentErrors => List.unmodifiable(_recentErrors);
