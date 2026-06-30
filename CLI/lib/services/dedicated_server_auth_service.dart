import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:grpc/grpc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_cli/command_runner.dart';
import 'package:kyber_cli/gen/api/maxima.dart';
import 'package:kyber_cli/models/dedicated_server_auth_context.dart';
import 'package:mason_logger/mason_logger.dart';

const _offlineApiToken = 'offline-direct';

final class DedicatedServerAuthException implements Exception {
  const DedicatedServerAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DedicatedServerAuthService {
  const DedicatedServerAuthService({required Logger logger}) : _logger = logger;

  final Logger _logger;

  Future<DedicatedServerAuthContext> resolve({
    required bool onlineMode,
    required String? credentials,
    required String? explicitKyberToken,
    required bool credentiallessHost,
  }) async {
    _validateMode(
      onlineMode: onlineMode,
      credentials: credentials,
      credentiallessHost: credentiallessHost,
    );
    _validateCredentials(credentials);

    final normalizedCredentials = _normalizeCredentials(credentials);
    final playerName = await _resolvePlayerName(
      credentials: normalizedCredentials,
      credentiallessHost: credentiallessHost,
    );
    final kyberToken = await _resolveKyberToken(
      onlineMode: onlineMode,
      explicitKyberToken: explicitKyberToken,
    );
    final userId = _stableStringHash(
      credentiallessHost
          ? 'credentialless-offline-bfii-host'
          : normalizedCredentials?.split(':').first ?? playerName,
    );

    return DedicatedServerAuthContext(
      playerName: playerName,
      kyberToken: kyberToken,
      licenseId: '${userId}_file',
      denuvoId: '${userId}_denuvo',
      credentials: normalizedCredentials,
    );
  }

  void _validateMode({
    required bool onlineMode,
    required String? credentials,
    required bool credentiallessHost,
  }) {
    if (!credentiallessHost) {
      return;
    }

    if (onlineMode) {
      throw const DedicatedServerAuthException(
        'Credentialless BFII host mode is only valid in offline/direct mode.',
      );
    }

    if (credentials != null) {
      throw const DedicatedServerAuthException(
        'Credentialless BFII host mode cannot use EA/Maxima credentials.',
      );
    }
  }

  void _validateCredentials(String? credentials) {
    if (credentials == null) {
      return;
    }

    throw const DedicatedServerAuthException(
      'Direct EA/Maxima password login is not supported by this build. '
      'Sign in through the normal EA/Maxima OAuth flow once, then start the '
      'BFII host server without KYBER_DEDICATED_CREDENTIALS.',
    );
  }

  String? _normalizeCredentials(String? credentials) {
    if (credentials == null) {
      return null;
    }

    final trimmed = credentials.trim();
    if (trimmed.startsWith('=')) {
      return trimmed.substring(1);
    }

    return trimmed;
  }

  Future<String> _resolvePlayerName({
    required String? credentials,
    required bool credentiallessHost,
  }) async {
    if (credentiallessHost) {
      _logger.info(
        'LAN_STAGE[cli.start_server.auth.skip] '
        'reason=credentialless_offline_host loginFlow=disabled',
      );
      return 'CredentiallessHost';
    }

    try {
      final player = await loginFlow();
      return player.displayName;
    } catch (e) {
      throw DedicatedServerAuthException(_formatLoginError(e));
    }
  }

  Future<String> _resolveKyberToken({
    required bool onlineMode,
    required String? explicitKyberToken,
  }) async {
    if (!onlineMode) {
      _logger.info(
        'LAN_STAGE[cli.start_server.auth.skip] reason=offline_direct '
        'tokenSource=internal_offline_sentinel',
      );
      return _offlineApiToken;
    }

    if (explicitKyberToken != null && explicitKyberToken.trim().isNotEmpty) {
      return explicitKyberToken.trim();
    }

    try {
      final authToken = await getAuthToken();
      final response = await sl.get<KyberGRPCService>().login(authToken);
      return response.token;
    } on GrpcError catch (e) {
      if (e.code == StatusCode.unauthenticated ||
          e.code == StatusCode.permissionDenied) {
        throw DedicatedServerAuthException('Kyber Login Error: ${e.message}');
      }

      throw DedicatedServerAuthException(
        'Failed to fetch Kyber auth token: $e',
      );
    }
  }

  String _formatLoginError(Object e) {
    if (e is PanicException || e is AnyhowException) {
      final message = e is PanicException
          ? e.message
          : (e as AnyhowException).message;
      if (message.contains('unknown variant `NO_SUCH_USER`')) {
        return 'Login failed: The specified user does not exist';
      }

      return 'Login failed: $message';
    }

    return 'Login failed: $e';
  }

  int _stableStringHash(String s) {
    var hash = 0;
    for (final codeUnit in s.codeUnits) {
      hash = 31 * hash + codeUnit;
    }

    return hash & 0x7fffffff;
  }
}
