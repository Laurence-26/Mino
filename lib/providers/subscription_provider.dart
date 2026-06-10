import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/revenue_cat_service.dart';

final isPremiumProvider = StreamProvider<bool>((ref) async* {
  yield await RevenueCatService().isPremium();
  yield* RevenueCatService().premiumStream;
});

final packagesProvider = FutureProvider<List<Package>>((ref) async {
  return RevenueCatService().getPackages();
});
