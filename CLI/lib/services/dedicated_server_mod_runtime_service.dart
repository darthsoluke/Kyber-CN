import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kyber_cli/command_runner.dart';
import 'package:kyber_cli/utils/services/level_declaration_service.dart';
import 'package:kyber_cli/utils/windows_env.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:mason_logger/mason_logger.dart';

final class DedicatedServerModRuntimeException implements Exception {
  const DedicatedServerModRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DedicatedServerModRuntimeService {
  const DedicatedServerModRuntimeService({required Logger logger})
    : _logger = logger;

  final Logger _logger;

  void apply({required List<FrostyMod> gameplayMods}) {
    _applyModLoaderState(gameplayMods);
    _registerLevelDeclarations(gameplayMods);
  }

  void _applyModLoaderState(List<FrostyMod> gameplayMods) {
    final override = Platform.environment['KYBER_DISABLE_MODLOADER'];
    if (override != null && override.isNotEmpty) {
      _logger.info(
        'KYBER_DISABLE_MODLOADER is set, leaving mod loader disabled',
      );
      return;
    }

    if (gameplayMods.isEmpty) {
      Env.set('KYBER_DISABLE_MODLOADER', '1');
      _logger.info(
        'No gameplay mods configured; disabling mod loader '
        'for BFII host-server startup',
      );
      return;
    }

    Env.delete('KYBER_DISABLE_MODLOADER');
  }

  void _registerLevelDeclarations(List<FrostyMod> gameplayMods) {
    final modEntries = <String, ModEntry>{};
    for (final mod in gameplayMods.where(
      (element) => element.customFrostyData != null,
    )) {
      modEntries[mod.filename.replaceAll(r'\', '/')] = ModEntry(
        _buildCustomMaps(mod),
        _buildCustomModes(mod),
        mod.customFrostyData!.modeMappings ?? {},
        mod.customFrostyData!.modeNameOverrides ?? {},
      );
    }

    sl
      ..registerSingleton<LevelDeclarationService>(LevelDeclarationService())
      ..get<LevelDeclarationService>().set(modEntries);
  }

  List<CustomMode> _buildCustomModes(FrostyMod mod) {
    return mod.customFrostyData!.modes.map((mode) {
      return CustomMode(
        mode.name,
        mode.id,
        mode.maxPlayers ?? -1,
        _decodeImage(mode.image, mod.filename),
      );
    }).toList();
  }

  List<CustomMap> _buildCustomMaps(FrostyMod mod) {
    return mod.customFrostyData!.maps.map((map) {
      return CustomMap(
        map.name,
        map.id,
        map.supportedModes ?? [],
        _decodeImage(map.image, mod.filename),
      );
    }).toList();
  }

  Uint8List _decodeImage(String image, String modFilename) {
    try {
      return base64.decode(image);
    } on FormatException catch (e) {
      throw DedicatedServerModRuntimeException(
        'Invalid custom map/mode image data in $modFilename: ${e.message}',
      );
    }
  }
}
