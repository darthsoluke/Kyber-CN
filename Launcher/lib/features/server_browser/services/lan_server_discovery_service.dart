import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/server_browser/helpers/lan_server_helper.dart';
import 'package:logging/logging.dart';

class LanServerDiscoveryService {
  final _logger = Logger('lan_server_discovery');

  Future<List<Server>> discover({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    final discovered = <String, Server>{};

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.readEventsEnabled = true;

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) {
          return;
        }

        Datagram? datagram;
        while ((datagram = socket!.receive()) != null) {
          try {
            final payload = utf8.decode(datagram!.data, allowMalformed: true);
            final decoded = jsonDecode(payload);
            if (decoded is! Map<String, dynamic>) {
              continue;
            }

            if (decoded['protocol'] != LanServerHelper.discoveryProtocol) {
              continue;
            }

            final server = LanServerHelper.fromDiscovery(
              decoded,
              datagram.address.address,
            );
            final existing = discovered[server.id];
            if (existing == null ||
                (existing.ip == InternetAddress.loopbackIPv4.address &&
                    server.ip != InternetAddress.loopbackIPv4.address)) {
              discovered[server.id] = server;
            }
          } catch (error, stackTrace) {
            _logger.fine('Failed to parse LAN discovery response: $error');
            _logger.finer(stackTrace.toString());
          }
        }
      });

      final probe = utf8.encode(LanServerHelper.discoveryProbe);
      socket.send(
        probe,
        InternetAddress('255.255.255.255'),
        LanServerHelper.discoveryPort,
      );
      socket.send(
        probe,
        InternetAddress.loopbackIPv4,
        LanServerHelper.discoveryPort,
      );

      await Future<void>.delayed(timeout);
    } finally {
      await subscription?.cancel();
      socket?.close();
    }

    final servers = discovered.values.toList()
      ..sort((a, b) {
        if (a.playerCount != b.playerCount) {
          return b.playerCount.compareTo(a.playerCount);
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    LanServerHelper.rememberAll(servers);
    return servers;
  }
}
