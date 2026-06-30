import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/server_browser/models/lan_server_metadata.dart';
import 'package:kyber_launcher/features/server_browser/services/lan_server_discovery_service.dart';
import 'package:kyber_launcher/features/server_browser/services/lan_server_factory.dart';
import 'package:kyber_launcher/features/server_browser/services/lan_server_registry.dart';

class LanServerHelper {
  LanServerHelper._();

  static final LanServerFactory _factory = LanServerFactory();
  static final LanServerRegistry _registry = LanServerRegistry.shared;
  static final LanServerDiscoveryService _discovery =
      LanServerDiscoveryService();

  static const String discoveryProbe = LanServerProtocol.discoveryProbe;
  static const String discoveryProtocol = LanServerProtocol.discoveryProtocol;
  static const int discoveryPort = LanServerProtocol.discoveryPort;
  static const int defaultGamePort = LanServerProtocol.defaultGamePort;

  static bool isLanServer(Server server) =>
      LanServerMetadata.fromServer(server).source || isLanServerId(server.id);

  static bool isLanServerId(String id) => LanServerIdentity.isSyntheticId(id);

  static bool hasApiBackedJoin(Server server) =>
      isLanServer(server) &&
      LanServerMetadata.fromServer(server).hasApiBackedJoin &&
      !isLanServerId(server.id) &&
      server.id.isNotEmpty;

  static bool isJoinable(Server server) =>
      !isLanServer(server) || LanServerMetadata.fromServer(server).joinable;

  static String makeSyntheticId(String address, int port) =>
      LanServerIdentity.makeSyntheticId(address, port);

  static void remember(Server server) => _registry.remember(server);

  static void rememberAll(Iterable<Server> servers) =>
      _registry.rememberAll(servers);

  static Server? lookup(String id) => _registry.lookup(id);

  static Future<Server> directConnect({
    required String address,
    required int port,
    bool requiresPassword = false,
  }) async {
    final server = await _discovery.discoverEndpoint(
      host: address,
      expectedGamePort: port,
      requiresPasswordOverride: requiresPassword,
    );
    remember(server);
    return server;
  }

  static Server fromDirectMetadata(Map<String, dynamic> data, String address) {
    final server = _factory.fromDirectMetadata(data, address);
    remember(server);
    return server;
  }

  static Server fromDiscovery(Map<String, dynamic> data, String address) {
    final server = _factory.fromDiscovery(data, address);
    remember(server);
    return server;
  }
}
