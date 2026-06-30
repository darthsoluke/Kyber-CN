import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/server_browser/models/lan_server_metadata.dart';
import 'package:kyber_launcher/features/server_browser/services/lan_server_factory.dart';
import 'package:kyber_launcher/features/server_browser/services/lan_server_registry.dart';
import 'package:logging/logging.dart';

class LanServerDiscoveryService {
  final Logger _logger = Logger('lan_server_discovery');
  final LanServerFactory _factory = LanServerFactory();
  final LanServerRegistry _registry = LanServerRegistry.shared;

  Future<List<Server>> discover({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    _logger.info(
      'DIRECT_STAGE[discovery.local.start] timeoutMs=${timeout.inMilliseconds}',
    );

    final servers = await _collectResponses(
      targets: [
        _ProbeTarget(InternetAddress('255.255.255.255'), discoveryPort),
        _ProbeTarget(InternetAddress.loopbackIPv4, discoveryPort),
      ],
      timeout: timeout,
      mode: _DiscoveryMode.local,
    );

    _logger.info(
      'DIRECT_STAGE[discovery.local.finished] count=${servers.length}',
    );
    return servers;
  }

  Future<Server> discoverEndpoint({
    required String host,
    required int expectedGamePort,
    bool requiresPasswordOverride = false,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    _logger.info(
      'DIRECT_STAGE[discovery.endpoint.start] '
      'host=$host expectedGamePort=$expectedGamePort '
      'timeoutMs=${timeout.inMilliseconds}',
    );

    final target = await _resolveTarget(host);
    final servers = await _collectResponses(
      targets: [_ProbeTarget(target, discoveryPort)],
      timeout: timeout,
      mode: _DiscoveryMode.endpoint,
    );

    if (servers.isEmpty) {
      throw StateError(
        'No dedicated server metadata response from $host:$discoveryPort. '
        'Open UDP $discoveryPort on the host, router, and cloud firewall.',
      );
    }

    final server = servers.first;
    if (server.port != expectedGamePort) {
      throw StateError(
        'Dedicated server metadata responded from $host, but advertised game '
        'port ${server.port} does not match requested port $expectedGamePort.',
      );
    }

    if (requiresPasswordOverride && !server.requiresPassword) {
      throw StateError(
        'Direct connect marked the server as password protected, but the '
        'dedicated metadata says it does not require a password.',
      );
    }

    _logger.info(
      'DIRECT_STAGE[discovery.endpoint.finished] '
      'id=${server.id} ip=${server.ip} port=${server.port} '
      'mods=${server.mods.length}',
    );
    return server;
  }

  Future<InternetAddress> _resolveTarget(String host) async {
    final addresses = await InternetAddress.lookup(host);
    for (final address in addresses) {
      if (address.type == InternetAddressType.IPv4) {
        return address;
      }
    }

    throw StateError('No IPv4 address found for $host.');
  }

  Future<List<Server>> _collectResponses({
    required List<_ProbeTarget> targets,
    required Duration timeout,
    required _DiscoveryMode mode,
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    final discovered = <String, Server>{};

    try {
      final discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
      );
      socket = discoverySocket
        ..broadcastEnabled = true
        ..readEventsEnabled = true;
      _logger.info(
        'DIRECT_STAGE[discovery.socket.bound] '
        'local=${socket.address.address}:${socket.port} '
        'broadcast=${socket.broadcastEnabled}',
      );

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) {
          return;
        }

        Datagram? datagram;
        while ((datagram = socket!.receive()) != null) {
          try {
            final payload = utf8.decode(datagram!.data, allowMalformed: true);
            _logger.fine(
              'DIRECT_STAGE[discovery.response.received] '
              'from=${datagram.address.address}:${datagram.port} '
              'bytes=${datagram.data.length}',
            );
            final decoded = jsonDecode(payload);
            if (decoded is! Map<String, dynamic>) {
              _logger.fine(
                'DIRECT_STAGE[discovery.response.ignored] reason=not_json_map',
              );
              continue;
            }

            if (decoded['protocol'] != LanServerProtocol.discoveryProtocol) {
              _logger.fine(
                'DIRECT_STAGE[discovery.response.ignored] '
                'reason=protocol_mismatch protocol=${decoded['protocol']}',
              );
              continue;
            }

            final server = mode == _DiscoveryMode.endpoint
                ? _factory.fromDirectMetadata(decoded, datagram.address.address)
                : _factory.fromDiscovery(decoded, datagram.address.address);
            _registry.remember(server);
            final existing = discovered[server.id];
            if (existing == null ||
                (existing.ip == InternetAddress.loopbackIPv4.address &&
                    server.ip != InternetAddress.loopbackIPv4.address)) {
              discovered[server.id] = server;
              _logger.info(
                'DIRECT_STAGE[discovery.server.accepted] '
                'id=${server.id} ip=${server.ip} port=${server.port} '
                'name=${server.name} replaced=${existing != null}',
              );
            } else {
              _logger.fine(
                'DIRECT_STAGE[discovery.server.duplicate] '
                'id=${server.id} existingIp=${existing.ip} '
                'candidateIp=${server.ip}',
              );
            }
          } on Object catch (error, stackTrace) {
            _logger
              ..fine(
                'DIRECT_STAGE[discovery.response.parse_error] error=$error',
              )
              ..finer(stackTrace.toString());
          }
        }
      });

      final probe = utf8.encode(LanServerProtocol.discoveryProbe);
      for (final target in targets) {
        final sent = socket.send(probe, target.address, target.port);
        _logger.info(
          'DIRECT_STAGE[discovery.probe.sent] '
          'target=${target.address.address}:${target.port} bytes=$sent',
        );
      }

      await Future<void>.delayed(timeout);
    } on Object catch (error, stackTrace) {
      _logger
        ..warning('DIRECT_STAGE[discovery.error] error=$error')
        ..finer(stackTrace.toString());
      rethrow;
    } finally {
      await subscription?.cancel();
      socket?.close();
      _logger.fine(
        'DIRECT_STAGE[discovery.socket.closed]',
      );
    }

    final servers = discovered.values.toList()
      ..sort((a, b) {
        if (a.playerCount != b.playerCount) {
          return b.playerCount.compareTo(a.playerCount);
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    _registry.rememberAll(servers);
    return servers;
  }

  static const int discoveryPort = LanServerProtocol.discoveryPort;
}

enum _DiscoveryMode { local, endpoint }

class _ProbeTarget {
  const _ProbeTarget(this.address, this.port);

  final InternetAddress address;
  final int port;
}
