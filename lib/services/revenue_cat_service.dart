import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

/// Thin wrapper around the RevenueCat SDK.
///
/// Responsibilities:
/// * Configure the SDK once.
/// * Identify / log-out the user as Firebase auth changes.
/// * Provide reactive entitlement state via [premiumStream].
/// * Expose the RC-hosted paywall and Customer Center.
class RevenueCatService {
  // ── Configuration ───────────────────────────────────────────────
  // RC public SDK key (test key — works on both Android & iOS in development).
  // For production, replace with platform-specific keys from
  // RevenueCat → Project Settings → API Keys.
  static const String _apiKey = 'test_UfTTceWMvHywlLQuanuqanSMKvM';

  /// Identifier of the entitlement that unlocks premium features.
  /// Must match the entitlement configured in the RC dashboard exactly.
  static const String entitlementId = 'mino Premium';

  /// Canonical package identifiers used in the RC offering.
  static const String monthlyPackageId = 'monthly';
  static const String yearlyPackageId = 'yearly';
  static const String lifetimePackageId = 'lifetime';

  // ── Singleton ───────────────────────────────────────────────────
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;
  RevenueCatService._internal();

  bool _configured = false;
  String? _currentUserId;

  final StreamController<bool> _premiumController =
      StreamController<bool>.broadcast();

  /// Emits the current premium state whenever it changes (purchase, restore,
  /// expiration, log-in, log-out).
  Stream<bool> get premiumStream => _premiumController.stream;

  // ── Lifecycle ───────────────────────────────────────────────────

  /// Configures the SDK on first call; on subsequent calls, switches the
  /// identified user via [Purchases.logIn] if the userId changed.
  Future<void> initialize(String userId) async {
    try {
      if (!_configured) {
        await Purchases.setLogLevel(
          kDebugMode ? LogLevel.debug : LogLevel.warn,
        );
        final configuration = PurchasesConfiguration(_apiKey)
          ..appUserID = userId.isEmpty ? null : userId;
        await Purchases.configure(configuration);
        _configured = true;
        _currentUserId = userId.isEmpty ? null : userId;

        Purchases.addCustomerInfoUpdateListener(_handleCustomerInfo);

        // Seed the stream with the initial entitlement state.
        try {
          final info = await Purchases.getCustomerInfo();
          _handleCustomerInfo(info);
        } catch (_) {/* offline / first-launch is fine */}
      } else if (userId.isNotEmpty && userId != _currentUserId) {
        await Purchases.logIn(userId);
        _currentUserId = userId;
      }
      debugPrint('RevenueCat ready (userId: $userId)');
    } catch (e) {
      debugPrint('RevenueCat initialize error: $e');
    }
  }

  /// Reset the identified user back to an anonymous appUserID.
  Future<void> logOut() async {
    if (!_configured) return;
    try {
      await Purchases.logOut();
      _currentUserId = null;
      _premiumController.add(false);
    } catch (e) {
      debugPrint('RevenueCat logOut error: $e');
    }
  }

  void _handleCustomerInfo(CustomerInfo info) {
    final active = info.entitlements.active.containsKey(entitlementId);
    _premiumController.add(active);
  }

  // ── Entitlement & customer info ─────────────────────────────────

  /// Returns true if the user currently has the [entitlementId] active.
  Future<bool> isPremium() async {
    if (!_configured) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(entitlementId);
    } catch (e) {
      debugPrint('isPremium error: $e');
      return false;
    }
  }

  /// Fetches the latest [CustomerInfo] (forces the SDK to sync with the server).
  Future<CustomerInfo?> customerInfo() async {
    if (!_configured) return null;
    try {
      return await Purchases.getCustomerInfo();
    } catch (e) {
      debugPrint('customerInfo error: $e');
      return null;
    }
  }

  // ── Offerings & packages ────────────────────────────────────────

  /// All packages in the current offering.
  Future<List<Package>> getPackages() async {
    if (!_configured) return const [];
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current?.availablePackages ?? const [];
    } catch (e) {
      debugPrint('getPackages error: $e');
      return const [];
    }
  }

  /// Returns the current [Offering] (used to present the paywall).
  Future<Offering?> currentOffering() async {
    if (!_configured) return null;
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current;
    } catch (e) {
      debugPrint('currentOffering error: $e');
      return null;
    }
  }

  /// Convenience: find a package by [PackageType] first, falling back to a
  /// literal identifier match.
  Package? findPackage(
    List<Package> packages, {
    required PackageType preferredType,
    required String fallbackIdentifier,
  }) {
    for (final p in packages) {
      if (p.packageType == preferredType) return p;
    }
    for (final p in packages) {
      if (p.identifier.toLowerCase() == fallbackIdentifier.toLowerCase()) {
        return p;
      }
    }
    return null;
  }

  // ── Purchase actions ────────────────────────────────────────────

  /// Purchase the given [package]. Returns true if the entitlement is now
  /// active. Cancellation is treated as a non-error false return.
  Future<bool> purchasePackage(Package package) async {
    if (!_configured) return false;
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return result.customerInfo.entitlements.active
          .containsKey(entitlementId);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('Purchase cancelled by user');
        return false;
      }
      debugPrint('Purchase error: $code');
      return false;
    } catch (e) {
      debugPrint('Purchase error: $e');
      return false;
    }
  }

  /// Restore prior purchases (e.g. after re-install or login on new device).
  Future<bool> restorePurchases() async {
    if (!_configured) return false;
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active.containsKey(entitlementId);
    } catch (e) {
      debugPrint('Restore error: $e');
      return false;
    }
  }

  // ── Hosted UI ───────────────────────────────────────────────────

  /// Present the RC-hosted paywall. Returns the [PaywallResult] so callers
  /// can react to purchase / restore / cancel.
  Future<PaywallResult> presentPaywall({bool displayCloseButton = true}) async {
    if (!_configured) return PaywallResult.error;
    try {
      return await RevenueCatUI.presentPaywall(
        displayCloseButton: displayCloseButton,
      );
    } catch (e) {
      debugPrint('presentPaywall error: $e');
      return PaywallResult.error;
    }
  }

  /// Present the paywall only if the user does NOT currently have
  /// [entitlementId]. Returns [PaywallResult.notPresented] if already premium.
  Future<PaywallResult> presentPaywallIfNeeded({
    bool displayCloseButton = true,
  }) async {
    if (!_configured) return PaywallResult.error;
    try {
      return await RevenueCatUI.presentPaywallIfNeeded(
        entitlementId,
        displayCloseButton: displayCloseButton,
      );
    } catch (e) {
      debugPrint('presentPaywallIfNeeded error: $e');
      return PaywallResult.error;
    }
  }

  /// Present the RC-hosted Customer Center where users can manage their
  /// subscription, cancel, restore, contact support, etc.
  Future<void> presentCustomerCenter() async {
    if (!_configured) return;
    try {
      await RevenueCatUI.presentCustomerCenter();
    } catch (e) {
      debugPrint('presentCustomerCenter error: $e');
    }
  }

  /// Gate helper: returns true if the user is (or has just become) premium.
  /// If not premium, presents the hosted paywall and returns true on
  /// successful purchase or restore, false on cancel/error.
  Future<bool> requirePremium() async {
    if (await isPremium()) return true;
    final result = await presentPaywallIfNeeded();
    return result == PaywallResult.purchased ||
        result == PaywallResult.restored ||
        result == PaywallResult.notPresented;
  }
}
