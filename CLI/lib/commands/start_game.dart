import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart' hide ProxyList;
import 'package:kyber_cli/command_runner.dart';
import 'package:kyber_cli/gen/api/maxima.dart';
import 'package:kyber_cli/models/maxima_instance.dart';
import 'package:kyber_cli/utils/collection_helper.dart';
import 'package:kyber_cli/utils/env_helper.dart';
import 'package:kyber_cli/utils/extensions/server_mod_extension.dart';
import 'package:kyber_cli/utils/kyber_grpc_server.dart';
import 'package:kyber_cli/utils/mod_helper.dart';
import 'package:kyber_cli/utils/proxy_helper.dart';
import 'package:kyber_cli/utils/services/level_declaration_service.dart';
import 'package:kyber_cli/utils/types/raw_mods.dart';
import 'package:kyber_cli/utils/windows_env.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart';

class StartGameCommand extends Command<int> {
  StartGameCommand({required Logger logger}) : _logger = logger {
    argParser
      ..addFlag('spectate', help: 'Starts the game in spectate mode')
      ..addOption(
        'credentials',
        abbr: 'c',
        help: 'Specify the credentials to use for EA login',
        valueHelp: 'persona:password',
      )
      ..addOption(
        'raw-mods',
        help: 'Specify a list of mods to use',
        valueHelp: 'path/to/mod_file.json',
      )
      ..addOption(
        'collection-file',
        help: 'Specify the Mod Collection file to use',
        valueHelp: 'path/to/collection.kmodcollection',
      )
      ..addOption('server-id', help: 'Specify the server id to connect to')
      ..addOption(
        'server-address',
        help:
            'Specify a direct-connect server address. '
            'This bypasses Kyber server lookup and join tokens.',
        valueHelp: 'ip-or-hostname',
      )
      ..addOption(
        'server-port',
        defaultsTo: '25200',
        help: 'Specify the direct-connect server port',
      )
      ..addOption(
        'server-password',
        help: 'Specify the direct-connect server password',
      )
      ..addOption('proxy-id', help: 'Specify the proxy id to use')
      ..addOption('token', abbr: 't')
      ..addOption('game-path', help: 'Specify the game path')
      ..addMultiOption(
        'game-args',
        help: 'Specify the game arguments',
        valueHelp: '[arg1, arg2, ...]',
      )
      ..addOption(
        'game-data-path',
        help: 'Specify the game data path',
        valueHelp: 'path',
        callback: (p0) => p0 is String ? Directory(p0) : null,
      )
      ..addOption(
        'module-branch',
        help: 'Specify the branch to use for the Kyber module',
        valueHelp: 'branch',
      )
      ..addOption(
        'module-path',
        help: 'Specify a custom directory to use for the Kyber module',
        valueHelp: 'path/to/module',
      )
      ..addFlag('show-console', help: 'Shows the Kyber console window')
      ..addOption('interface-port', valueHelp: '9000');
  }

  static const int _defaultServerPort = 25200;

  @override
  String get description => '''Starts Battlefront and injects Kyber''';

  @override
  String get name => 'start_game';

  final Logger _logger;

  @override
  Future<int> run() async {
    final service = sl.get<KyberGRPCService>();
    final modulePath = argResults?['module-path'] as String?;
    EnvHelper.setPath(modulePath);
    final moduleDir = modulePath ?? FileHelper.getModuleDirectory().path;
    final serverId = (argResults?['server-id'] as String?)?.trim();
    final serverAddress = (argResults?['server-address'] as String?)?.trim();
    final hasServerId = serverId?.isNotEmpty ?? false;
    final hasServerAddress = serverAddress?.isNotEmpty ?? false;
    if (hasServerId && hasServerAddress) {
      _logger.err('server-id and server-address are mutually exclusive');
      return ExitCode.usage.code;
    }

    final directConnect = hasServerAddress;
    final onlineMode =
        !directConnect &&
        (Platform.environment['KYBER_ONLINE_MODE'] ?? '1') != '0';
    Env.set('KYBER_ONLINE_MODE', onlineMode ? '1' : '0');
    final showConsole = argResults?['show-console'] as bool? ?? false;
    if (showConsole) {
      Env.delete('KYBER_HIDE_CONSOLE');
    } else {
      Env.set('KYBER_HIDE_CONSOLE', '1');
    }
    _logger
      ..info(
        'LAN_STAGE[cli.start_game.mode] onlineMode=$onlineMode '
        'directConnect=$directConnect serverId=${serverId ?? ''} '
        'serverAddress=${serverAddress ?? ''}',
      )
      ..info('Starting login flow...');
    late ServicePlayer player;
    try {
      var loginCredentials = argResults?['credentials'] as String?;
      if (loginCredentials != null && loginCredentials.startsWith('=')) {
        loginCredentials = loginCredentials.substring(1);
      }

      player = await loginFlow(loginOverride: loginCredentials);
    } catch (e) {
      if (e is PanicException || e is AnyhowException) {
        final err = e is PanicException
            ? e.message
            : (e as AnyhowException).message;
        if (err.contains('unknown variant `NO_SUCH_USER`')) {
          _logger.err('Login failed: The specified user does not exist');
        } else {
          _logger.err('Login failed: $err');
        }
        return ExitCode.usage.code;
      }

      _logger.err('Login failed: $e');
      return ExitCode.usage.code;
    }

    _logger
      ..success('Logged in as ${player.displayName}.')
      ..info(
        onlineMode
            ? 'Fetching Maxima auth token...'
            : 'Skipping Kyber auth token fetch for offline/direct mode...',
      );

    if (!onlineMode) {
      final kToken =
          (argResults?['token'] as String?) ??
          Platform.environment['KYBER_API_TOKEN'] ??
          'offline-direct';
      service.token = kToken;
      Env.set('KYBER_API_TOKEN', kToken);
      _logger.info(
        'LAN_STAGE[cli.start_game.auth.skip] reason=offline_direct '
        'tokenSource=${_offlineTokenSource()}',
      );
    } else if (argResults?['token'] != null) {
      final kToken = argResults?['token'] as String;
      service.token = kToken;
      Env.set('KYBER_API_TOKEN', kToken);
      _logger.info('LAN_STAGE[cli.start_game.auth.argument]');
    } else {
      final authToken = await getAuthToken();

      _logger.info('Fetching Kyber auth token...');
      try {
        final kToken = await service.getAuthToken(authToken);
        Env.set('KYBER_API_TOKEN', kToken);
      } catch (e) {
        if (e is GrpcError) {
          if (e.code == StatusCode.unauthenticated ||
              e.code == StatusCode.permissionDenied) {
            _logger.err('Kyber Login Error: ${e.message}');
          } else {
            _logger.err('Failed to fetch Kyber auth token: ${e.message}');
          }

          return ExitCode.usage.code;
        }
      }

      _logger.success('Kyber auth token fetched');
    }

    final rawModsPath = argResults?['raw-mods'] as String?;
    File? collectionFile;
    if (argResults?['collection-file'] != null) {
      collectionFile = File(argResults?['collection-file'] as String);
      if (!collectionFile.existsSync()) {
        _logger.err('Collection file does not exist');
        return ExitCode.usage.code;
      }

      await CollectionHelper().useCollection(collectionFile);
    }

    Server? server;
    if (hasServerId) {
      try {
        _logger.info('Joining server with id: $serverId');
        server = await service.serverBrowserClient.getServer(
          ServerRequest(id: serverId),
        );

        final currentIp = await KyberNetworkHelper.getCurrentIpAddress();
        if (server.ip == currentIp) {
          server.ip = '127.0.0.1';
        }
      } catch (e) {
        if (e is GrpcError) {
          if (e.code == StatusCode.notFound) {
            _logger.err('Server with id "$serverId" not found');
          } else {
            _logger.err('Failed to fetch server: ${e.message}');
          }
        }
      }
    }

    JoinServerRequest? joinServerByIP;
    if (directConnect) {
      final address = serverAddress!;
      final serverPort = int.tryParse(
        (argResults?['server-port'] as String?)?.trim() ?? '',
      );
      if (serverPort == null || serverPort <= 0 || serverPort > 65535) {
        _logger.err('server-port must be between 1 and 65535');
        return ExitCode.usage.code;
      }

      final password =
          (argResults?['server-password'] as String?) ??
          Platform.environment['KYBER_SERVER_PASSWORD'] ??
          '';
      joinServerByIP = JoinServerRequest(
        id: 'lan:$address:$serverPort',
        ip: address,
        port: serverPort,
        spectate: argResults?['spectate'] as bool? ?? false,
        type: JoinServerType.DIRECT,
        joinToken: '',
        password: password,
      );
      _logger.info(
        'LAN_STAGE[cli.start_game.direct_join.request] '
        'id=${joinServerByIP.id} '
        'ip=${joinServerByIP.ip}:${joinServerByIP.port} '
        'passwordPresent=${joinServerByIP.password.isNotEmpty} '
        'spectate=${joinServerByIP.spectate}',
      );
    } else if (server != null) {
      KyberProxy? proxy;
      if (server.requiresProxy) {
        final proxyId = argResults?['proxy-id'] as String?;
        if (proxyId != null) {
          final proxies = await ProxyHelper.getProxies();
          final tmpProxy = proxies
              .where((x) => x.proxyInfo.id == proxyId)
              .firstOrNull;
          if (tmpProxy == null) {
            _logger.err('Proxy with id $proxyId not found');
            return ExitCode.usage.code;
          }

          proxy = tmpProxy;
        } else {
          proxy = await ProxyHelper.getOptimalProxy();
        }
      }

      final tokenResp = await service.clientServerClient.createJoinToken(
        .new(
          server: server.id,
          password: Platform.environment['KYBER_SERVER_PASSWORD'],
        ),
      );

      joinServerByIP = JoinServerRequest(
        id: server.id,
        ip: server.requiresProxy ? proxy!.proxyInfo.ip : server.ip,
        port: server.requiresProxy ? _defaultServerPort : server.port,
        spectate: argResults?['spectate'] as bool? ?? false,
        type: server.requiresProxy
            ? JoinServerType.PROXIED
            : JoinServerType.DIRECT,
        joinToken: tokenResp.token,
      );
    }

    final kyberPort =
        argResults?['interface-port'] as String? ??
        (await KyberNetworkHelper.findAvailablePort()).toString();
    Env.set('KYBER_INTERFACE_PORT', kyberPort);
    Env.set('KYBER_API_HOSTNAME', service.moduleRpcTarget);
    Env.set('KYBER_HTTP_HOSTNAME', service.httpHostname);
    Env.set('KYBER_API_INSECURE', service.isInsecure ? '1' : '0');
    Env.set('KYBER_WS_SCHEME', service.webSocketScheme);
    _logger.info(
      'LAN_STAGE[cli.start_game.api_target] '
      'rpcTarget=${service.moduleRpcTarget} httpHost=${service.httpHostname} '
      'insecure=${service.isInsecure} wsScheme=${service.webSocketScheme}',
    );

    ModData? modData;
    var gameplayMods = <FrostyMod>[];
    if (collectionFile != null) {
      final metaData = await ModCollection.readCollection(collectionFile);
      final dir = CollectionHelper().getModsDirectory();
      final mods = CollectionHelper().getModsList(metaData);
      final fbMods = ModHelper.readFrostyMods(
        mods.map((e) => join(dir, e)).toList(),
      );

      gameplayMods = ModHelper.filterGameplayMods(fbMods);

      modData = ModData(
        basePath: normalize(dir),
        modPaths: mods,
        mods: gameplayMods.map((e) => e.toServerMod()),
        explodedMods: ModHelper.expandMods(
          gameplayMods,
        ).map((e) => e.toServerMod()),
      );
    } else if (rawModsPath != null) {
      final rawModsFile = File(rawModsPath);
      if (!rawModsFile.existsSync()) {
        _logger.err('The specified raw-mods file does not exist');
        return ExitCode.usage.code;
      }

      final data = rawModsFile.readAsStringSync();
      final rawMods = RawMods.fromJson(
        jsonDecode(data) as Map<String, dynamic>,
      );
      final fbMods = ModHelper.readFrostyMods(
        rawMods.modPaths.map((e) => join(rawMods.basePath, e)).toList(),
      );

      gameplayMods = ModHelper.filterGameplayMods(fbMods);

      modData = ModData(
        basePath: rawMods.basePath,
        modPaths: rawMods.modPaths,
        mods: gameplayMods.map((e) => e.toServerMod()),
        explodedMods: ModHelper.expandMods(
          gameplayMods,
        ).map((e) => e.toServerMod()),
      );
    }

    final modEntries = <String, ModEntry>{};
    for (final mod in gameplayMods.where(
      (element) =>
          kRequiredCategories.contains(
            element.details.category.toLowerCase(),
          ) &&
          element.customFrostyData != null,
    )) {
      final modes = mod.customFrostyData!.modes
          .map(
            (e) => CustomMode(
              e.name,
              e.id,
              e.maxPlayers ?? -1,
              base64.decode(e.image),
            ),
          )
          .toList();
      final maps = mod.customFrostyData!.maps
          .map(
            (e) => CustomMap(
              e.name,
              e.id,
              e.supportedModes ?? [],
              base64.decode(e.image),
            ),
          )
          .toList();

      modEntries[mod.filename] = ModEntry(
        maps,
        modes,
        mod.customFrostyData!.modeMappings ?? {},
        mod.customFrostyData!.modeNameOverrides ?? {},
      );
    }

    sl
      ..registerSingleton<LevelDeclarationService>(LevelDeclarationService())
      ..get<LevelDeclarationService>().set(modEntries);

    final grpcServer = KyberGRPCServer();
    await grpcServer.start();
    grpcServer.setInitializeRequest(
      InitializeRequest(joinServer: joinServerByIP, modData: modData),
    );

    _logger.info('Kyber will listen on port $kyberPort');
    final gameArgs =
        (argResults?['game-args'] as List<String>? ?? const <String>[])
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
    final pid = await startGame(
      gameSlug: 'star-wars-battlefront-2',
      gamePathOverride: argResults?['game-path'] as String?,
      gameArgs: gameArgs,
    );

    final moduleFile = join(moduleDir, 'Kyber.dll');
    _logger.info('Injecting Kyber from $moduleFile...');
    await injectKyber(pid: pid, path: moduleFile);

    sl.registerSingleton<MaximaGameInstance>(
      MaximaGameInstance(
        pid: pid,
        isDedicated: false,
        clientService: ClientGRPCService('', 0),
        mods: gameplayMods,
      ),
    );

    _logger.info('Waiting for Kyber (PID: $pid)');
    final completion = Completer<void>();
    lsxGetEventStream(pid: pid).listen(
      (event) async {
        if (event != 'RequestLicense') {
          return;
        }

        _logger.success('Kyber started');
      },
      onDone: completion.complete,
      onError: completion.complete,
    );

    try {
      await completion.future;
    } catch (e) {
      _logger.err('Error: $e');
    }

    return ExitCode.success.code;
  }

  String _offlineTokenSource() {
    if (argResults?['token'] != null) {
      return 'argument';
    }

    if (Platform.environment.containsKey('KYBER_API_TOKEN')) {
      return 'environment';
    }

    return 'placeholder';
  }
}
