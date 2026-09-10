/// Application service graph: built once in `main()`, torn down on exit.
///
/// Construction order matters (log first, dependents after). Everything is
/// injected — widgets and providers never construct services themselves.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/core_manager.dart';
import '../core/xray_adapter.dart';
import '../core/xray_config_builder.dart';
import '../core/xray_config_validator.dart';
import '../core/xray_stats.dart';
import '../diagnostics/diagnostics.dart';
import '../logging/log_service.dart';
import '../network/connectivity.dart';
import '../platform/app_paths.dart';
import '../platform/autostart.dart';
import '../platform/os_info.dart';
import '../profiles/best_profile.dart';
import '../profiles/profile_importer.dart';
import '../profiles/profile_repository.dart';
import '../proxy/system_proxy.dart';
import '../proxy/tun_manager.dart';
import '../settings/backup_service.dart';
import '../settings/settings_repository.dart';
import '../speedtest/speed_test.dart';
import '../storage/json_store.dart';
import '../storage/secure_vault.dart';
import '../subscriptions/subscription_fetcher.dart';
import '../subscriptions/subscription_manager.dart';
import '../update/update_service.dart';

String _newUuid() => const Uuid().v4();

class AppServices {
  AppServices._({
    required this.paths,
    required this.log,
    required this.os,
    required this.settings,
    required this.vault,
    required this.profiles,
    required this.importer,
    required this.subscriptions,
    required this.core,
    required this.systemProxy,
    required this.tun,
    required this.autostart,
    required this.connectivity,
    required this.diagnostics,
    required this.speedTest,
    required this.selector,
    required this.updates,
    required this.backup,
  },);

  final AppPaths paths;
  final LogService log;
  final OsInfo os;
  final SettingsRepository settings;
  final SecureVault vault;
  final ProfileRepository profiles;
  final ProfileImporter importer;
  final SubscriptionManager subscriptions;
  final CoreManager core;
  final SystemProxyService systemProxy;
  final TunManager tun;
  final AutostartService autostart;
  final ConnectivityService connectivity;
  final DiagnosticsService diagnostics;
  final SpeedTestService speedTest;
  final BestProfileSelector selector;
  final UpdateService updates;
  final BackupService backup;

  static Future<AppServices> create({AppPaths? pathsOverride}) async {
    final paths = pathsOverride ?? await AppPaths.resolve();
    await paths.ensureCreated();

    final log = LogService(logDir: paths.logsDir);
    await log.init();
    log.info('app', 'IranLink starting (portable=${paths.portable})');

    final os = OsInfo.current();
    log.info('app', 'OS: ${os.displayName}');

    final settings = SettingsRepository(
      store: JsonStore(file: paths.settingsFile, schemaVersion: 1),
      log: log,
    );
    await settings.load();
    log.minLevel = _parseLevel(settings.current.logLevel);

    final vault = await SecureVaultFactory.create(
      vaultFile: paths.vaultFile,
      keyFile: File(p.join(paths.configDir.path, 'vault.key')),
      log: log,
    );

    final profiles = ProfileRepository(
      store: JsonStore(file: paths.profilesFile, schemaVersion: 1),
      newId: _newUuid,
      log: log,
    );
    await profiles.load();

    final importer = ProfileImporter(repository: profiles, log: log);

    final subscriptions = SubscriptionManager(
      store: JsonStore(file: paths.subscriptionsFile, schemaVersion: 1),
      cacheDir: paths.subscriptionsDir,
      profiles: profiles,
      fetcher: SubscriptionFetcher(log: log),
      newId: _newUuid,
      log: log,
    );
    await subscriptions.load();

    const builder = XrayConfigBuilder();
    const validator = XrayConfigValidator();
    final core = CoreManager(
      adapter: XrayCoreAdapter(),
      builder: builder,
      validator: validator,
      statsClient: XrayStatsClient(),
      paths: paths,
      os: os,
      log: log,
    );
    await core.init();

    final systemProxy = SystemProxyService(log: log);
    final tun = TunManager(os: os, log: log);
    final autostart = AutostartService(log: log);
    final connectivity = ConnectivityService(log: log);
    final diagnostics = DiagnosticsService(
      core: core,
      systemProxy: systemProxy,
      tun: tun,
      vault: vault,
      paths: paths,
      os: os,
      connectivity: connectivity,
      log: log,
    );
    final speedTest = SpeedTestService(log: log);

    final probe = ProfileProbe(
      adapter: XrayCoreAdapter(),
      builder: builder,
      executable: _probeExecutable(os),
      log: log,
    );
    final selector = BestProfileSelector(
      probe: probe,
      connectivity: connectivity,
      repository: profiles,
      log: log,
    );

    return AppServices._(
      paths: paths,
      log: log,
      os: os,
      settings: settings,
      vault: vault,
      profiles: profiles,
      importer: importer,
      subscriptions: subscriptions,
      core: core,
      systemProxy: systemProxy,
      tun: tun,
      autostart: autostart,
      connectivity: connectivity,
      diagnostics: diagnostics,
      speedTest: speedTest,
      selector: selector,
      updates: UpdateService(log: log),
      backup: BackupService(log: log),
    );
  }

  static String _probeExecutable(OsInfo os) {
    final override = Platform.environment['IRANLINK_CORE_DIR'];
    final bundled = override != null && override.isNotEmpty
        ? Directory(override)
        : AppPaths.bundledCoreDir();
    final primary = File(p.join(bundled.path, 'xray.exe'));
    final legacy = File(p.join(bundled.path, 'win7', 'xray.exe'));
    final first = os.useLegacyCore ? legacy : primary;
    final second = os.useLegacyCore ? primary : legacy;
    if (first.existsSync()) return first.path;
    if (second.existsSync()) return second.path;
    return '';
  }

  static LogLevel _parseLevel(String name) {
    return LogLevel.values.firstWhere(
      (level) => level.name.toLowerCase() == name.toLowerCase(),
      orElse: () => LogLevel.info,
    );
  }

  Future<void> dispose() async {
    await core.dispose();
    await subscriptions.dispose();
    await profiles.dispose();
    await settings.dispose();
    await log.dispose();
  }
}
