import 'dart:io';

import 'package:args/args.dart';
import 'package:kyber_cli/models/dedicated_server_launch_config.dart';

final class DedicatedServerConfigException implements Exception {
  const DedicatedServerConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DedicatedServerLaunchController {
  const DedicatedServerLaunchController({
    required this.argResults,
    required this.environment,
  });

  final ArgResults argResults;
  final Map<String, String> environment;

  DedicatedServerLaunchConfig resolve() {
    final onlineMode = _resolveOnlineMode();
    final hasRotation = _hasMapRotation();

    return DedicatedServerLaunchConfig(
      serverName: _requiredText('server-name', 'KYBER_SERVER_NAME'),
      gamePath: _requiredExistingFile('game-path', 'KYBER_GAME_PATH'),
      onlineMode: onlineMode,
      serverPort: _requiredPort('server-port', 'KYBER_SERVER_PORT'),
      maxPlayers: _requiredPositiveInt(
        'max-players',
        'KYBER_SERVER_MAX_PLAYERS',
      ),
      map: hasRotation
          ? _optionalText('map', 'KYBER_SERVER_MAP')
          : _requiredText('map', 'KYBER_SERVER_MAP'),
      mode: hasRotation
          ? _optionalText('mode', 'KYBER_SERVER_MODE')
          : _requiredText('mode', 'KYBER_SERVER_MODE'),
      modulePath: _requiredModuleDirectory('module-path', 'KYBER_MODULE_DIR'),
      gameArgs: _resolveGameArgs(),
    );
  }

  bool _hasMapRotation() {
    if (argResults.wasParsed('rotation-file')) {
      return true;
    }

    final value = environment['KYBER_MAP_ROTATION'];
    return value != null && value.trim().isNotEmpty;
  }

  bool _resolveOnlineMode() {
    final offlineFlag = argResults['offline'] as bool? ?? false;
    final envValue = environment['KYBER_ONLINE_MODE'];
    if (offlineFlag && envValue != null && envValue != '0') {
      throw const DedicatedServerConfigException(
        '--offline conflicts with KYBER_ONLINE_MODE. Use one explicit mode.',
      );
    }

    if (offlineFlag) {
      return false;
    }

    if (envValue == null || envValue.isEmpty || envValue == '1') {
      return true;
    }

    if (envValue == '0') {
      return false;
    }

    throw DedicatedServerConfigException(
      'KYBER_ONLINE_MODE must be either 1 or 0, got "$envValue".',
    );
  }

  String _requiredText(String option, String envName) {
    final value = _optionOrEnv(option, envName);
    if (value == null || value.trim().isEmpty) {
      throw DedicatedServerConfigException(
        '$option is required. Pass --$option or set $envName.',
      );
    }

    return value.trim();
  }

  String _optionalText(String option, String envName) {
    return _optionOrEnv(option, envName)?.trim() ?? '';
  }

  String _requiredExistingFile(String option, String envName) {
    final value = _requiredText(option, envName);
    if (!File(value).existsSync()) {
      throw DedicatedServerConfigException(
        '$option points to a missing file: $value',
      );
    }

    return value;
  }

  String _requiredExistingDirectory(String option, String envName) {
    final normalized = _requiredText(option, envName);
    if (!Directory(normalized).existsSync()) {
      throw DedicatedServerConfigException(
        '$option points to a missing directory: $normalized',
      );
    }

    return normalized;
  }

  String _requiredModuleDirectory(String option, String envName) {
    final normalized = _requiredExistingDirectory(option, envName);
    for (final fileName in const ['Kyber.dll', 'vivoxsdk.dll']) {
      final moduleFile = File('$normalized${Platform.pathSeparator}$fileName');
      if (!moduleFile.existsSync()) {
        throw DedicatedServerConfigException(
          '$option must contain $fileName: $normalized',
        );
      }
    }

    return normalized;
  }

  int _requiredPort(String option, String envName) {
    final value = _requiredPositiveInt(option, envName);
    if (value > 65535) {
      throw DedicatedServerConfigException(
        '$option must be between 1 and 65535, got $value.',
      );
    }

    return value;
  }

  int _requiredPositiveInt(String option, String envName) {
    final value = _requiredText(option, envName);
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      throw DedicatedServerConfigException(
        '$option must be a positive integer, got "$value".',
      );
    }

    return parsed;
  }

  String? _optionOrEnv(String option, String envName) {
    if (argResults.wasParsed(option)) {
      final optionValue = argResults[option] as String?;
      if (optionValue == null || optionValue.trim().isEmpty) {
        throw DedicatedServerConfigException('$option was provided but empty.');
      }

      return optionValue;
    }

    final envValue = environment[envName];
    if (envValue != null && envValue.trim().isNotEmpty) {
      return envValue;
    }

    return argResults[option] as String?;
  }

  List<String> _resolveGameArgs() {
    final values = argResults['game-args'];
    if (values is! List<String>) {
      return const [];
    }

    return List.unmodifiable(
      values.map((value) => value.trim()).where((value) => value.isNotEmpty),
    );
  }
}
