import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/module_version_service.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/core/services/windows_env.dart';
import 'package:kyber_launcher/features/frosty/dialogs/frosty_pack_selector_dialog.dart';
import 'package:kyber_launcher/features/game/dialogs/mod_limit_dialog.dart';
import 'package:kyber_launcher/features/kyber/services/kyber_grpc_service.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_start_game_dialog.dart';
import 'package:kyber_launcher/features/maxima/extensions/server_mod.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/features/maxima/services/maxima_instance_service.dart';
import 'package:kyber_launcher/features/mod_collections/providers/mod_collection_cubit.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/features/server_host/services/dedicated_host_user_config_service.dart';
import 'package:kyber_launcher/gen/rust/api/maxima.dart' as maxima;
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

class MaximaHelper {
  static final Logger _logger = Logger('maxima_helper');

  static bool _hasConfiguredMods(InitializeRequest? initializeRequest) {
    if (initializeRequest == null || !initializeRequest.hasModData()) {
      return false;
    }

    final modData = initializeRequest.modData;
    return modData.modPaths.isNotEmpty ||
        modData.mods.isNotEmpty ||
        modData.explodedMods.isNotEmpty;
  }

  static bool _usesOfflineDirectMode(InitializeRequest? initializeRequest) {
    if (initializeRequest == null) {
      return Platform.environment['KYBER_ONLINE_MODE'] == '0';
    }

    if (initializeRequest.hasStartServer() &&
        initializeRequest.startServer.hasOnlineMode()) {
      return !initializeRequest.startServer.onlineMode;
    }

    if (initializeRequest.hasJoinServer()) {
      final joinServer = initializeRequest.joinServer;
      return joinServer.joinToken.isEmpty && joinServer.id.startsWith('lan:');
    }

    return Platform.environment['KYBER_ONLINE_MODE'] == '0';
  }

  static bool _usesDedicatedServerMode(InitializeRequest? initializeRequest) {
    if (initializeRequest == null || !initializeRequest.hasStartServer()) {
      return false;
    }

    final startServer = initializeRequest.startServer;
    if (!startServer.hasOnlineMode()) {
      throw StateError(
        'StartServerRequest.onlineMode must be set before launcher dispatch.',
      );
    }

    return !startServer.onlineMode;
  }

  static Future<({String user, String pass})?>
  _resolveDedicatedCredentials() async {
    final credentials = await sl
        .get<DedicatedHostUserConfigService>()
        .readCredentials();
    if (credentials == null) {
      return null;
    }

    return (user: credentials.username, pass: credentials.password);
  }

  static Future<void> requestGameLaunch(
    BuildContext context, {
    ModCollectionMetaData? modCollection,
    bool showCollectionSelector = true,
    InitializeRequest? initializeRequest,
    bool requireSuccessfulLaunch = false,
  }) async {
    var selectedCollection = modCollection;
    if (selectedCollection == null && showCollectionSelector) {
      selectedCollection = await showKyberDialog<ModCollectionMetaData?>(
        context: context,
        builder: (_) => const FrostyPackSelectorDialog(),
      );

      if (selectedCollection == null) {
        _logger.fine('User cancelled selection. Aborting requestGameLaunch');
        return;
      }
    }

    initializeRequest ??= InitializeRequest();
    final offlineDirectMode = _usesOfflineDirectMode(initializeRequest);
    if (selectedCollection != null) {
      if (selectedCollection.getLocalMods().contains(null)) {
        NotificationService.error(
          message:
              'Some mods in your collection are missing. '
              'Please check your mod collection.',
        );
        return;
      }

      final modPaths = selectedCollection.getModPaths();
      final preloadedModCount =
          offlineDirectMode || !Preferences.general.enabledPreloadMods
          ? 0
          : (await sl.get<KyberGRPCService>().launcherClient.getPreloadedMods(
              Empty(),
            )).mods.length;
      final modLimit = Preferences.general.enabledPreloadMods
          ? 1739 - preloadedModCount
          : 1739;
      if (offlineDirectMode) {
        _logger.info(
          'LAN_STAGE[maxima.launch.preloaded_mods.skip] reason=offline_direct',
        );
      }
      if (modPaths.length >= modLimit) {
        _logger.warning('Mod limit reached: ${modPaths.length}');

        if (context.mounted) {
          await showKyberDialog(
            context: context,
            builder: (_) => const ModLimitDialog(),
          );
        }

        return;
      }

      initializeRequest.modData = ModData(
        basePath: ModService.getBasePath(),
        modPaths: modPaths,
        mods: selectedCollection
            .getLocalMods(onlyGameplay: true)
            .whereType<FrostyMod>()
            .map(ServerMod().fromFrostyMod)
            .toList(),
        explodedMods: selectedCollection
            .getLocalMods(
              onlyGameplay: true,
              expandCollections: true,
            )
            .whereType<FrostyMod>()
            .where((e) => !e.isCollection)
            .map(ServerMod().fromFrostyMod)
            .toList(),
      );
    }

    if (!context.mounted) {
      _logger.warning('Context is not mounted, aborting requestGameLaunch');
      return;
    }

    if (initializeRequest.startupCommands.isNotEmpty) {
      _logger.fine(
        'Starting game with startup commands: '
        '${initializeRequest.startupCommands}',
      );
    }

    if (!context.mounted) {
      _logger.warning('Context is not mounted, aborting requestGameLaunch');
      return;
    }

    final launchResult = await showKyberDialog<MaximaLaunchResult>(
      context: context,
      builder: (_) => MaximaStartGameDialog(
        initializeRequest: initializeRequest,
        mods: selectedCollection
            ?.getLocalMods()
            .whereType<FrostyMod>()
            .toList(),
      ),
    );
    if (requireSuccessfulLaunch && launchResult?.success != true) {
      throw StateError(
        launchResult?.message ?? 'BFII launch did not complete successfully.',
      );
    }
  }

  static Future<MaximaGameInstance> startGame({
    InitializeRequest? initializeRequest,
    String? gameSlug,
    String? gamePath,
    String? gameDataPath,
    List<FrostyMod>? mods,
  }) async {
    final path = Platform.environment['PATH'];

    if (path == null) {
      throw Exception('PATH environment variable is not set');
    }

    final moduleVersionService = ModuleVersionService();
    final requiresModSupport = _hasConfiguredMods(initializeRequest);
    final moduleDirectory = await moduleVersionService.getLaunchModuleDirectory(
      requireModSupport: requiresModSupport,
    );
    final grpcDebug = Preferences.debug.grpcDebugLogs;
    final moduleDebug = Preferences.debug.moduleDebugLogs;
    final newPath = '$path;$moduleDirectory';
    final interfacePort = await KyberNetworkHelper.findAvailablePort();
    final offlineDirectMode = _usesOfflineDirectMode(initializeRequest);
    final dedicatedServerMode = _usesDedicatedServerMode(initializeRequest);
    final dedicatedCredentials = dedicatedServerMode
        ? await _resolveDedicatedCredentials()
        : null;
    if (dedicatedServerMode && dedicatedCredentials == null) {
      throw StateError(
        'BFII host credentials are not configured. Open Settings > '
        'Accounts & Updates > BFII Dedicated Host and enter your own account.',
      );
    }

    await maxima.startMaxima(dummyAuthStorage: dedicatedServerMode);
    final instanceService = sl.get<MaximaInstanceService>();
    final runningInstance = instanceService.primaryInstance;
    if (runningInstance != null) {
      final runningRole = runningInstance.isDedicated
          ? 'BFII host server'
          : 'game client';
      final requestedRole = dedicatedServerMode
          ? 'BFII host server'
          : 'game client';
      throw StateError(
        'Battlefront II is already running as a $runningRole. '
        'This machine can only run one BFII process at a time; stop it before '
        'starting a $requestedRole. Run the BFII host server on another PC/VPS '
        'if this computer needs to join as a player.',
      );
    }

    final kyberService = sl.get<KyberGRPCService>();
    final offlineTokenSource =
        Platform.environment.containsKey(
          'KYBER_API_TOKEN',
        )
        ? 'environment'
        : kyberService.token != null
        ? 'existing_service'
        : 'placeholder';
    final kToken = offlineDirectMode
        ? Platform.environment['KYBER_API_TOKEN'] ??
              kyberService.token ??
              'offline-direct'
        : await kyberService.getAuthToken(await maxima.getAuthToken());
    if (!offlineDirectMode || kyberService.token == null) {
      kyberService.token = kToken;
    }
    final moduleVersion = await moduleVersionService.getRuntimeVersion(
      moduleDirectory: moduleDirectory,
    );
    ProcessEnv.set('KYBER_API_TOKEN', kToken);
    ProcessEnv.set('KYBER_ONLINE_MODE', offlineDirectMode ? '0' : '1');
    if (dedicatedServerMode) {
      ProcessEnv.set('KYBER_DEDICATED_SERVER', '1');
    } else {
      ProcessEnv.delete('KYBER_DEDICATED_SERVER');
    }
    ProcessEnv.set('KYBER_MODULE_VERSION', moduleVersion);
    ProcessEnv.set('KYBER_INTERFACE_PORT', interfacePort.toString());
    ProcessEnv.set(
      'KYBER_HTTP_HOSTNAME',
      kyberService.httpHostname,
    );
    ProcessEnv.set('PATH', newPath);
    ProcessEnv.set('KYBER_API_HOSTNAME', kyberService.moduleRpcTarget);
    ProcessEnv.set('KYBER_API_INSECURE', kyberService.isInsecure ? '1' : '0');
    ProcessEnv.set('KYBER_WS_SCHEME', kyberService.webSocketScheme);
    _logger.info(
      'LAN_STAGE[maxima.launch.mode] onlineMode=${!offlineDirectMode} '
      'offlineDirect=$offlineDirectMode '
      'dedicated=$dedicatedServerMode '
      'tokenSource=${offlineDirectMode ? offlineTokenSource : 'kyber_api'} '
      'interfacePort=$interfacePort '
      'rpcTarget=${kyberService.moduleRpcTarget} '
      'httpHost=${kyberService.httpHostname} '
      'insecure=${kyberService.isInsecure} '
      'wsScheme=${kyberService.webSocketScheme}',
    );

    if (_hasConfiguredMods(initializeRequest)) {
      ProcessEnv.delete('KYBER_DISABLE_MODLOADER');
    } else {
      ProcessEnv.set('KYBER_DISABLE_MODLOADER', '1');
    }

    if (grpcDebug) {
      ProcessEnv.set('GRPC_TRACE', 'all');
      ProcessEnv.set('GRPC_VERBOSITY', 'debug');
    } else {
      ProcessEnv.delete('GRPC_TRACE');
      ProcessEnv.delete('GRPC_VERBOSITY');
    }

    if (moduleDebug) {
      ProcessEnv.set('KYBER_LOG_LEVEL', 'debug');
    } else {
      ProcessEnv.delete('KYBER_LOG_LEVEL');
    }

    final gameClient = ClientGRPCService('127.0.0.1', interfacePort);
    final gamePID = await maxima
        .startGame(
          gameSlug: gameSlug ?? 'star-wars-battlefront-2',
          gamePathOverride: gamePath,
          user: dedicatedCredentials?.user,
          pass: dedicatedCredentials?.pass,
        )
        .timeout(
          const Duration(seconds: 90),
          onTimeout: () => throw TimeoutException(
            'Timed out waiting for Maxima to launch the BFII host process. '
            'No starwarsbattlefrontii.exe process was observed before timeout.',
          ),
        );
    _logger.info('Started game with PID: $gamePID');

    final serverMetadata =
        dedicatedServerMode && initializeRequest?.hasStartServer() == true
        ? ServerInstanceMetadata.fromStartRequest(
            initializeRequest!.startServer,
          )
        : null;

    final instance = dedicatedServerMode
        ? ServerInstance(
            pid: gamePID,
            clientService: gameClient,
            mods: mods ?? [],
            serverMetadata: serverMetadata,
          )
        : ClientInstance(
            pid: gamePID,
            clientService: gameClient,
            mods: mods ?? [],
          );

    try {
      sl.get<KyberGRPCServer>().setInitializeRequest(
        initializeRequest ?? InitializeRequest(),
      );
      if (dedicatedServerMode) {
        _logger.info(
          'LAN_STAGE[maxima.launch.dedicated.inject_immediate] pid=$gamePID',
        );
      } else {
        await maxima
            .lsxGetEventStream(pid: gamePID, isStartup: true)
            .firstWhere((e) => e == 'RequestLicense');
      }
      await maxima.injectKyber(
        pid: gamePID,
        path: p.join(moduleDirectory, 'Kyber.dll'),
      );
    } catch (e) {
      if (e is AnyhowException) {
        _logger.severe('Failed to inject Kyber into game: ${e.message}');
      }
      rethrow;
    }

    instanceService.addInstance(instance);

    return instance;
  }
}
