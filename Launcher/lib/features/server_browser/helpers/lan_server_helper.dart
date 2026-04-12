import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:kyber/kyber.dart';

class LanServerHelper {
  LanServerHelper._();

  static const String discoveryProbe = 'KYBER_LAN_DISCOVERY_V1';
  static const String discoveryProtocol = 'kyber_lan_v1';
  static const int discoveryPort = 25249;
  static const int defaultGamePort = 25200;

  static const String _sourceKey = 'lan_source';
  static const String _authModeKey = 'lan_auth_mode';
  static const String _joinableKey = 'lan_joinable';
  static const String _addressKey = 'lan_address';
  static const String _dedicatedKey = 'lan_dedicated';

  static final Map<String, Server> _registry = <String, Server>{};

  static bool isLanServer(Server server) =>
      server.meta[_sourceKey] == '1' || isLanServerId(server.id);

  static bool isLanServerId(String id) => id.startsWith('lan:');

  static bool hasApiBackedJoin(Server server) =>
      isLanServer(server) &&
      server.meta[_authModeKey] == 'online' &&
      !isLanServerId(server.id) &&
      server.id.isNotEmpty;

  static bool isJoinable(Server server) =>
      !isLanServer(server) || server.meta[_joinableKey] != '0';

  static String makeSyntheticId(String address, int port) =>
      'lan:$address:$port';

  static void remember(Server server) {
    _registry[server.id] = server;
  }

  static void rememberAll(Iterable<Server> servers) {
    for (final server in servers) {
      remember(server);
    }
  }

  static Server? lookup(String id) => _registry[id];

  static Server directConnect({
    required String address,
    required int port,
    bool requiresPassword = false,
  }) {
    final server = Server(
      id: makeSyntheticId(address, port),
      name: 'LAN $address:$port',
      levelSetup: LevelSetup(map: '', mode: '', mapName: '', modeName: ''),
      creator: address,
      creatorId: '',
      official: false,
      requiresPassword: requiresPassword,
      mods: const <ServerMod>[],
      playerCount: 0,
      maxPlayerCount: 0,
      requiresProxy: false,
      ip: address,
      port: port,
      description: '',
      meta: [
        const MapEntry(_sourceKey, '1'),
        const MapEntry(_authModeKey, 'offline'),
        const MapEntry(_joinableKey, '1'),
        MapEntry(_addressKey, address),
        const MapEntry(_dedicatedKey, '0'),
      ],
      region: '',
      mapImageHash: '',
    );

    remember(server);
    return server;
  }

  static Server fromDiscovery(Map<String, dynamic> data, String address) {
    final authMode = data['authMode'] as String? ?? 'offline';
    final advertisedId = data['serverId'] as String? ?? '';
    final port = (data['port'] as num?)?.toInt() ?? defaultGamePort;
    final serverId = authMode == 'online' && advertisedId.isNotEmpty
        ? advertisedId
        : makeSyntheticId(address, port);

    final mods = ((data['mods'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (mod) => ServerMod(
            name: mod['name'] as String? ?? '',
            version: mod['version'] as String? ?? '',
            link: mod['link'] as String? ?? '',
            fileSize: $fixnum.Int64((mod['fileSize'] as num?)?.toInt() ?? 0),
          ),
        )
        .toList();

    final meta = <MapEntry<String, String>>[
      const MapEntry(_sourceKey, '1'),
      MapEntry(_authModeKey, authMode),
      MapEntry(
        _joinableKey,
        (data['joinable'] as bool? ?? true) ? '1' : '0',
      ),
      MapEntry(_addressKey, address),
      MapEntry(
        _dedicatedKey,
        (data['dedicated'] as bool? ?? false) ? '1' : '0',
      ),
    ];

    final server = Server(
      id: serverId,
      name: data['name'] as String? ?? 'Kyber LAN Server',
      levelSetup: LevelSetup(
        map: data['level'] as String? ?? '',
        mode: data['mode'] as String? ?? '',
        mapName: data['mapName'] as String? ?? '',
        modeName: data['modeName'] as String? ?? '',
      ),
      creator: data['creator'] as String? ?? address,
      creatorId: '',
      official: false,
      requiresPassword: data['requiresPassword'] as bool? ?? false,
      mods: mods,
      playerCount: (data['playerCount'] as num?)?.toInt() ?? 0,
      maxPlayerCount: (data['maxPlayerCount'] as num?)?.toInt() ?? 0,
      requiresProxy: false,
      ip: address,
      port: port,
      description: data['description'] as String? ?? '',
      meta: meta,
      region: '',
      mapImageHash: '',
    );

    remember(server);
    return server;
  }
}
