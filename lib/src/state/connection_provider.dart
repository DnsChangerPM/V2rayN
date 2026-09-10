/// Connection state: core lifecycle + system proxy, UI-ready.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/core_manager.dart';
import '../logging/log_service.dart';
import '../models/connection.dart';
import '../models/profile.dart';
import '../models/settings.dart';
import '../profiles/profile_repository.dart';
import '../proxy/system_proxy.dart';
import '../settings/settings_repository.dart';
import '../tray/tray_service.dart';

class ConnectionProvider extends ChangeNotifier
    implements TrayConnectionSource {
  ConnectionProvider({
    required CoreManager core,
    required SystemProxyService systemProxy,
    required SettingsRepository settings,
    required ProfileRepository profiles,
    required LogService log,
  },)  : _core = core,
        _systemProxy = systemProxy,
        _settings = settings,
        _profiles = profiles,
        _log = log {
    _coreSubscription = _core.statusStream.listen(_onCoreStatus);
    _trafficSubscription = _core.trafficStream.listen((traffic) {
      _traffic = traffic;
      notifyListeners();
    });
  }

  final CoreManager _core;
  final SystemProxyService _systemProxy;
  final SettingsRepository _settings;
  final ProfileRepository _profiles;
  final LogService _log;

  late final StreamSubscription<CoreStatus> _coreSubscription;
  late final StreamSubscription<TrafficStats> _trafficSubscription;

  ConnectionState _state = ConnectionState.disconnected;
  TrafficStats _traffic = const TrafficStats();
  String _failureKey = '';
  AppFailure? _failure;

  ConnectionState get state => _state;
  TrafficStats get traffic => _traffic;
  String get failureKey => _failureKey;
  AppFailure? get failure => _failure;
  CoreStatus get coreStatus => _core.status;
  String get coreVersion => _core.coreVersion;

  ProxyProfile? get activeProfile =>
      _profiles.findById(_settings.current.activeProfileId);

  bool get isConnected => _state == ConnectionState.connected;
  bool get isBusy =>
      _state == ConnectionState.connecting ||
      _state == ConnectionState.disconnecting;

  Future<void> toggle() =>
      isConnected ? disconnect() : connect();

  Future<void> connect() async {
    if (_state == ConnectionState.connecting ||
        _state == ConnectionState.connected) {
      return;
    }
    final profile = activeProfile;
    if (profile == null) {
      _setError(const AppFailure(messageKey: 'errorNoProfile'));
      return;
    }
    _state = ConnectionState.connecting;
    _failureKey = '';
    _failure = null;
    notifyListeners();

    final settings = _settings.current;
    await _core.connect(profile: profile, settings: settings);
    if (_core.status == CoreStatus.running) {
      if (settings.proxyMode == ProxyMode.system) {
        try {
          await _systemProxy.enable(
              server:
                  '127.0.0.1:${settings.inbounds.httpPort}',);
        } on Object catch (e) {
          _log.error('connection', 'System proxy failed', error: e);
          await _core.disconnect();
          _setError(
              const AppFailure(messageKey: 'proxyErrorApplyFailed'),);
          return;
        }
      }
      await _profiles.recordUsage(profile.id);
      _state = ConnectionState.connected;
    } else {
      _setError(
          _core.lastFailure ??
              const AppFailure(messageKey: 'coreErrorStartFailed'),);
      return;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (_state == ConnectionState.disconnected ||
        _state == ConnectionState.disconnecting) {
      return;
    }
    _state = ConnectionState.disconnecting;
    notifyListeners();
    try {
      await _systemProxy.disable();
    } on Object catch (e) {
      _log.warning('connection', 'Proxy restore failed', error: e);
    }
    await _core.disconnect();
    _traffic = const TrafficStats();
    _state = ConnectionState.disconnected;
    notifyListeners();
  }

  void _onCoreStatus(CoreStatus status) {
    switch (status) {
      case CoreStatus.crashed:
      case CoreStatus.error:
        if (_state == ConnectionState.connected ||
            _state == ConnectionState.connecting) {
          _setError(
              _core.lastFailure ??
                  const AppFailure(messageKey: 'coreErrorStartFailed'),);
        }
      case CoreStatus.stopped:
        if (_state != ConnectionState.disconnecting &&
            _state != ConnectionState.disconnected) {
          _state = ConnectionState.disconnected;
          _traffic = const TrafficStats();
          notifyListeners();
        }
      case CoreStatus.starting:
      case CoreStatus.running:
      case CoreStatus.stopping:
        notifyListeners(); // core badge refresh
    }
  }

  void _setError(AppFailure failure) {
    _failure = failure;
    _failureKey = failure.messageKey;
    _state = ConnectionState.error;
    notifyListeners();
  }

  /// Re-read system state (used by pull-to-refresh in Diagnostics).
  void refresh() => notifyListeners();

  @override
  void dispose() {
    _coreSubscription.cancel();
    _trafficSubscription.cancel();
    super.dispose();
  }
}
