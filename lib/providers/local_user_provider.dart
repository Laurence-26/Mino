import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalUserNotifier extends StateNotifier<Map<String, dynamic>> {
  LocalUserNotifier() : super({}) {
    _load();
  }

  static const _nameKey = 'user_name';
  static const _balanceKey = 'starting_balance';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = {
      'name': prefs.getString(_nameKey) ?? 'User',
      'startingBalance': prefs.getDouble(_balanceKey) ?? 0.0,
    };
  }

  Future<void> setName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
    state = {...state, 'name': name};
  }

  Future<void> setStartingBalance(double balance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_balanceKey, balance);
    state = {...state, 'startingBalance': balance};
  }
}

final localUserProvider = StateNotifierProvider<LocalUserNotifier, Map<String, dynamic>>((ref) => LocalUserNotifier());