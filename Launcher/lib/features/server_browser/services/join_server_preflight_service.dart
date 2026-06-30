import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/server_browser/helpers/lan_server_helper.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';

class JoinServerPreflightResult {
  const JoinServerPreflightResult._({
    required this.allowed,
    this.messageKey,
    this.message,
    this.reason = '',
    this.skippedApi = false,
  });

  const JoinServerPreflightResult.allowed({bool skippedApi = false})
    : this._(allowed: true, skippedApi: skippedApi);

  const JoinServerPreflightResult.blocked({
    String? messageKey,
    String? message,
    String reason = '',
  }) : this._(
         allowed: false,
         messageKey: messageKey,
         message: message,
         reason: reason,
       );

  final bool allowed;
  final String? messageKey;
  final String? message;
  final String reason;
  final bool skippedApi;
}

class JoinServerPreflightService {
  JoinServerPreflightService({
    KyberGRPCService? kyber,
    Logger? logger,
  }) : _kyber = kyber ?? sl.get<KyberGRPCService>(),
       _logger = logger ?? Logger('join_server_preflight');

  final KyberGRPCService _kyber;
  final Logger _logger;

  bool usesApiValidation(Server server) {
    return !LanServerHelper.isLanServer(server) ||
        LanServerHelper.hasApiBackedJoin(server);
  }

  Future<JoinServerPreflightResult> checkPassword({
    required Server server,
    required String password,
  }) async {
    _logger.info(
      'LAN_STAGE[join_dialog.password_check.start] '
      'id=${server.id} isLan=${LanServerHelper.isLanServer(server)} '
      'apiBackedJoin=${LanServerHelper.hasApiBackedJoin(server)} '
      'passwordPresent=${password.isNotEmpty}',
    );

    if (!usesApiValidation(server)) {
      if (server.requiresPassword && password.isEmpty) {
        _logger.warning(
          'LAN_STAGE[join_dialog.password_check.blocked] '
          'id=${server.id} reason=missing_lan_password',
        );
        return const JoinServerPreflightResult.blocked(
          messageKey: 'join.enterPasswordContinue',
          reason: 'missing_lan_password',
        );
      }

      _logger.info(
        'LAN_STAGE[join_dialog.password_check.skip_api] '
        'id=${server.id} reason=lan_direct',
      );
      return const JoinServerPreflightResult.allowed(skippedApi: true);
    }

    _logger.info(
      'LAN_STAGE[join_dialog.password_check.api.start] id=${server.id}',
    );
    final result = await _kyber.serverBrowserClient.canJoinServer(
      CanJoinServerRequest(id: server.id, password: password),
    );

    if (result.canJoin) {
      _logger.info(
        'LAN_STAGE[join_dialog.password_check.api.allowed] id=${server.id}',
      );
      return const JoinServerPreflightResult.allowed();
    }

    _logger.warning(
      'LAN_STAGE[join_dialog.password_check.api.denied] '
      'id=${server.id} reason=${result.reason}',
    );
    return JoinServerPreflightResult.blocked(
      messageKey: 'join.invalidPassword',
      reason: result.reason,
    );
  }

  Future<JoinServerPreflightResult> validateSubmit({
    required Server server,
    required String password,
  }) async {
    if (LanServerHelper.isLanServer(server) &&
        !LanServerHelper.isJoinable(server)) {
      _logger.warning(
        'LAN_STAGE[join_dialog.submit.blocked] '
        'id=${server.id} reason=lan_not_registered',
      );
      return const JoinServerPreflightResult.blocked(
        messageKey: 'join.lanNotRegistered',
        reason: 'lan_not_registered',
      );
    }

    final useApiValidation = usesApiValidation(server);
    _logger.info(
      'LAN_STAGE[join_dialog.submit.preflight] '
      'id=${server.id} useApiValidation=$useApiValidation '
      'requiresPassword=${server.requiresPassword} '
      'passwordPresent=${password.isNotEmpty}',
    );

    if (!useApiValidation || server.requiresPassword) {
      return const JoinServerPreflightResult.allowed();
    }

    _logger.info('LAN_STAGE[join_dialog.submit.api.start] id=${server.id}');
    final result = await _kyber.serverBrowserClient.canJoinServer(
      CanJoinServerRequest(id: server.id, password: password),
    );

    if (result.canJoin) {
      _logger.info(
        'LAN_STAGE[join_dialog.submit.api.allowed] id=${server.id}',
      );
      return const JoinServerPreflightResult.allowed();
    }

    _logger.warning(
      'LAN_STAGE[join_dialog.submit.api.denied] '
      'id=${server.id} reason=${result.reason}',
    );
    return JoinServerPreflightResult.blocked(message: result.reason);
  }
}
