import 'package:kyber/kyber.dart';
import 'package:logging/logging.dart';

class LanServerRegistry {
  LanServerRegistry._() : _logger = Logger('lan_server_registry');

  static final LanServerRegistry shared = LanServerRegistry._();

  final Logger _logger;
  final Map<String, Server> _servers = <String, Server>{};

  void remember(Server server) {
    _servers[server.id] = server;
    _logger.fine(
      'LAN_STAGE[registry.remember] '
      'id=${server.id} ip=${server.ip} port=${server.port}',
    );
  }

  void rememberAll(Iterable<Server> servers) {
    var count = 0;
    for (final server in servers) {
      remember(server);
      count++;
    }
    _logger.fine('LAN_STAGE[registry.remember_all] count=$count');
  }

  Server? lookup(String id) {
    final server = _servers[id];
    _logger.fine(
      'LAN_STAGE[registry.lookup] id=$id hit=${server != null}',
    );
    return server;
  }
}
