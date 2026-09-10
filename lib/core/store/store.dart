import 'dart:convert';
import 'dart:io';

import '../model/profile.dart';
import '../model/settings.dart';
import '../utils/paths.dart';

/// Persistent state: settings, servers and subscriptions.
class AppStore {
  AppStore({
    AppSettings? settings,
    List<Profile>? profiles,
    List<Subscription>? subscriptions,
  })  : settings = settings ?? AppSettings(),
        profiles = profiles ?? <Profile>[],
        subscriptions = subscriptions ?? <Subscription>[];

  AppSettings settings;
  List<Profile> profiles;
  List<Subscription> subscriptions;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'settings': settings.toJson(),
        'profiles': profiles.map((e) => e.toJson()).toList(growable: false),
        'subscriptions':
            subscriptions.map((e) => e.toJson()).toList(growable: false),
      };

  static AppStore fromJson(Map<String, dynamic> json) => AppStore(
        settings: json['settings'] is Map
            ? AppSettings.fromJson(Map<String, dynamic>.from(json['settings'] as Map))
            : AppSettings(),
        profiles: (json['profiles'] as List? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(Profile.fromJson)
            .toList(),
        subscriptions: (json['subscriptions'] as List? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(Subscription.fromJson)
            .toList(),
      );

  static AppStore load() {
    try {
      final file = AppPaths.settingsFile;
      if (!file.existsSync()) {
        return AppStore();
      }
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        return AppStore();
      }
      return fromJson(Map<String, dynamic>.from(decoded));
    } on Object {
      // A corrupted file must not brick the app: start fresh, keep a backup.
      try {
        final file = AppPaths.settingsFile;
        file.copySync('${file.path}.corrupt');
      } on Object {
        // ignore
      }
      return AppStore();
    }
  }

  Future<void> save() async {
    final file = AppPaths.settingsFile;
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(toJson()), flush: true);
    if (file.existsSync()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }

  // -- helpers --------------------------------------------------------------

  Profile? findProfile(String? id) {
    if (id == null) {
      return null;
    }
    for (final profile in profiles) {
      if (profile.id == id) {
        return profile;
      }
    }
    return null;
  }

  Profile? get selectedProfile {
    final selected = findProfile(settings.selectedProfileId);
    if (selected != null) {
      return selected;
    }
    if (profiles.isNotEmpty) {
      return profiles.first;
    }
    return null;
  }

  /// Replaces the servers of a subscription, keeping locally added ones.
  void mergeSubscription(Subscription subscription, List<Profile> incoming) {
    profiles.removeWhere((p) => p.subscriptionId == subscription.id);
    profiles.addAll(incoming);
    subscription
      ..serverCount = incoming.length
      ..lastUpdatedAt = DateTime.now()
      ..lastError = null;
  }
}
