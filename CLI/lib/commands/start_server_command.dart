import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_cli/bfii_host/bfii_host_server.dart';
import 'package:kyber_cli/command_runner.dart';
import 'package:kyber_cli/gen/api/maxima.dart';
import 'package:kyber_cli/utils/env_helper.dart';
import 'package:kyber_cli/utils/kyber_grpc_server.dart';
import 'package:kyber_cli/utils/windows_env.dart';
import 'package:mason_logger/mason_logger.dart';

const _denuvoLogPrefix = 'Got Denuvo Token: ';
const _bfiiContentId = '1035052';

class StartServerCommand extends Command<int> {
  StartServerCommand({required Logger logger, required this.logStream})
    : _logger = logger {
    argParser
      ..addFlag('show-console', help: 'Shows the Kyber console window.')
      ..addFlag(
        'offline',
        help:
            'Starts without Kyber server registration/proxy/join-token auth. '
            'Use this for LAN or direct public-IP hosting.',
        negatable: false,
      )
      ..addSeparator('Server Options')
      ..addOption('server-name', abbr: 'n', help: 'Specify the server name')
      ..addOption(
        'server-password',
        abbr: 'p',
        help: 'Specify the server password',
      )
      ..addOption('server-description', help: 'Specify the server description')
      ..addOption('server-port', help: 'Specify the server listen port')
      ..addOption('max-players', help: 'Specify the maximum number of players')
      ..addOption('mode', help: 'Specify the mode')
      ..addOption('map', help: 'Specify the map')
      ..addOption('rotation-file', help: 'Specify the rotation file to use')
      ..addOption(
        'startup-commands',
        help: 'Specify a text file with startup commands',
        valueHelp: 'path/to/commands.txt',
      )
      ..addSeparator('Game Options')
      ..addOption(
        'collection-file',
        help: 'Specify the Mod Collection file to use',
        valueHelp: 'path/to/collection.kmodcollection',
      )
      ..addOption(
        'collection-mods-directory',
        help: 'Specify the directory to use for the collection mods',
        valueHelp: 'path/to/mods',
      )
      ..addOption(
        'raw-mods',
        help: 'Specify a list of mods to use',
        valueHelp: 'path/to/mod_file.json',
      )
      ..addOption(
        'mod-folder',
        help:
            'Specify a directory that contains a collection file '
            'and all required mods',
        valueHelp: 'path/to/dir',
      )
      ..addOption(
        'game-path',
        help: 'Specify the Battlefront II executable path',
      )
      ..addMultiOption(
        'game-args',
        help: 'Specify the game arguments',
        valueHelp: '[arg1, arg2, ...]',
      )
      ..addSeparator('Maxima Options')
      ..addOption(
        'credentials',
        abbr: 'c',
        help:
            'Unsupported in shipping builds. Use the normal EA/Maxima OAuth '
            'session instead.',
        valueHelp: 'access-token',
      )
      ..addOption(
        'license-mode',
        allowed: const ['reuse', 'refresh'],
        help:
            'Controls BFII license provisioning. reuse keeps valid cached '
            'licenses; refresh forces Maxima to request a new EA license.',
      )
      ..addOption(
        'denuvo-token',
        help:
            'Optional explicit Denuvo token override. Prefer --license-mode '
            'refresh unless you know the token is current for this machine.',
      )
      ..addFlag(
        'credentialless-host',
        help:
            'Start an offline/direct BFII host without EA/Maxima credentials. '
            'Requires an already provisioned BFII/Wine runtime state.',
        negatable: false,
      )
      ..addOption('token', help: 'Specify the Kyber auth token')
      ..addOption(
        'module-path',
        help:
            'Specify a custom directory containing Kyber.dll '
            'for BFII injection',
        valueHelp: 'path/to/module',
      )
      ..addOption(
        'module-branch',
        help: 'Specify the branch to use for the Kyber module',
        valueHelp: 'branch',
      )
      ..addOption('offer-id', help: 'Specify the offer ID')
      ..addOption('interface-port', valueHelp: '9000');
  }

  @override
  String get description =>
      '''Starts a BFII host-server process with the given options''';

  @override
  String get name => 'start_server';

  final Logger _logger;
  final Stream<LogEntry> logStream;

  @override
  Future<int> run() async {
    final allowDedicated = Platform
        .environment['KYBER_BYPASS_DOCKER_I_REALLY_KNOW_WHAT_I_AM_DOING'];
    if (allowDedicated == null || allowDedicated.isEmpty) {
      _logger.info(
        'To host BFII host servers, please use the Kyber server image. This path still launches Battlefront II; it is not a standalone backend. For more information, visit https://docs.kyber.gg',
      );
      return ExitCode.usage.code;
    }

    final launchConfig = switch (argResults) {
      final results? => () {
        try {
          return BfiiHostLaunchController(
            argResults: results,
            environment: Platform.environment,
          ).resolve();
        } on BfiiHostConfigException catch (e) {
          _logger.err(e.message);
          return null;
        }
      }(),
      _ => null,
    };
    if (launchConfig == null) {
      return ExitCode.usage.code;
    }

    EnvHelper.setPath(launchConfig.modulePath);

    final onlineMode = launchConfig.onlineMode;
    final credentials = _resolveCredentials();
    late final bool credentiallessHost;
    try {
      credentiallessHost = _resolveCredentiallessHost(
        onlineMode: onlineMode,
        credentials: credentials,
      );
    } on BfiiHostConfigException catch (e) {
      _logger.err(e.message);
      return ExitCode.usage.code;
    }
    if (credentials != null) {
      _logger.err(
        'Direct EA/Maxima password login is not supported by this build. '
        'Sign in through the normal EA/Maxima OAuth flow once, then start the '
        'BFII host server without KYBER_DEDICATED_CREDENTIALS.',
      );
      return ExitCode.usage.code;
    }

    Env.set('KYBER_ONLINE_MODE', onlineMode ? '1' : '0');
    Env.set('KYBER_CREDENTIALLESS_HOST', credentiallessHost ? '1' : '0');
    _logger
      ..info(
        'LAN_STAGE[cli.start_server.mode] onlineMode=$onlineMode '
        'offlineFlag=${argResults?['offline'] as bool? ?? false} '
        'credentiallessHost=$credentiallessHost',
      )
      ..info('Starting Maxima runtime...');

    try {
      await startMaxima(dummyAuthStorage: credentiallessHost);
    } catch (e) {
      _logger.err('Failed to start Maxima runtime: $e');
      return ExitCode.software.code;
    }

    _logger.info(
      credentiallessHost
          ? 'Resolving credentialless offline host identity...'
          : credentials != null
          ? 'Logging in with dedicated Maxima credentials...'
          : 'Starting login flow...',
    );

    late final BfiiHostAuthContext authContext;
    try {
      authContext = await BfiiHostAuthService(logger: _logger).resolve(
        onlineMode: onlineMode,
        credentials: credentials,
        explicitKyberToken: argResults?['token'] as String?,
        credentiallessHost: credentiallessHost,
      );
    } on BfiiHostAuthException catch (e) {
      _logger.err(e.message);
      return ExitCode.usage.code;
    }

    _logger
      ..success(
        credentiallessHost
            ? 'Using credentialless host identity ${authContext.playerName}.'
            : credentials != null
            ? 'Logged in dedicated host as ${authContext.playerName}.'
            : 'Logged in as ${authContext.playerName}.',
      )
      ..info('Starting BFII host-server process...');

    late final _BfiiLicenseMode licenseMode;
    late final String? denuvoTokenOverride;
    try {
      licenseMode = _resolveLicenseMode();
      denuvoTokenOverride = _resolveDenuvoTokenOverride();
      _configureLicenseEnvironment(
        mode: licenseMode,
        denuvoTokenOverride: denuvoTokenOverride,
      );
    } on BfiiHostConfigException catch (e) {
      _logger.err(e.message);
      return ExitCode.usage.code;
    }

    final results = argResults;
    if (results == null) {
      return ExitCode.usage.code;
    }

    late final BfiiHostSessionConfig sessionConfig;
    try {
      sessionConfig = BfiiHostSessionController(
        argResults: results,
        environment: Platform.environment,
        defaultMap: launchConfig.map,
        defaultMode: launchConfig.mode,
      ).resolve();
    } on BfiiHostSessionConfigException catch (e) {
      _logger.err(e.message);
      return ExitCode.usage.code;
    }
    _logger.info(
      'Loaded map rotation with ${sessionConfig.mapRotation.length} entries',
    );

    sl.get<KyberGRPCService>().token = authContext.kyberToken;

    final licenseService = switch (Platform.environment) {
      final environment => () {
        try {
          return BfiiHostLicenseService(
            config: BfiiHostLicenseConfig.fromEnvironment(environment),
            logger: _logger,
          );
        } on BfiiHostLicenseException catch (e) {
          _logger.err(e.message);
          return null;
        }
      }(),
    };
    if (licenseService == null) {
      return ExitCode.usage.code;
    }

    if (denuvoTokenOverride == null && licenseMode == _BfiiLicenseMode.reuse) {
      try {
        final existingToken = await licenseService.fetch(
          id: authContext.denuvoId,
        );
        if (existingToken != null) {
          _logger.info('Found existing Denuvo token, using it...');
          Env.set('MAXIMA_DENUVO_TOKEN', existingToken);
        }
      } on BfiiHostLicenseException catch (e) {
        _logger.err(e.message);
        return ExitCode.usage.code;
      }
    } else if (denuvoTokenOverride != null) {
      _logger.info('Using user-provided Denuvo token override.');
    } else {
      _logger.info(
        'Skipping cached Denuvo token because license-mode=refresh.',
      );
    }

    final showConsole = argResults?['show-console'] as bool? ?? false;
    if (showConsole) {
      Env.delete('KYBER_HIDE_CONSOLE');
    } else {
      Env.set('KYBER_HIDE_CONSOLE', '1');
    }

    Env.set('KYBER_API_TOKEN', authContext.kyberToken);

    Env.set('KYBER_DEDICATED_SERVER', '1');

    final kyberPort =
        argResults?['interface-port'] as String? ??
        (await KyberNetworkHelper.findAvailablePort()).toString();
    final kyberService = sl.get<KyberGRPCService>();
    Env.set('KYBER_INTERFACE_PORT', kyberPort);
    Env.set('KYBER_API_HOSTNAME', kyberService.moduleRpcTarget);
    Env.set('KYBER_HTTP_HOSTNAME', kyberService.httpHostname);
    Env.set('KYBER_API_INSECURE', kyberService.isInsecure ? '1' : '0');
    Env.set('KYBER_WS_SCHEME', kyberService.webSocketScheme);
    _logger.info(
      'LAN_STAGE[cli.start_server.api_target] '
      'rpcTarget=${kyberService.moduleRpcTarget} '
      'httpHost=${kyberService.httpHostname} '
      'insecure=${kyberService.isInsecure} '
      'wsScheme=${kyberService.webSocketScheme}',
    );

    try {
      _cleanInvalidLocalBfiiLicenseFiles(contentId: _bfiiContentId);
    } on BfiiHostConfigException catch (e) {
      _logger.err(e.message);
      return ExitCode.usage.code;
    }

    if (licenseMode == _BfiiLicenseMode.reuse) {
      try {
        await licenseService.fetch(
          id: authContext.licenseId,
          writeLicenseFile: true,
        );
      } on BfiiHostLicenseException catch (e) {
        _logger.err(e.message);
        return ExitCode.usage.code;
      }
    } else {
      _logger.info(
        'Skipping synced BFII license file because license-mode=refresh; '
        'Maxima will request a fresh license.',
      );
    }

    logStream.listen((event) {
      switch (event.msg) {
        case final String msg when event.msg.startsWith(_denuvoLogPrefix):
          final token = msg.substring(_denuvoLogPrefix.length);
          unawaited(
            licenseService
                .upload(id: authContext.denuvoId, data: token)
                .catchError((Object e) {
                  _logger.err('License upload failed: $e');
                }),
          );
      }
    });

    late final BfiiHostModConfig resolvedModConfig;
    try {
      resolvedModConfig = await BfiiHostModController(
        argResults: results,
        environment: Platform.environment,
      ).resolve();
    } on BfiiHostModConfigException catch (e) {
      _logger.err(e.message);
      return ExitCode.usage.code;
    }

    final modData = resolvedModConfig.modData;
    final gameplayMods = resolvedModConfig.gameplayMods;

    try {
      BfiiHostModRuntimeService(
        logger: _logger,
      ).apply(gameplayMods: gameplayMods);
    } on BfiiHostModRuntimeException catch (e) {
      _logger.err(e.message);
      return ExitCode.usage.code;
    }

    _logger.info('Kyber is listening on port $kyberPort');

    final server = KyberGRPCServer();
    await server.start();

    final serverPort = launchConfig.serverPort;

    if (onlineMode && serverPort != 25200) {
      _logger.warn(
        'Custom server ports are only fully supported in direct BFII host '
        'mode. '
        'Kyber online registration still assumes port 25200.',
      );
    }

    server.setInitializeRequest(
      InitializeRequest(
        modData: modData,
        startupCommands: sessionConfig.startupCommands,
        startServer: StartServerRequest(
          password:
              (Platform.environment['KYBER_SERVER_PASSWORD'] ??
                      argResults?['server-password'])
                  as String?,
          description:
              (Platform.environment['KYBER_SERVER_DESCRIPTION'] ??
                      argResults?['server-description'])
                  as String?,
          mapRotation: sessionConfig.mapRotation,
          maxPlayers: launchConfig.maxPlayers,
          onlineMode: onlineMode,
          port: serverPort,
          name: launchConfig.serverName,
        ),
      ),
    );

    late final int pid;
    try {
      pid = await BfiiHostRuntimeService(logger: _logger).start(
        gamePath: launchConfig.gamePath,
        modulePath: launchConfig.modulePath,
        interfacePort: int.parse(kyberPort),
        serverPort: serverPort,
        gameplayMods: gameplayMods,
        gameArgs: launchConfig.gameArgs,
        // Credentials are consumed by loginFlow above. BFII must launch through
        // the normal Maxima offer path, not OnlineOffline(contentId).
        credentials: null,
      );
    } on BfiiHostRuntimeException catch (e) {
      _logger.err(e.message);
      return ExitCode.usage.code;
    }

    final completion = Completer<void>();
    lsxGetEventStream(pid: pid).listen(
      (event) async {
        if (event == 'RequestLicense') {
          _logger.info(
            'Game requested license; BFII host-server health check continues '
            'separately.',
          );
          unawaited(
            licenseService.upload(id: authContext.licenseId).catchError((
              Object e,
            ) {
              _logger.err('License upload failed: $e');
            }),
          );
        }
      },
      onDone: completion.complete,
      onError: (e) => completion.complete(),
    );

    await completion.future;

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

  bool _resolveCredentiallessHost({
    required bool onlineMode,
    required String? credentials,
  }) {
    final flag = argResults?['credentialless-host'] as bool? ?? false;
    final envValue = Platform.environment['KYBER_CREDENTIALLESS_HOST'];
    final envEnabled = switch (envValue?.trim().toLowerCase()) {
      null || '' || '0' || 'false' || 'no' => false,
      '1' || 'true' || 'yes' => true,
      final value => throw BfiiHostConfigException(
        'KYBER_CREDENTIALLESS_HOST must be 1 or 0, got "$value".',
      ),
    };

    final enabled = flag || envEnabled;
    if (!enabled) {
      return false;
    }

    if (onlineMode) {
      throw const BfiiHostConfigException(
        '--credentialless-host requires --offline or KYBER_ONLINE_MODE=0.',
      );
    }

    if (credentials != null) {
      throw const BfiiHostConfigException(
        '--credentialless-host cannot be combined with credentials.',
      );
    }

    return true;
  }

  _BfiiLicenseMode _resolveLicenseMode() {
    final optionValue = argResults?['license-mode'] as String?;
    final rawValue =
        optionValue ??
        Platform.environment['KYBER_DEDICATED_LICENSE_MODE'] ??
        Platform.environment['KYBER_LICENSE_MODE'];
    final value = (rawValue ?? 'reuse').trim().toLowerCase();

    return switch (value) {
      'reuse' => _BfiiLicenseMode.reuse,
      'refresh' => _BfiiLicenseMode.refresh,
      _ => throw BfiiHostConfigException(
        'license-mode must be reuse or refresh, got "$value".',
      ),
    };
  }

  String? _resolveDenuvoTokenOverride() {
    final optionValue = argResults?['denuvo-token'] as String?;
    final rawValue =
        optionValue ??
        Platform.environment['KYBER_DENUVO_TOKEN'] ??
        Platform.environment['KYBER_DEDICATED_DENUVO_TOKEN'] ??
        Platform.environment['MAXIMA_DENUVO_TOKEN'];
    final value = rawValue?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  void _configureLicenseEnvironment({
    required _BfiiLicenseMode mode,
    required String? denuvoTokenOverride,
  }) {
    Env.set('KYBER_DEDICATED_LICENSE_MODE', mode.name);
    if (mode == _BfiiLicenseMode.refresh) {
      Env.set('MAXIMA_FORCE_LICENSE_REFRESH', '1');
    } else {
      Env.delete('MAXIMA_FORCE_LICENSE_REFRESH');
    }

    if (denuvoTokenOverride != null) {
      Env.set('MAXIMA_DENUVO_TOKEN', denuvoTokenOverride);
    } else if (mode == _BfiiLicenseMode.refresh) {
      Env.delete('MAXIMA_DENUVO_TOKEN');
    }

    _logger.info(
      'BFII license mode: ${mode.name}'
      '${denuvoTokenOverride == null ? '' : ' with explicit Denuvo token'}',
    );
  }

  void _cleanInvalidLocalBfiiLicenseFiles({required String contentId}) {
    if (!Platform.isWindows) {
      return;
    }

    final programData = Platform.environment['ProgramData'];
    if (programData == null || programData.trim().isEmpty) {
      throw const BfiiHostConfigException(
        'ProgramData is not set; cannot clean stale BFII license files.',
      );
    }

    final licenseDirectory = Directory(
      '$programData\\Electronic Arts\\EA Services\\License',
    );
    if (!licenseDirectory.existsSync()) {
      return;
    }

    for (final fileName in ['$contentId.dlf', '${contentId}_cached.dlf']) {
      final file = File('${licenseDirectory.path}\\$fileName');
      if (!file.existsSync()) {
        continue;
      }

      if (_hasEncodedLicenseSignatureHeader(file)) {
        _logger.info(
          'Existing BFII license file has a valid encoded signature header: '
          '${file.path}',
        );
        continue;
      }

      try {
        file.deleteSync();
        _logger.info(
          'Removed invalid BFII license file before refresh: ${file.path}',
        );
      } on FileSystemException catch (e) {
        throw BfiiHostConfigException(
          'Failed to remove invalid BFII license file ${file.path}: '
          '${e.message}',
        );
      }
    }
  }

  bool _hasEncodedLicenseSignatureHeader(File file) {
    const headerLength = 65;
    RandomAccessFile? handle;
    try {
      handle = file.openSync();
      if (handle.lengthSync() < headerLength) {
        return false;
      }

      return _isValidEncodedLicenseSignatureHeader(
        handle.readSync(headerLength),
      );
    } on FileSystemException {
      return false;
    } finally {
      handle?.closeSync();
    }
  }

  bool _isValidEncodedLicenseSignatureHeader(List<int> header) {
    if (header.isEmpty || header.first == 0) {
      return false;
    }

    var seenPadding = false;
    final encoded = <int>[];
    for (final byte in header) {
      if (byte == 0) {
        seenPadding = true;
        continue;
      }

      if (seenPadding || byte < 32 || byte > 126) {
        return false;
      }

      encoded.add(byte);
    }

    if (encoded.length < 40) {
      return false;
    }

    try {
      final decoded = base64.decode(ascii.decode(encoded));
      return _derSequenceLength(decoded) == decoded.length;
    } on FormatException {
      return false;
    }
  }

  int? _derSequenceLength(List<int> bytes) {
    if (bytes.length < 2 || bytes.first != 0x30) {
      return null;
    }

    final lengthByte = bytes[1];
    if ((lengthByte & 0x80) == 0) {
      final totalLength = 2 + lengthByte;
      return totalLength <= bytes.length ? totalLength : null;
    }

    final lengthByteCount = lengthByte & 0x7f;
    if (lengthByteCount == 0 ||
        lengthByteCount > 4 ||
        bytes.length < 2 + lengthByteCount) {
      return null;
    }

    var payloadLength = 0;
    for (var i = 0; i < lengthByteCount; i++) {
      payloadLength = (payloadLength << 8) + bytes[2 + i];
    }

    final totalLength = 2 + lengthByteCount + payloadLength;
    return totalLength <= bytes.length ? totalLength : null;
  }
}

enum _BfiiLicenseMode { reuse, refresh }
