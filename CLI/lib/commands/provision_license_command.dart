import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:kyber_cli/gen/api/maxima.dart';
import 'package:mason_logger/mason_logger.dart';

class ProvisionLicenseCommand extends Command<int> {
  ProvisionLicenseCommand({required Logger logger}) : _logger = logger {
    argParser
      ..addOption(
        'credentials',
        abbr: 'c',
        help: 'EA/Maxima credentials used once to provision the local license',
        valueHelp: 'persona:password',
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
      'Provisions a BFII license into the current Wine prefix.';

  @override
  String get name => 'provision_license';

  @override
  Future<int> run() async {
    final credentials = _resolveCredentials();
    if (credentials == null) {
      _logger.err(
        'credentials are required for license provisioning. '
        'Pass --credentials or set KYBER_BFII_HOST_CREDENTIALS.',
      );
      return ExitCode.usage.code;
    }

    final split = credentials.split(':');
    if (split.length != 2 || split.first.isEmpty || split.last.isEmpty) {
      _logger.err('Invalid credentials format. Use persona:password');
      return ExitCode.usage.code;
    }

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
      await startMaxima(dummyAuthStorage: true);
      await provisionGameLicense(
        gamePath: gamePath,
        user: split.first,
        pass: split.last,
        contentId: contentId,
      );
    } catch (e) {
      _logger.err('License provisioning failed: ${_formatProvisionError(e)}');
      return ExitCode.software.code;
    }

    _logger.success('License provisioned successfully for this Wine prefix.');
    return ExitCode.success.code;
  }

  String? _resolveCredentials() {
    final optionValue = argResults?['credentials'] as String?;
    if (optionValue != null && optionValue.trim().isNotEmpty) {
      return optionValue.trim();
    }

    for (final name in const [
      'KYBER_BFII_HOST_CREDENTIALS',
      'KYBER_DEDICATED_CREDENTIALS',
      'MAXIMA_CREDENTIALS',
    ]) {
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
