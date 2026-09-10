/// Xray StatsService client (gRPC over loopback, hand-written messages).
///
/// Covers exactly the `xray.app.stats.command` surface IranLink needs:
/// `QueryStats(pattern)`. Messages are hand-written against the stable
/// stats.proto (field numbers unchanged for years) to avoid a protoc
/// build step. All failures degrade to "stats unavailable" — they never
/// affect the connection itself.
library;

import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:grpc/grpc.dart';
import 'package:protobuf/protobuf.dart' as pb;

// ---------------------------------------------------------------------------
// Messages (xray/app/stats/command/command.proto)
// ---------------------------------------------------------------------------

class Stat extends pb.GeneratedMessage {
  factory Stat({String? name, Int64? value}) {
    final result = create();
    if (name != null) result.name = name;
    if (value != null) result.value = value;
    return result;
  }

  Stat._() : super();

  factory Stat.fromBuffer(List<int> data,
          [pb.ExtensionRegistry registry = pb.ExtensionRegistry.EMPTY,]) =>
      create()..mergeFromBuffer(data, registry);

  static final pb.BuilderInfo _i = pb.BuilderInfo(
    'Stat',
    package: const pb.PackageName('xray.app.stats.command'),
    createEmptyInstance: create,
  )
    ..aOS(1, 'name')
    ..aInt64(2, 'value')
    ..hasRequiredFields = false;

  @override
  pb.BuilderInfo get info_ => _i;

  static Stat create() => Stat._();

  @override
  Stat createEmptyInstance() => create();

  @override
  Stat clone() => Stat()..mergeFromMessage(this);

  String get name => $_getSZ(0);
  set name(String v) => $_setString(0, v);

  Int64 get value => $_getI64(1);
  set value(Int64 v) => $_setInt64(1, v);
}

class QueryStatsRequest extends pb.GeneratedMessage {
  factory QueryStatsRequest({String? pattern, bool? reset}) {
    final result = create();
    if (pattern != null) result.pattern = pattern;
    if (reset != null) result.reset = reset;
    return result;
  }

  QueryStatsRequest._() : super();

  factory QueryStatsRequest.fromBuffer(List<int> data,
          [pb.ExtensionRegistry registry = pb.ExtensionRegistry.EMPTY,]) =>
      create()..mergeFromBuffer(data, registry);

  static final pb.BuilderInfo _i = pb.BuilderInfo(
    'QueryStatsRequest',
    package: const pb.PackageName('xray.app.stats.command'),
    createEmptyInstance: create,
  )
    ..aOS(1, 'pattern')
    ..aOB(2, 'reset')
    ..hasRequiredFields = false;

  @override
  pb.BuilderInfo get info_ => _i;

  static QueryStatsRequest create() => QueryStatsRequest._();

  @override
  QueryStatsRequest createEmptyInstance() => create();

  @override
  QueryStatsRequest clone() => QueryStatsRequest()..mergeFromMessage(this);

  String get pattern => $_getSZ(0);
  set pattern(String v) => $_setString(0, v);

  bool get reset => $_getBF(1);
  set reset(bool v) => $_setBool(1, v);
}

class QueryStatsResponse extends pb.GeneratedMessage {
  QueryStatsResponse._() : super();

  factory QueryStatsResponse.fromBuffer(List<int> data,
          [pb.ExtensionRegistry registry = pb.ExtensionRegistry.EMPTY,]) =>
      create()..mergeFromBuffer(data, registry);

  static final pb.BuilderInfo _i = pb.BuilderInfo(
    'QueryStatsResponse',
    package: const pb.PackageName('xray.app.stats.command'),
    createEmptyInstance: create,
  )
    ..pc<Stat>(2, 'stat', pb.PbFieldType.PM, subBuilder: Stat.create)
    ..hasRequiredFields = false;

  @override
  pb.BuilderInfo get info_ => _i;

  static QueryStatsResponse create() => QueryStatsResponse._();

  @override
  QueryStatsResponse createEmptyInstance() => create();

  @override
  QueryStatsResponse clone() => create()..mergeFromMessage(this);

  List<Stat> get stat => $_getList(0);
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

class StatsServiceClient extends Client {
  StatsServiceClient(
    super.channel, {
    super.options,
    super.interceptors,
  });

  static final _$queryStats = ClientMethod<QueryStatsRequest, QueryStatsResponse>(
    '/xray.app.stats.command.StatsService/QueryStats',
    (QueryStatsRequest value) => value.writeToBuffer(),
    (List<int> value) => QueryStatsResponse.fromBuffer(value),
  );

  ResponseFuture<QueryStatsResponse> queryStats(
    QueryStatsRequest request, {
    CallOptions? options,
  }) =>
      $createUnaryCall(_$queryStats, request, options: options);
}

class ProxyTraffic {
  const ProxyTraffic({required this.uplinkBytes, required this.downlinkBytes});

  final int uplinkBytes;
  final int downlinkBytes;
}

class XrayStatsClient {
  XrayStatsClient({this.timeout = const Duration(seconds: 3)});

  final Duration timeout;

  Future<Map<String, int>> queryStats({
    required String host,
    required int port,
    required String pattern,
  }) async {
    final channel = ClientChannel(
      host,
      port: port,
      options: const ChannelOptions(
        credentials: ChannelCredentials.insecure(),
      ),
    );
    try {
      final client = StatsServiceClient(channel);
      final response = await client
          .queryStats(QueryStatsRequest(pattern: pattern, reset: false))
          .timeout(timeout);
      await channel.shutdown();
      return {for (final s in response.stat) s.name: s.value.toInt()};
    } on Object {
      try {
        await channel.shutdown();
      } on Object {
        // ignore shutdown errors
      }
      rethrow;
    }
  }

  /// Traffic counters for the main `proxy` outbound, or null when the API
  /// is unreachable (stats disabled, core starting, API blocked).
  Future<ProxyTraffic?> proxyTraffic(
      {required String host, required int port,}) async {
    try {
      final stats = await queryStats(
        host: host,
        port: port,
        pattern: 'outbound>>>proxy>>>traffic>>>',
      );
      final up = stats['outbound>>>proxy>>>traffic>>>uplink'];
      final down = stats['outbound>>>proxy>>>traffic>>>downlink'];
      if (up == null || down == null) return null;
      return ProxyTraffic(uplinkBytes: up, downlinkBytes: down);
    } on Object {
      return null;
    }
  }
}
