import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExportNotifier extends StateNotifier<int> {
  ExportNotifier() : super(0) {
    _load();
  }

  static const _key = 'pdf_exports_remaining';
  static const _welcomeGrant = 2;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_key)) {
      await prefs.setInt(_key, _welcomeGrant);
      state = _welcomeGrant;
    } else {
      state = prefs.getInt(_key) ?? 0;
    }
  }

  Future<void> addExports(int count) async {
    final prefs = await SharedPreferences.getInstance();
    state = state + count;
    await prefs.setInt(_key, state);
  }

  Future<bool> useExport() async {
    if (state <= 0) return false;
    final prefs = await SharedPreferences.getInstance();
    state = state - 1;
    await prefs.setInt(_key, state);
    return true;
  }

  bool get hasExports => state > 0;
}

final exportProvider =
    StateNotifierProvider<ExportNotifier, int>(
        (ref) => ExportNotifier());