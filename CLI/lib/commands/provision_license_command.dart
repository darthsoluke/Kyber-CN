import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:kyber_cli/gen/api/maxima.dart';
import 'package:mason_logger/mason_logger.dart';

class ProvisionLicenseCommand extends Command<int> {
  ProvisionLicenseCommand({required Logger logger}) : _logger = logger {
    argParser
      ..addOption(
        'token',
        help:
            'Optional EA/Maxima access token. If omitted, the normal OAuth '
            'session is used.',
        valueHelp: 'access-token',
      )
      ..addOption(
        'game-path',
        help: 'Battlefront II executable path for OOA activation detection',
        valueHelp: 'path/to/starwarsbattlefrontii.exe',
      )
      ..addOption(
        'content-id',
        help: 'EA content ID to provision',
        defaultsTo: '1035052',
      );
  }

  final Logger _logger;

  @override
  String get description =>
      'Provisions a BFII license through the normal EA OAuth/Maxima session.';

  @override
  String get name => 'provision_license';

  @override
  Future<int> run() async {
    final gamePath = _resolveRequiredText('game-path', 'KYBER_GAME_PATH');
    if (gamePath == null) {
      return ExitCode.usage.code;
    }
    if (!File(gamePath).existsSync()) {
      _logger.err('game-path points to a missing file: $gamePath');
      return ExitCode.usage.code;
    }

    final contentId = (argResults?['content-id'] as String?)?.trim();
    if (contentId == null || contentId.isEmpty) {
      _logger.err('content-id is required.');
      return ExitCode.usage.code;
    }

    _logger.info(
      'Provisioning BFII license for content $contentId into this runtime...',
    );

    try {
      await startMaxima(dummyAuthStorage: false);
      final explicitToken = _resolveToken();
      if (explicitToken == null) {
        final player = await loginFlow();
        _logger.info(
          'Using EA/Maxima OAuth session for ${player.displayName}.',
        );
      } else {
        await loginWithToken(token: explicitToken);
        _logger.info('Using explicit EA/Maxima access token.');
      }
      final token = explicitToken ?? await getAuthToken();
      await provisionGameLicense(
        gamePath: gamePath,
        user: token,
        pass: '',
        contentId: contentId,
      );
    } catch (e) {
      _logger.err('License provisioning failed: ${_formatProvisionError(e)}');
      return ExitCode.software.code;
    }

    _logger.success('License provisioned successfully for this machine.');
    return ExitCode.success.code;
  }

  String? _resolveToken() {
    final optionValue = argResults?['token'] as String?;
    if (optionValue != null && optionValue.trim().isNotEmpty) {
      return optionValue.trim();
    }

    for (final name in const ['KYBER_EA_ACCESS_TOKEN', 'MAXIMA_ACCESS_TOKEN']) {
      final value = Platform.environment[name];
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  String? _resolveRequiredText(String option, String envName) {
    final optionValue = argResults?[option] as String?;
    if (optionValue != null && optionValue.trim().isNotEmpty) {
      return optionValue.trim();
    }

    final envValue = Platform.environment[envName];
    if (envValue != null && envValue.trim().isNotEmpty) {
      return envValue.trim();
    }

    _logger.err('$option is required. Pass --$option or set $envName.');
    return null;
  }

  String _formatProvisionError(Object error) {
    return error.toString().split('Stack backtrace:').first.trim();
  }
}
