import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// FormFlow Premium (doc item 11). One product in Google Play Console /
/// App Store Connect; the id can be changed at build time with
/// `--dart-define=PREMIUM_PRODUCT_ID=...`. See MONETIZATION.md.
class PremiumProduct {
  static const id = String.fromEnvironment('PREMIUM_PRODUCT_ID', defaultValue: 'formflow_premium');
}

enum PurchaseOutcome { purchased, pending, cancelled, unavailable, error }

abstract class PurchaseService {
  /// Starts listening for purchase updates; [onPremium] is called whenever
  /// the store confirms (or restores) Premium.
  Future<void> init(void Function(bool premium) onPremium);

  /// Price text from the store, or null when the store is unavailable.
  Future<String?> price();

  Future<PurchaseOutcome> buy();

  Future<void> restore();

  void dispose();
}

/// Used in tests and when no store is reachable.
class NoPurchaseService implements PurchaseService {
  @override
  Future<void> init(void Function(bool premium) onPremium) async {}

  @override
  Future<String?> price() async => null;

  @override
  Future<PurchaseOutcome> buy() async => PurchaseOutcome.unavailable;

  @override
  Future<void> restore() async {}

  @override
  void dispose() {}
}

class StorePurchaseService implements PurchaseService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;
  void Function(bool premium)? _onPremium;
  Completer<PurchaseOutcome>? _pending;

  @override
  Future<void> init(void Function(bool premium) onPremium) async {
    _onPremium = onPremium;
    try {
      _sub = _iap.purchaseStream.listen(_onUpdates, onError: (_) {});
    } catch (_) {}
  }

  Future<ProductDetails?> _load() async {
    if (_product != null) return _product;
    try {
      if (!await _iap.isAvailable()) return null;
      final r = await _iap.queryProductDetails({PremiumProduct.id});
      if (r.productDetails.isNotEmpty) _product = r.productDetails.first;
    } catch (_) {}
    return _product;
  }

  @override
  Future<String?> price() async => (await _load())?.price;

  @override
  Future<PurchaseOutcome> buy() async {
    final p = await _load();
    if (p == null) return PurchaseOutcome.unavailable;
    _pending = Completer<PurchaseOutcome>();
    try {
      final started = await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
      if (!started) return PurchaseOutcome.error;
    } catch (_) {
      return PurchaseOutcome.error;
    }
    return _pending!.future.timeout(const Duration(minutes: 5), onTimeout: () => PurchaseOutcome.pending);
  }

  @override
  Future<void> restore() async {
    try {
      await _iap.restorePurchases();
    } catch (_) {}
  }

  void _finish(PurchaseOutcome o) {
    final c = _pending;
    if (c != null && !c.isCompleted) c.complete(o);
  }

  Future<void> _onUpdates(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.productID != PremiumProduct.id) continue;
      final st = p.status;
      if (st == PurchaseStatus.purchased || st == PurchaseStatus.restored) {
        _onPremium?.call(true);
        _finish(PurchaseOutcome.purchased);
      } else if (st == PurchaseStatus.pending) {
        _finish(PurchaseOutcome.pending);
      } else if (st == PurchaseStatus.canceled) {
        _finish(PurchaseOutcome.cancelled);
      } else {
        _finish(PurchaseOutcome.error);
      }
      if (p.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(p);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() => _sub?.cancel();
}

/// Overridden in main() with [StorePurchaseService].
final purchaseProvider = Provider<PurchaseService>((ref) => NoPurchaseService());
