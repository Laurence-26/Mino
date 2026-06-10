import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final localeProvider = StateProvider<Locale>((ref) => const Locale('en'));
// providers/settings_provider.dart
final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final currencyProvider = StateProvider<String>((ref) => 'USD');