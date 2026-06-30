import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_cli/models/dedicated_server_session_config.dart';

final class DedicatedServerSessionConfigException implements Exception {
  const DedicatedServerSessionConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DedicatedServerSessionController {
  const DedicatedServerSessionController({
    required this.argResults,
    required this.environment,
    required this.defaultMap,
    required this.defaultMode,
  });

  final ArgResults argResults;
  final Map<String, String> environment;
  final String defaultMap;
  final String defaultMode;

  DedicatedServerSessionConfig resolve() {
    return DedicatedServerSessionConfig(
      mapRotation: _resolveMapRotation(),
      startupCommands: _resolveStartupCommands(),
    );
  }

  List<LevelSetup> _resolveMapRotation() {
    final hasRotationFile = argResults.wasParsed('rotation-file');
    final encodedRotation = environment['KYBER_MAP_ROTATION'];
    final hasEnvironmentRotation =
        encodedRotation != null && encodedRotation.trim().isNotEmpty;

    if (hasRotationFile && hasEnvironmentRotation) {
      throw const DedicatedServerSessionConfigException(
        'rotation-file conflicts with KYBER_MAP_ROTATION. Use one map '
        'rotation source.',
      );
    }

    if (hasRotationFile) {
      final path = _requiredOption('rotation-file');
      return _parseRotationLines(File(path).readAsLinesSync(), path);
    }

    if (hasEnvironmentRotation) {
      return _parseRotationLines(
        utf8.decode(base64.decode(encodedRotation)).split('\n'),
        'KYBER_MAP_ROTATION',
      );
    }

    if (defaultMap.isEmpty || defaultMode.isEmpty) {
      throw const DedicatedServerSessionConfigException(
        'map and mode are required when no map rotation is configured.',
      );
    }

    return [LevelSetup(map: defaultMap, mode: defaultMode)];
  }

  List<String> _resolveStartupCommands() {
    if (!argResults.wasParsed('startup-commands')) {
      return const [];
    }

    final path = _requiredOption('startup-commands');
    final file = File(path);
    if (!file.existsSync()) {
      throw DedicatedServerSessionConfigException(
        'startup-commands points to a missing file: $path',
      );
    }

    return file.readAsLinesSync();
  }

  List<LevelSetup> _parseRotationLines(List<String> lines, String source) {
    final rotation = <LevelSetup>[];
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      final split = line.split(';');
      if (split.length != 2 || split.first.isEmpty || split.last.isEmpty) {
        throw DedicatedServerSessionConfigException(
          'Invalid map rotation entry in $source: $rawLine',
        );
      }

      rotation.add(LevelSetup(map: split.last, mode: split.first));
    }

    if (rotation.isEmpty) {
      throw DedicatedServerSessionConfigException(
        'Map rotation source contains no playable entries: $source',
      );
    }

    return rotation;
  }

  String _requiredOption(String option) {
    final value = argResults[option] as String?;
    if (value == null || value.trim().isEmpty) {
      throw DedicatedServerSessionConfigException(
        '$option was provided but empty.',
      );
    }

    if (option.endsWith('file') || option == 'startup-commands') {
      final file = File(value);
      if (!file.existsSync()) {
        throw DedicatedServerSessionConfigException(
          '$option points to a missing file: $value',
        );
      }
    }

    return value.trim();
  }
}
