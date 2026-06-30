import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_cli/models/dedicated_server_mod_config.dart';
import 'package:kyber_cli/utils/collection_helper.dart';
import 'package:kyber_cli/utils/extensions/server_mod_extension.dart';
import 'package:kyber_cli/utils/mod_helper.dart';
import 'package:kyber_cli/utils/types/raw_mods.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:path/path.dart';

final class DedicatedServerModConfigException implements Exception {
  const DedicatedServerModConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DedicatedServerModController {
  const DedicatedServerModController({
    required this.argResults,
    required this.environment,
  });

  final ArgResults argResults;
  final Map<String, String> environment;

  Future<DedicatedServerModConfig> resolve() async {
    final modFolder = _optionalOptionOrEnv('mod-folder', 'KYBER_MOD_FOLDER');
    final collectionFile = _optionalOption('collection-file');
    final collectionModsDirectory = _optionalOption(
      'collection-mods-directory',
    );
    final rawMods = _optionalOption('raw-mods');

    _validateMutuallyExclusiveInputs(
      modFolder: modFolder,
      collectionFile: collectionFile,
      rawMods: rawMods,
    );

    if (modFolder != null) {
      return _fromModFolder(modFolder);
    }

    if (collectionFile != null) {
      if (collectionModsDirectory == null) {
        throw const DedicatedServerModConfigException(
          'collection-file requires collection-mods-directory.',
        );
      }

      return _fromCollectionFile(
        collectionFile: collectionFile,
        modsDirectory: collectionModsDirectory,
      );
    }

    if (collectionModsDirectory != null) {
      throw const DedicatedServerModConfigException(
        'collection-mods-directory requires collection-file.',
      );
    }

    if (rawMods != null) {
      return _fromRawMods(rawMods);
    }

    return const DedicatedServerModConfig(modData: null, gameplayMods: []);
  }

  void _validateMutuallyExclusiveInputs({
    required String? modFolder,
    required String? collectionFile,
    required String? rawMods,
  }) {
    if (modFolder != null && (collectionFile != null || rawMods != null)) {
      throw const DedicatedServerModConfigException(
        'mod-folder conflicts with collection-file and raw-mods. '
        'Use only one mod input source.',
      );
    }

    if (collectionFile != null && rawMods != null) {
      throw const DedicatedServerModConfigException(
        'collection-file conflicts with raw-mods. '
        'Use only one mod input source.',
      );
    }
  }

  Future<DedicatedServerModConfig> _fromModFolder(String modFolder) async {
    final dir = Directory(modFolder);
    if (!dir.existsSync()) {
      throw DedicatedServerModConfigException(
        'mod-folder points to a missing directory: $modFolder',
      );
    }

    final collectionFiles = dir
        .listSync()
        .whereType<File>()
        .where((file) => extension(file.path) == '.kbcollection')
        .toList(growable: false);
    if (collectionFiles.isEmpty) {
      throw DedicatedServerModConfigException(
        'mod-folder does not contain a .kbcollection file: $modFolder',
      );
    }

    if (collectionFiles.length > 1) {
      throw DedicatedServerModConfigException(
        'mod-folder contains multiple .kbcollection files: $modFolder',
      );
    }

    return _fromCollectionFile(
      collectionFile: collectionFiles.single.path,
      modsDirectory: modFolder,
    );
  }

  Future<DedicatedServerModConfig> _fromCollectionFile({
    required String collectionFile,
    required String modsDirectory,
  }) async {
    final file = File(collectionFile);
    if (!file.existsSync()) {
      throw DedicatedServerModConfigException(
        'collection-file points to a missing file: $collectionFile',
      );
    }

    final dir = Directory(modsDirectory);
    if (!dir.existsSync()) {
      throw DedicatedServerModConfigException(
        'collection-mods-directory points to a missing directory: '
        '$modsDirectory',
      );
    }

    final metaData = await ModCollection.readCollection(file);
    final collectionHelper = CollectionHelper();
    final modPaths = collectionHelper.getModsList(
      metaData,
      modDirectory: modsDirectory,
    );
    final frostyModPaths = collectionHelper
        .getModsList(metaData, listFrostyCollectionMods: false)
        .map((path) => join(modsDirectory, basename(path)))
        .toList(growable: false);

    _requireExistingModFiles(frostyModPaths, 'collection-file');

    final fbMods = ModHelper.readFrostyMods(frostyModPaths);
    _requireAllModsReadable(frostyModPaths, fbMods);
    _requireCollectionModsReadable(fbMods);

    final gameplayMods = ModHelper.filterGameplayMods(fbMods);
    return DedicatedServerModConfig(
      modData: ModData(
        basePath: _normalizeBasePathForServer(modsDirectory),
        modPaths: modPaths,
        mods: gameplayMods.map((mod) => mod.toServerMod()),
        explodedMods: ModHelper.expandMods(
          gameplayMods,
        ).map((mod) => mod.toServerMod()),
      ),
      gameplayMods: gameplayMods,
    );
  }

  DedicatedServerModConfig _fromRawMods(String rawModsPath) {
    final file = File(rawModsPath);
    if (!file.existsSync()) {
      throw DedicatedServerModConfigException(
        'raw-mods points to a missing file: $rawModsPath',
      );
    }

    final rawMods = RawMods.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
    if (rawMods.basePath.trim().isEmpty) {
      throw const DedicatedServerModConfigException(
        'raw-mods basePath must not be empty.',
      );
    }

    final dir = Directory(rawMods.basePath);
    if (!dir.existsSync()) {
      throw DedicatedServerModConfigException(
        'raw-mods basePath points to a missing directory: ${rawMods.basePath}',
      );
    }

    final frostyModPaths = rawMods.modPaths
        .map((path) => join(rawMods.basePath, path))
        .toList(growable: false);
    _requireExistingModFiles(frostyModPaths, 'raw-mods');

    final fbMods = ModHelper.readFrostyMods(frostyModPaths);
    _requireAllModsReadable(frostyModPaths, fbMods);
    _requireCollectionModsReadable(fbMods);

    final gameplayMods = ModHelper.filterGameplayMods(fbMods);
    return DedicatedServerModConfig(
      modData: ModData(
        basePath: rawMods.basePath,
        modPaths: rawMods.modPaths,
        mods: gameplayMods.map((mod) => mod.toServerMod()),
        explodedMods: ModHelper.expandMods(
          gameplayMods,
        ).map((mod) => mod.toServerMod()),
      ),
      gameplayMods: gameplayMods,
    );
  }

  void _requireExistingModFiles(List<String> paths, String source) {
    final missing = paths.where((path) => !File(path).existsSync()).toList();
    if (missing.isEmpty) {
      return;
    }

    throw DedicatedServerModConfigException(
      '$source references missing mod file(s): ${missing.join(', ')}',
    );
  }

  void _requireAllModsReadable(List<String> paths, List<FrostyMod> mods) {
    if (mods.length == paths.length) {
      return;
    }

    throw DedicatedServerModConfigException(
      'Failed to read one or more Frosty mod files: ${paths.join(', ')}',
    );
  }

  void _requireCollectionModsReadable(List<FrostyMod> mods) {
    final collectionModPaths = mods
        .where((mod) => mod.isCollection)
        .expand(ModHelper.getCollectionMods)
        .toList(growable: false);
    if (collectionModPaths.isEmpty) {
      return;
    }

    _requireExistingModFiles(collectionModPaths, 'frosty collection');

    final collectionMods = ModHelper.readFrostyMods(collectionModPaths);
    _requireAllModsReadable(collectionModPaths, collectionMods);
  }

  String _normalizeBasePathForServer(String path) {
    if (!Platform.isLinux) {
      return path;
    }

    return 'Z:${path.replaceAll('/', r'\')}';
  }

  String? _optionalOption(String option) {
    if (!argResults.wasParsed(option)) {
      return null;
    }

    final value = argResults[option] as String?;
    if (value == null || value.trim().isEmpty) {
      throw DedicatedServerModConfigException(
        '$option was provided but empty.',
      );
    }

    return value.trim();
  }

  String? _optionalOptionOrEnv(String option, String envName) {
    final optionValue = _optionalOption(option);
    if (optionValue != null) {
      return optionValue;
    }

    final envValue = environment[envName];
    if (envValue == null || envValue.trim().isEmpty) {
      return null;
    }

    return envValue.trim();
  }
}
