import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/features/map_rotation/models/map_rotation_entry.dart';
import 'package:kyber_launcher/features/maxima/helper/maxima_helper.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/features/maxima/services/maxima_instance_service.dart';
import 'package:kyber_launcher/features/mod_collections/providers/mod_collection_cubit.dart';
import 'package:kyber_launcher/features/mods/services/level_declaration_service.dart';
import 'package:kyber_launcher/features/server_host/models/host_start_progress_event.dart';
import 'package:kyber_launcher/features/server_host/services/external_dedicated_host_service.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';

class HostStartDraft {
  HostStartDraft({
    required this.name,
    required this.description,
    required this.password,
    required this.maxPlayers,
    required this.onlineMode,
    required this.port,
    required this.collection,
    required this.mapEntries,
    required this.friendlyFire,
    required this.healthRegeneration,
  });

  factory HostStartDraft.fromForm(
    Map<String, Object?> values, {
    required ModCollectionMetaData collection,
    required List<MapRotationEntry> mapEntries,
  }) {
    return HostStartDraft(
      name: values['serverName']! as String,
      description: values['description'] as String?,
      password: values['password'] as String?,
      maxPlayers: values['maxPlayers'] as int?,
      onlineMode: (values['onlineMode'] as bool?) ?? true,
      port: int.parse((values['serverPort']! as String).trim()),
      collection: collection,
      mapEntries: mapEntries,
      friendlyFire: (values['friendlyFire'] as bool?) ?? false,
      healthRegeneration: (values['healthRegeneration'] as bool?) ?? true,
    );
  }

  final String name;
  final String? description;
  final String? password;
  final int? maxPlayers;
  final bool onlineMode;
  final int port;
  final ModCollectionMetaData collection;
  final List<MapRotationEntry> mapEntries;
  final bool friendlyFire;
  final bool healthRegeneration;

  bool get passwordPresent => password?.isNotEmpty == true;
}

class HostStartRejectedException implements Exception {
  const HostStartRejectedException({
    this.messageKey,
    this.fallbackMessage,
    this.params = const {},
  });

  final String? messageKey;
  final String? fallbackMessage;
  final Map<String, Object?> params;

  @override
  String toString() => fallbackMessage ?? messageKey ?? super.toString();
}

class ServerHostStartService {
  ServerHostStartService({
    KyberGRPCService? kyber,
    LevelDeclarationService? levels,
    Logger? logger,
  }) : _kyber = kyber ?? sl.get<KyberGRPCService>(),
       _levels = levels ?? sl.get<LevelDeclarationService>(),
       _logger = logger ?? Logger('server_host_start');

  final KyberGRPCService _kyber;
  final LevelDeclarationService _levels;
  final Logger _logger;

  void validateDraft(
    HostStartDraft draft, {
    HostStartProgressSink? onProgress,
  }) {
    _emit(onProgress, 'host.progress.validateDraft');
    _logger.info(
      'LAN_STAGE[host.start.validate] '
      'onlineMode=${draft.onlineMode} requestedPort=${draft.port} '
      'maxPlayers=${draft.maxPlayers} '
      'passwordPresent=${draft.passwordPresent}',
    );

    if (draft.onlineMode && draft.port != 25200) {
      _logger.warning(
        'LAN_STAGE[host.start.rejected] '
        'reason=custom_port_online requestedPort=${draft.port}',
      );
      throw const HostStartRejectedException(
        messageKey: 'host.customPortOnlineUnsupported',
      );
    }

    if (draft.mapEntries.isEmpty) {
      _logger.warning(
        'LAN_STAGE[host.start.rejected] reason=empty_map_rotation',
      );
      throw const HostStartRejectedException(
        messageKey: 'host.mapRotationRequired',
      );
    }

    _emit(onProgress, 'host.progress.draftValidated');
  }

  Future<void> updateExistingServer({
    required String? serverId,
    required HostStartDraft draft,
    HostStartProgressSink? onProgress,
  }) async {
    if (serverId == null || serverId.isEmpty) {
      throw const HostStartRejectedException(
        fallbackMessage: 'No selected server id is available.',
      );
    }

    _emit(onProgress, 'host.progress.updateServer');
    _logger.info('LAN_STAGE[host.update.start] id=$serverId');
    await _kyber.serverBrowserClient.updateServer(
      UpdateServerRequest(
        id: serverId,
        name: draft.name,
        description: draft.description,
        password: draft.password,
      ),
    );
    _logger.info('LAN_STAGE[host.update.ok] id=$serverId');
    _emit(
      onProgress,
      'host.progress.updateCompleted',
      status: HostStartProgressStatus.success,
    );
  }

  Future<void> startNewServer(
    BuildContext context,
    HostStartDraft draft, {
    HostStartProgressSink? onProgress,
    bool validate = true,
  }) async {
    if (validate) {
      validateDraft(draft, onProgress: onProgress);
    }

    _emit(onProgress, 'host.progress.buildRequest');
    final startRequest = buildStartRequest(draft);
    _logger.info(
      'LAN_STAGE[host.start.request_built] '
      'onlineMode=${startRequest.onlineMode} '
      'requestedPort=${startRequest.port} '
      'mapRotation=${startRequest.mapRotation.length} '
      'passwordPresent=${startRequest.password.isNotEmpty}',
    );

    if (draft.onlineMode) {
      await _validateOfficialServer(startRequest, onProgress: onProgress);
    }

    _emit(onProgress, 'host.progress.buildStartupCommands');
    final startupCommands = buildStartupCommands(draft);

    if (!draft.onlineMode) {
      _emit(onProgress, 'host.progress.externalHostStart');
      await sl.get<ExternalDedicatedHostService>().start(
        serverName: draft.name,
        port: draft.port,
        maxPlayers: draft.maxPlayers ?? 2,
        password: draft.password,
        passwordPresent: draft.passwordPresent,
        collection: draft.collection,
        mapEntries: draft.mapEntries,
        startupCommands: startupCommands,
        onProgress: onProgress,
      );
      _emit(
        onProgress,
        'host.progress.serverStarted',
        status: HostStartProgressStatus.success,
      );
      return;
    }

    if (!context.mounted) {
      return;
    }
    await _dispatchStart(
      context,
      startRequest: startRequest,
      startupCommands: startupCommands,
      collection: draft.collection,
      onProgress: onProgress,
    );
    if (!draft.onlineMode) {
      await _confirmBfiiHostInstance(onProgress: onProgress);
    }
    _emit(
      onProgress,
      'host.progress.serverStarted',
      status: HostStartProgressStatus.success,
    );
  }

  StartServerRequest buildStartRequest(HostStartDraft draft) {
    return StartServerRequest(
      name: draft.name,
      description: draft.description,
      password: draft.password,
      maxPlayers: draft.maxPlayers,
      mapRotation: buildMapRotation(draft),
      onlineMode: draft.onlineMode,
      port: draft.port,
    );
  }

  List<LevelSetup> buildMapRotation(HostStartDraft draft) {
    return draft.mapEntries.map((entry) {
      return LevelSetup(
        map: entry.map,
        mode: entry.mode,
        mapName: _levels
            .getMapByMode(
              map: entry.map,
              mode: entry.mode,
              collection: draft.collection,
            )
            ?.name,
        modeName: _levels.getModeName(
          mode: entry.mode,
          collection: draft.collection,
        ),
      );
    }).toList();
  }

  List<String> buildStartupCommands(HostStartDraft draft) {
    return [
      if (draft.friendlyFire) 'SyncedGame.EnableFriendlyFire 1',
      if (!draft.healthRegeneration) 'SyncedGame.DisableRegenerateHealth 1',
    ];
  }

  Future<void> _validateOfficialServer(
    StartServerRequest request, {
    HostStartProgressSink? onProgress,
  }) async {
    _emit(onProgress, 'host.progress.officialValidate');
    _logger.info('LAN_STAGE[host.official.validate.start]');
    await _kyber.serverBrowserClient.validateServer(
      RegisterServerRequest(
        name: request.name,
        description: request.description,
        password: request.password,
        maxPlayerCount: request.maxPlayers,
        explodedMods: [],
        mods: [],
        levelSetup: LevelSetup(map: '', mode: ''),
        statsSource: .KYBER,
      ),
    );
    _logger.info('LAN_STAGE[host.official.validate.ok]');
    _emit(onProgress, 'host.progress.officialValidated');
  }

  Future<void> _dispatchStart(
    BuildContext context, {
    required StartServerRequest startRequest,
    required List<String> startupCommands,
    required ModCollectionMetaData collection,
    HostStartProgressSink? onProgress,
  }) async {
    final instanceService = sl.get<MaximaInstanceService>();
    if (!startRequest.onlineMode) {
      _emit(onProgress, 'host.progress.directDispatch');
      if (instanceService.bfiiHostInstance != null) {
        throw const HostStartRejectedException(
          fallbackMessage: 'A BFII host server is already running.',
        );
      }

      await _launchServerProcess(
        context,
        startRequest: startRequest,
        startupCommands: startupCommands,
        collection: collection,
        onProgress: onProgress,
      );
      return;
    }

    if (instanceService.clientInstance != null) {
      _emit(onProgress, 'host.progress.liveRpcDispatch');
      await _startViaLiveRpc(
        startRequest,
        startupCommands,
        collection,
        instanceService.clientInstance!,
        onProgress: onProgress,
      );
      return;
    }

    _emit(onProgress, 'host.progress.launchDispatch');
    await _launchServerProcess(
      context,
      startRequest: startRequest,
      startupCommands: startupCommands,
      collection: collection,
      onProgress: onProgress,
    );
  }

  Future<void> _launchServerProcess(
    BuildContext context, {
    required StartServerRequest startRequest,
    required List<String> startupCommands,
    required ModCollectionMetaData collection,
    HostStartProgressSink? onProgress,
  }) async {
    _emit(onProgress, 'host.progress.launchGameProcess');
    _logger.info(
      'LAN_STAGE[host.dispatch.launch_game] '
      'initialCommands=${startupCommands.length}',
    );
    if (!context.mounted) {
      return;
    }
    await MaximaHelper.requestGameLaunch(
      context,
      initializeRequest: InitializeRequest(
        startServer: startRequest,
        startupCommands: startupCommands,
      ),
      modCollection: collection,
      requireSuccessfulLaunch: true,
    );
  }

  Future<void> _startViaLiveRpc(
    StartServerRequest startRequest,
    List<String> startupCommands,
    ModCollectionMetaData collection,
    MaximaGameInstance instance, {
    HostStartProgressSink? onProgress,
  }) async {
    _emit(onProgress, 'host.progress.liveRpcStart');
    _logger.info(
      'LAN_STAGE[host.dispatch.live_rpc] '
      'initialCommands=${startupCommands.length}',
    );

    if (startupCommands.isNotEmpty) {
      throw const HostStartRejectedException(
        messageKey: 'host.initialCommandsRequireIdle',
      );
    }

    if (!_loadedGameplayModsMatch(instance, collection)) {
      _logger.warning(
        'LAN_STAGE[host.dispatch.live_rpc.blocked] '
        'reason=mod_collection_mismatch '
        'loadedMods=${_gameplayModKeys(instance.gameplayMods).join(',')} '
        'requestedMods=${_collectionGameplayModKeys(collection).join(',')}',
      );
      throw const HostStartRejectedException(
        messageKey: 'host.restartRequiredForModCollection',
      );
    }

    final client = instance.clientService;
    final state = await client.commonClient.getInfo(Empty());
    if (state.hasClient() || state.hasServer()) {
      _logger.info(
        'LAN_STAGE[host.dispatch.live_rpc.blocked] '
        'reason=already_running '
        'hasClient=${state.hasClient()} '
        'hasServer=${state.hasServer()}',
      );
      throw const HostStartRejectedException(
        fallbackMessage: 'Client or server is already running.',
      );
    }

    await client.serverClient.startServer(startRequest);
    _emit(onProgress, 'host.progress.liveRpcStarted');
  }

  bool _loadedGameplayModsMatch(
    MaximaGameInstance instance,
    ModCollectionMetaData collection,
  ) {
    return const ListEquality<String>().equals(
      _gameplayModKeys(instance.gameplayMods),
      _collectionGameplayModKeys(collection),
    );
  }

  List<String> _collectionGameplayModKeys(ModCollectionMetaData collection) {
    return _gameplayModKeys(
      collection.getLocalMods(onlyGameplay: true).whereType<FrostyMod>(),
    );
  }

  List<String> _gameplayModKeys(Iterable<FrostyMod> mods) {
    return mods
        .map((mod) {
          return '${mod.details.name}@${mod.details.version}';
        })
        .toList(growable: false);
  }

  Future<void> _confirmBfiiHostInstance({
    HostStartProgressSink? onProgress,
  }) async {
    _emit(onProgress, 'host.progress.confirmHostInstance');
    final instanceService = sl.get<MaximaInstanceService>();
    final deadline = DateTime.now().add(const Duration(seconds: 5));

    while (DateTime.now().isBefore(deadline)) {
      final instance = instanceService.bfiiHostInstance;
      if (instance != null && await _isProcessRunning(instance.pid)) {
        _emit(
          onProgress,
          'host.progress.hostInstanceConfirmed',
          params: {'pid': instance.pid},
        );
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    throw const HostStartRejectedException(
      messageKey: 'host.progress.hostInstanceMissing',
    );
  }

  Future<bool> _isProcessRunning(int pid) async {
    if (pid <= 0) {
      return false;
    }

    if (Platform.isWindows) {
      final command =
          r'$process = Get-Process -Id '
          '$pid'
          r' -ErrorAction SilentlyContinue; if ($process) { exit 0 } exit 1';
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        command,
      ]);
      return result.exitCode == 0;
    }

    final result = await Process.run('sh', ['-c', 'kill -0 $pid']);
    return result.exitCode == 0;
  }

  void _emit(
    HostStartProgressSink? onProgress,
    String messageKey, {
    HostStartProgressStatus status = HostStartProgressStatus.running,
    Map<String, Object?> params = const {},
  }) {
    onProgress?.call(
      HostStartProgressEvent(
        messageKey: messageKey,
        params: params,
        status: status,
      ),
    );
  }
}
