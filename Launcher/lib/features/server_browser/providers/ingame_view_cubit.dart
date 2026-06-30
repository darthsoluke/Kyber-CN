import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/server_browser/helpers/lan_server_helper.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class IngameViewCubit extends Cubit<IngameViewState> {
  IngameViewCubit() : super(const IngameViewState());

  final _logger = Logger('ingame_view_cubit');
  Timer? _keepAliveTimer;

  WebSocketChannel? _channel;

  @override
  Future<void> close() {
    unloadServer();
    return super.close();
  }

  void unloadServer() {
    _logger.info('Unloading server');

    unawaited(_channel?.sink.close());
    _keepAliveTimer?.cancel();

    emit(const IngameViewState());

    if (isClosed) {
      return;
    }
  }

  Future<void> loadServer(Server server) async {
    emit(IngameViewState(id: server.id, server: server));
    await selectServer(serverId: server.id);
  }

  Future<void> selectServer({String? serverId}) async {
    if (state.server == null && serverId == null) {
      return;
    }

    await _channel?.sink.close();
    _keepAliveTimer?.cancel();

    try {
      final id = serverId ?? state.id;
      final cachedServer = state.server;
      _logger.info('Loading server $id');
      emit(IngameViewState(id: id));
      final service = sl.get<KyberGRPCService>();
      late final Server server;
      if (id != null && LanServerHelper.isLanServerId(id)) {
        final lanServer = LanServerHelper.lookup(id) ?? cachedServer;
        if (lanServer == null) {
          throw Exception('LAN server is no longer available');
        }
        server = lanServer;
      } else {
        server = await service.serverBrowserClient.getServer(
          ServerRequest(id: id),
        );
      }

      emit(state.copyWith(id: id, server: server));

      if (id != null && LanServerHelper.isLanServerId(id)) {
        _logger.info('Skipping websocket subscription for offline LAN server');
        return;
      }

      _logger.info('Subscribing to server events');

      final url = service.webSocketUri('/ws/client/${server.id}');
      _logger.info('Subscribing to server events at $url');
      _channel = IOWebSocketChannel.connect(
        url,
        headers: {
          'Authorization': service.token,
        },
        connectTimeout: const Duration(seconds: 10),
      );

      await _channel?.ready;

      _channel?.stream.listen(
        (event) {
          try {
            final data = ServerManagementAPIEvent.fromBuffer(
              event as List<int>,
            );
            if (data.hasPlayers()) {
              _logger.fine('Received players event');
              emit(state.copyWith(players: data.players.players));
            } else if (data.hasConsole()) {
              _logger.fine('Received console event');
              final commands = List<String>.from(state.commands)
                ..add(data.console.message);
              emit(state.copyWith(commands: commands));
            }
          } on Object catch (e, s) {
            _logger.severe('Error parsing event', e, s);
          }
        },
        onDone: () {
          _logger.info('Stream done');
          unloadServer();
        },
        onError: (dynamic e, StackTrace s) {
          NotificationService.showNotification(
            title: 'Server error',
            message: 'An error occurred while communicating with the server',
          );
          _logger.severe('Stream error', e, s);
          unloadServer();
        },
      );

      _keepAliveTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) async => _channel?.sink.add(''),
      );

      await Future<void>.delayed(const Duration(seconds: 3));
    } on WebSocketException catch (e, s) {
      var error = 'Failed to connect to websocket';
      switch (e.httpStatusCode ?? 0) {
        case 401:
          error = 'Failed to connect to websocket: Unauthorized';
        case 404:
          error = 'The specified server was not found';
      }

      _logger.severe('Failed to connect to websocket', e, s);
      NotificationService.error(message: error);
      unloadServer();
    } on GrpcError catch (e, s) {
      _logger.severe('Error loading server:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message:
            e.message ??
            'An error occurred while communicating with the server',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    } on SocketException catch (e, s) {
      _logger.severe('Socket error:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message: 'An error occurred while communicating with the server',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    } on Object catch (e, s) {
      _logger.severe('Error loading server:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message: 'An error occurred while communicating with the server',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    }
  }
}

class IngameViewState {
  const IngameViewState({
    this.id,
    this.server,
    this.players = const [],
    this.commands = const [],
  });

  final String? id;
  final Server? server;
  final List<ServerPlayer> players;
  final List<String> commands;

  IngameViewState copyWith({
    String? id,
    Server? server,
    List<ServerPlayer>? players,
    List<String>? commands,
  }) {
    return IngameViewState(
      id: id ?? this.id,
      server: server ?? this.server,
      players: players ?? this.players,
      commands: commands ?? this.commands,
    );
  }
}
