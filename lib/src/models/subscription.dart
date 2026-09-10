/// Subscription model (pure Dart).
library;

enum SubscriptionStatus { idle, refreshing, ok, error }

/// A remote profile source. [url] is SECRET and must never be logged raw.
class Subscription {
  const Subscription({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.autoRefresh = false,
    this.refreshIntervalMinutes = 240,
    this.lastUpdatedAt,
    this.lastStatus = SubscriptionStatus.idle,
    this.lastError = '',
    this.profileCount = 0,
    this.userAgent = '',
    this.allowInsecure = false,
    this.createdAt,
  },);

  final String id;
  final String name;
  final String url;
  final bool enabled;
  final bool autoRefresh;
  final int refreshIntervalMinutes;
  final DateTime? lastUpdatedAt;
  final SubscriptionStatus lastStatus;
  final String lastError;
  final int profileCount;
  final String userAgent;
  final bool allowInsecure;
  final DateTime? createdAt;

  Subscription copyWith({
    String? id,
    String? name,
    String? url,
    bool? enabled,
    bool? autoRefresh,
    int? refreshIntervalMinutes,
    DateTime? lastUpdatedAt,
    SubscriptionStatus? lastStatus,
    String? lastError,
    int? profileCount,
    String? userAgent,
    bool? allowInsecure,
    DateTime? createdAt,
  },) {
    return Subscription(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      enabled: enabled ?? this.enabled,
      autoRefresh: autoRefresh ?? this.autoRefresh,
      refreshIntervalMinutes: refreshIntervalMinutes ?? this.refreshIntervalMinutes,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastStatus: lastStatus ?? this.lastStatus,
      lastError: lastError ?? this.lastError,
      profileCount: profileCount ?? this.profileCount,
      userAgent: userAgent ?? this.userAgent,
      allowInsecure: allowInsecure ?? this.allowInsecure,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'enabled': enabled,
        'autoRefresh': autoRefresh,
        'refreshIntervalMinutes': refreshIntervalMinutes,
        'lastUpdatedAt': lastUpdatedAt?.toIso8601String(),
        'lastStatus': lastStatus.name,
        'lastError': lastError,
        'profileCount': profileCount,
        'userAgent': userAgent,
        'allowInsecure': allowInsecure,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory Subscription.fromJson(Map<String, dynamic> json) {
    SubscriptionStatus statusFrom(String? name) {
      return SubscriptionStatus.values.firstWhere(
        (s) => s.name == name,
        orElse: () => SubscriptionStatus.idle,
      );
    }

    DateTime? dateOrNull(Object? v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

    return Subscription(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      enabled: json['enabled'] != false,
      autoRefresh: json['autoRefresh'] == true,
      refreshIntervalMinutes: (json['refreshIntervalMinutes'] as num?)?.toInt() ?? 240,
      lastUpdatedAt: dateOrNull(json['lastUpdatedAt']),
      lastStatus: statusFrom(json['lastStatus']?.toString()),
      lastError: (json['lastError'] ?? '').toString(),
      profileCount: (json['profileCount'] as num?)?.toInt() ?? 0,
      userAgent: (json['userAgent'] ?? '').toString(),
      allowInsecure: json['allowInsecure'] == true,
      createdAt: dateOrNull(json['createdAt']),
    );
  }
}
