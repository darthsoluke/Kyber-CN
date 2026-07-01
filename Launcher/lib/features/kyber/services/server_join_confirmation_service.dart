import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_status_cubit.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:logging/logging.dart';

class ServerJoinConfirmationService {
  ServerJoinConfirmationService({Logger? logger})
    : _logger = logger ?? Logger('server_join_confirmation');

  final Logger _logger;

  static const _pollInterval = Duration(seconds: 1);
  static const _rpcTimeout = Duration(seconds: 2);
  static const _interfaceTimeout = Duration(seconds: 45);
  static const _joinTimeout = Duration(seconds: 150);

  void resetJoinSignal() {
    _readStatusCubit().joined = false;
    _logger.info('LAN_STAGE[join.confirm.reset]');
  }

  Future<void> waitForClientInterface(
    MaximaGameInstance instance, {
    Duration timeout = _interfaceTimeout,
    void Function(String messageKey)? onProgress,
  }) async {
    _logger.info(
      'DIRECT_STAGE[join.confirm.interface.wait.start] '
      'pid=${instance.pid} timeout=${timeout.inSeconds}s',
    );
    onProgress?.call('maxima.progress.waitKyberInterface');
    await _pollUntil(
      timeout: timeout,
      timeoutMessage:
          'Timed out waiting for the KYBER module interface after BFII launch.',
      action: () async {
        await instance.clientService.commonClient
            .getInfo(Empty())
            .timeout(_rpcTimeout);
        _logger.info(
          'LAN_STAGE[join.confirm.interface.ready] pid=${instance.pid}',
        );
        return true;
      },
    );
    _logger.info(
      'DIRECT_STAGE[join.confirm.interface.wait.done] pid=${instance.pid}',
    );
  }

  Future<void> waitForJoin(
    MaximaGameInstance instance,
    JoinServerRequest request, {
    Duration timeout = _joinTimeout,
    void Function(String messageKey)? onProgress,
  }) async {
    final statusCubit = _readStatusCubit();
    var observedClientState = false;
    _logger.info(
      'DIRECT_STAGE[join.confirm.join.wait.start] '
      'pid=${instance.pid} id=${request.id} ip=${request.ip}:${request.port} '
      'type=${request.type.name} '
      'joinTokenPresent=${request.joinToken.isNotEmpty} '
      'passwordPresent=${request.password.isNotEmpty} '
      'spectate=${request.spectate} timeout=${timeout.inSeconds}s',
    );
    onProgress?.call('maxima.progress.joinConfirm');

    await _pollUntil(
      timeout: timeout,
      timeoutMessage:
          'Timed out waiting for BFII to enter the server. The join request '
          'was sent, but the launcher never received KYBER OnServerJoined. '
          'Check the target address, UDP port, firewall/NAT, server password, '
          'required mods, and the KYBER module log.',
      action: () async {
        if (statusCubit.joined) {
          onProgress?.call('maxima.progress.joinConfirmed');
          _logger.info(
            'LAN_STAGE[join.confirm.joined] id=${request.id} '
            'ip=${request.ip}:${request.port}',
          );
          return true;
        }

        final state = await instance.clientService.commonClient
            .getInfo(Empty())
            .timeout(_rpcTimeout);
        if (state.hasClient() && !observedClientState) {
          observedClientState = true;
          onProgress?.call('maxima.progress.joinConnectionObserved');
          _logger.info(
            'LAN_STAGE[join.confirm.client_state] '
            'requestedId=${request.id} reportedId=${state.client.serverId}',
          );
        }

        return false;
      },
    );
    _logger.info(
      'DIRECT_STAGE[join.confirm.join.wait.done] '
      'pid=${instance.pid} id=${request.id}',
    );
  }

  Future<void> _pollUntil({
    required Duration timeout,
    required String timeoutMessage,
    required Future<bool> Function() action,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    var attempts = 0;

    while (DateTime.now().isBefore(deadline)) {
      attempts++;
      try {
        if (await action()) {
          return;
        }
      } on GrpcError catch (e) {
        lastError = e;
        if (e.code != StatusCode.unavailable &&
            e.code != StatusCode.deadlineExceeded) {
          rethrow;
        }
      } on TimeoutException catch (e) {
        lastError = e;
      }

      if (attempts == 1 || attempts % 10 == 0) {
        _logger.info(
          'DIRECT_STAGE[join.confirm.poll.waiting] '
          'attempt=$attempts '
          'remainingMs=${deadline.difference(DateTime.now()).inMilliseconds} '
          'lastError=${lastError ?? ''}',
        );
      }

      await Future<void>.delayed(_pollInterval);
    }

    if (lastError == null) {
      throw TimeoutException(timeoutMessage, timeout);
    }

    throw TimeoutException('$timeoutMessage Last error: $lastError', timeout);
  }

  KyberStatusCubit _readStatusCubit() {
    final context = navigatorKey.currentContext;
    if (context == null) {
      throw StateError('Navigator context is not available for join tracking.');
    }

    return context.read<KyberStatusCubit>();
  }
}
