import 'package:kyber/kyber.dart';

enum LanServerAuthMode {
  offline('offline'),
  online('online'),
  unavailable('unavailable')
  ;

  const LanServerAuthMode(this.value);

  final String value;

  static LanServerAuthMode parse(String? value) {
    for (final mode in values) {
      if (mode.value == value) {
        return mode;
      }
    }

    return LanServerAuthMode.offline;
  }
}

class LanServerProtocol {
  const LanServerProtocol._();

  static const String discoveryProbe = 'KYBER_LAN_DISCOVERY_V1';
  static const String discoveryProtocol = 'kyber_lan_v1';
  static const int discoveryPort = 25249;
  static const int defaultGamePort = 25200;
}

class LanServerIdentity {
  const LanServerIdentity._();

  static bool isSyntheticId(String id) =>
      id.startsWith('direct:') || id.startsWith('lan:');

  static String makeSyntheticId(String address, int port) =>
      'direct:$address:$port';
}

class LanServerMetadata {
  const LanServerMetadata({
    required this.source,
    required this.authMode,
    required this.joinable,
    required this.address,
    required this.dedicated,
  });

  factory LanServerMetadata.fromServer(Server server) {
    return LanServerMetadata(
      source:
          server.meta[sourceKey] == '1' || server.meta[legacySourceKey] == '1',
      authMode: LanServerAuthMode.parse(
        server.meta[authModeKey] ?? server.meta[legacyAuthModeKey],
      ),
      joinable:
          (server.meta[joinableKey] ?? server.meta[legacyJoinableKey]) != '0',
      address:
          server.meta[addressKey] ?? server.meta[legacyAddressKey] ?? server.ip,
      dedicated:
          server.meta[dedicatedKey] == '1' ||
          server.meta[legacyDedicatedKey] == '1',
    );
  }

  factory LanServerMetadata.direct({required String address}) {
    return LanServerMetadata(
      source: true,
      authMode: LanServerAuthMode.offline,
      joinable: true,
      address: address,
      dedicated: true,
    );
  }

  factory LanServerMetadata.discovery({
    required String authMode,
    required bool joinable,
    required String address,
    required bool dedicated,
  }) {
    return LanServerMetadata(
      source: true,
      authMode: LanServerAuthMode.parse(authMode),
      joinable: joinable,
      address: address,
      dedicated: dedicated,
    );
  }

  static const String sourceKey = 'direct_source';
  static const String authModeKey = 'direct_auth_mode';
  static const String joinableKey = 'direct_joinable';
  static const String addressKey = 'direct_address';
  static const String dedicatedKey = 'direct_dedicated';

  static const String legacySourceKey = 'lan_source';
  static const String legacyAuthModeKey = 'lan_auth_mode';
  static const String legacyJoinableKey = 'lan_joinable';
  static const String legacyAddressKey = 'lan_address';
  static const String legacyDedicatedKey = 'lan_dedicated';

  final bool source;
  final LanServerAuthMode authMode;
  final bool joinable;
  final String address;
  final bool dedicated;

  bool get hasApiBackedJoin => authMode == LanServerAuthMode.online;

  List<MapEntry<String, String>> toMetaEntries() {
    return <MapEntry<String, String>>[
      MapEntry(sourceKey, source ? '1' : '0'),
      MapEntry(authModeKey, authMode.value),
      MapEntry(joinableKey, joinable ? '1' : '0'),
      MapEntry(addressKey, address),
      MapEntry(dedicatedKey, dedicated ? '1' : '0'),
    ];
  }
}
