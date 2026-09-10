/// Subscription list state (thin wrapper over [SubscriptionManager]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/subscription.dart';
import '../subscriptions/subscription_manager.dart';

class SubscriptionProvider extends ChangeNotifier {
  SubscriptionProvider({required SubscriptionManager manager})
      : _manager = manager {
    _subscription = _manager.changed.listen((_) => notifyListeners());
  }

  final SubscriptionManager _manager;
  late final StreamSubscription<void> _subscription;

  List<Subscription> get subscriptions => _manager.subscriptions;
  Subscription? findById(String id) => _manager.findById(id);

  Future<Subscription> add({
    required String name,
    required String url,
    bool autoRefresh = false,
    int refreshIntervalMinutes = 240,
  },) =>
      _manager.add(
        name: name,
        url: url,
        autoRefresh: autoRefresh,
        refreshIntervalMinutes: refreshIntervalMinutes,
      );

  Future<void> update(Subscription subscription) => _manager.update(subscription);

  Future<void> remove(String id) => _manager.remove(id);

  Future<bool> refresh(String id) => _manager.refresh(id);

  Future<void> refreshAll() => _manager.refreshAllEnabled();

  void cancelRefresh(String id) => _manager.cancelRefresh(id);

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
