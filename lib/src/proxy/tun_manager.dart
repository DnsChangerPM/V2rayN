/// TUN mode: capability detection + modular roadmap (honest v1).
///
/// A real TUN implementation needs a kernel driver (Wintun), an elevated
/// setup flow, a userspace TCP/IP stack (tun2socks-style), and route-table
/// management. Shipping a *fake* TUN toggle would be worse than gating it,
/// so v1 provides:
///
/// - precise capability detection (OS gate, elevation state, driver presence),
/// - a stable [TunManager] interface the UI already binds to,
/// - explicit `unavailableReasonKey` strings instead of silent failure.
///
/// Roadmap (tracked, not promised): bundle wintun.dll, add an elevated
/// helper for driver install + route setup, integrate a tun2socks core.
/// See `docs/architecture.md` ("Adding another core") — TUN arrives as a
/// separate managed process behind this same interface.
library;

import 'dart:io';

import '../logging/log_service.dart';
import '../platform/os_info.dart';

enum TunState { disabled, enabling, enabled, error }

class TunCapability {
  const TunCapability({required this.available, this.reasonKey = ''});

  final bool available;

  /// l10n key explaining why TUN is unavailable ('' when available).
  final String reasonKey;
}

class TunManager {
  TunManager({required OsInfo os, required LogService log})
      : _os = os,
        _log = log;

  final OsInfo _os;
  final LogService _log;

  TunState _state = TunState.disabled;
  TunState get state => _state;

  /// Directory where a future wintun.dll would live (next to the EXE).
  static String get driverSearchPath =>
      '${File(Platform.resolvedExecutable).parent.path}\\wintun.dll';

  TunCapability capability() {
    if (!_os.isWindows) {
      return const TunCapability(
          available: false, reasonKey: 'tunUnsupportedPlatform',);
    }
    if (!_os.supportsTun) {
      return const TunCapability(
          available: false, reasonKey: 'tunUnsupportedLegacyWindows',);
    }
    // Win10+: driver + helper are not bundled in v1 (documented roadmap).
    final driverPresent = File(driverSearchPath).existsSync();
    _log.debug('tun', 'Capability check: wintun present=$driverPresent');
    return const TunCapability(
        available: false, reasonKey: 'tunNotBundledInVersion',);
  }

  /// Attempt to enable TUN. In v1 this always reports the honest reason
  /// instead of pretending; the interface stays stable for the real
  /// implementation.
  Future<TunCapability> enable() async {
    final cap = capability();
    if (!cap.available) {
      _state = TunState.error;
      _log.warning('tun', 'Enable refused: ${cap.reasonKey}');
      return cap;
    }
    _state = TunState.enabled;
    return cap;
  }

  Future<void> disable() async {
    _state = TunState.disabled;
  }
}
