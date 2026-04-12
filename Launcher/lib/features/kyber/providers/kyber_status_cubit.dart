import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/rich_presence.dart';
import 'package:kyber_launcher/core/services/voip_service.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/features/server_browser/helpers/lan_server_helper.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';

class KyberStatusCubit extends Cubit<KyberStatusState> {
  bool joined = false;

  KyberStatusCubit() : super(KyberStatusInitial()) {
    _statusTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) async => onTick(),
    );

    _rpcServerTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      if (!sl.isRegistered<MaximaGameInstance>()) {
        return;
      }

      final commonState = await sl
          .get<MaximaGameInstance>()
          .clientService
          .commonClient
          .getInfo(Empty());
      if (!commonState.hasServer() && !commonState.client.hasServerId()) {
        sl.get<RichPresence>().clearPresence();
        return;
      }

      final id = commonState.hasServer()
          ? commonState.server.id
          : commonState.client.serverId;
      final server = await _resolveServer(id);
      final currentState = this.state;
      if (currentState is KyberStatusHosting) {
        emit(
          KyberStatusHosting(
            serverState: currentState.serverState,
            server: server,
          ),
        );
      } else if (currentState is KyberStatusPlaying) {
        emit(
          KyberStatusPlaying(
            serverState: currentState.serverState,
            server: server,
            joined: joined,
          ),
        );
      } else {
        emit(KyberStatusNormal());
      }

      if (server != null) {
        sl.get<RichPresence>().updatePresenceKyber(commonState, server);
      }
    });
  }

  Future<void> onTick() async {
    final isRegistered = sl.isRegistered<MaximaGameInstance>();
    if (!isRegistered) {
      final rp = sl.get<RichPresence>();
      if (state is! KyberStatusInitial || rp.started != null) {
        sl.get<RichPresence>().clearPresence();
      }

      joined = false;

      return emit(KyberStatusInitial());
    }

    try {
      final client = sl.get<MaximaGameInstance>();
      final data = await client.clientService.commonClient.getInfo(Empty());
      if (data.vivoxInitialized && client.voipSettings == null) {
        sl.get<VoipService>().setGameVoipSettings();
      }

      final isKyber = data.hasClient() || data.hasServer();
      var server = (state is KyberStatusPlaying || state is KyberStatusHosting)
          ? ((state as dynamic).server as Server?)
          : null;
      if (isKyber &&
          (state is KyberStatusInitial ||
              ((state is KyberStatusPlaying || state is KyberStatusHosting) &&
                  (state as dynamic).server == null))) {
        final id = data.hasServer() ? data.server.id : data.client.serverId;
        server = await _resolveServer(id);
        if (server != null) {
          sl.get<RichPresence>().updatePresenceKyber(data, server);
        }
      }

      if (data.hasClient()) {
        emit(
          KyberStatusPlaying(
            serverState: data.server,
            server: server,
            joined: joined,
          ),
        );
      } else if (data.hasServer()) {
        emit(KyberStatusHosting(serverState: data.server, server: server));
      } else {
        emit(KyberStatusNormal());
      }
    } catch (e) {
      if (e is GrpcError) {
        if (e.code == StatusCode.unavailable) {
          _logger.severe('Kyber gRPC server is unavailable...');
          return;
        }
      }

      print(e);
      rethrow;
    }
  }

  final _logger = Logger('status_cubit');

  Future<Server?> _resolveServer(String id) async {
    if (id.isEmpty) {
      return null;
    }

    if (LanServerHelper.isLanServerId(id)) {
      return LanServerHelper.lookup(id);
    }

    final client = sl.get<KyberGRPCService>();
    return client.serverBrowserClient.getServer(ServerRequest(id: id));
  }

  @override
  Future<void> close() {
    _statusTimer.cancel();
    _rpcServerTimer.cancel();
    return super.close();
  }

  late Timer _statusTimer;
  late Timer _rpcServerTimer;
}

class KyberStatusState {}

class KyberStatusInitial extends KyberStatusState {}

class KyberStatusNormal extends KyberStatusState {}

class KyberStatusPlaying extends KyberStatusState {
  KyberStatusPlaying({
    required this.serverState,
    this.server,
    this.joined = false,
  });

  final ServerState serverState;
  final Server? server;
  final bool joined;
}

class KyberStatusHosting extends KyberStatusState {
  KyberStatusHosting({required this.serverState, this.server});

  final ServerState serverState;
  final Server? server;
}
