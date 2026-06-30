import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/server_browser/models/lan_server_metadata.dart';
import 'package:logging/logging.dart';

class LanServerFactory {
  LanServerFactory({Logger? logger})
    : _logger = logger ?? Logger('lan_server_factory');

  final Logger _logger;

  Server directConnect({
    required String address,
    required int port,
    bool requiresPassword = false,
  }) {
    final metadata = LanServerMetadata.direct(address: address);
    final server = Server(
      id: LanServerIdentity.makeSyntheticId(address, port),
      name: 'Direct $address:$port',
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
      meta: metadata.toMetaEntries(),
      region: '',
      mapImageHash: '',
    );

    _logger.info(
      'DIRECT_STAGE[server.normalize.direct.manual] '
      'id=${server.id} address=$address port=$port '
      'requiresPassword=$requiresPassword',
    );
    return server;
  }

  Server fromDirectMetadata(Map<String, dynamic> data, String address) {
    return _fromMetadataPayload(
      data,
      resolvedAddress: address,
      sourceAddress: address,
      stage: 'direct',
    );
  }

  Server fromDiscovery(Map<String, dynamic> data, String address) {
    final advertisedAddress = (data['address'] as String?)?.trim();
    final resolvedAddress =
        advertisedAddress != null && advertisedAddress.isNotEmpty
        ? advertisedAddress
        : address;
    return _fromMetadataPayload(
      data,
      resolvedAddress: resolvedAddress,
      sourceAddress: address,
      stage: 'discovery',
      advertisedAddress: advertisedAddress,
    );
  }

  Server _fromMetadataPayload(
    Map<String, dynamic> data, {
    required String resolvedAddress,
    required String sourceAddress,
    required String stage,
    String? advertisedAddress,
  }) {
    final authMode =
        data['authMode'] as String? ?? LanServerAuthMode.offline.value;
    final advertisedId = data['serverId'] as String? ?? '';
    final port =
        (data['port'] as num?)?.toInt() ?? LanServerProtocol.defaultGamePort;
    final metadata = LanServerMetadata.discovery(
      authMode: authMode,
      joinable: data['joinable'] as bool? ?? true,
      address: resolvedAddress,
      dedicated: data['dedicated'] as bool? ?? false,
    );
    final serverId = metadata.hasApiBackedJoin && advertisedId.isNotEmpty
        ? advertisedId
        : LanServerIdentity.makeSyntheticId(resolvedAddress, port);

    final mods = ((data['mods'] as List?) ?? const <dynamic>[])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (mod) => ServerMod(
            name: mod['name'] as String? ?? '',
            version: mod['version'] as String? ?? '',
            link: mod['link'] as String? ?? '',
            fileSize: $fixnum.Int64((mod['fileSize'] as num?)?.toInt() ?? 0),
          ),
        )
        .toList();

    final server = Server(
      id: serverId,
      name: data['name'] as String? ?? 'Kyber Direct Server',
      levelSetup: LevelSetup(
        map: data['level'] as String? ?? '',
        mode: data['mode'] as String? ?? '',
        mapName: data['mapName'] as String? ?? '',
        modeName: data['modeName'] as String? ?? '',
      ),
      creator: data['creator'] as String? ?? resolvedAddress,
      creatorId: '',
      official: false,
      requiresPassword: data['requiresPassword'] as bool? ?? false,
      mods: mods,
      playerCount: (data['playerCount'] as num?)?.toInt() ?? 0,
      maxPlayerCount: (data['maxPlayerCount'] as num?)?.toInt() ?? 0,
      requiresProxy: false,
      ip: resolvedAddress,
      port: port,
      description: data['description'] as String? ?? '',
      meta: metadata.toMetaEntries(),
      region: '',
      mapImageHash: '',
    );

    _logger.info(
      'DIRECT_STAGE[server.normalize.$stage] '
      'sourceAddress=$sourceAddress '
      'advertisedAddress=${advertisedAddress ?? ''} '
      'resolvedAddress=$resolvedAddress id=${server.id} '
      'authMode=$authMode apiBackedJoin=${metadata.hasApiBackedJoin} '
      'joinable=${metadata.joinable} port=$port mods=${mods.length}',
    );
    return server;
  }
}
