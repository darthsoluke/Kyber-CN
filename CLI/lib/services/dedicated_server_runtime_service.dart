import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:kyber/gen/Proto/kyber_common.pb.dart' as common;
import 'package:kyber/gen/Proto/kyber_interface.pbgrpc.dart' as iface;
import 'package:kyber_cli/command_runner.dart';
import 'package:kyber_cli/gen/api/maxima.dart';
import 'package:kyber_cli/models/maxima_instance.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart';

final class DedicatedServerRuntimeException implements Exception {
  const DedicatedServerRuntimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DedicatedServerRuntimeService {
  const DedicatedServerRuntimeService({required Logger logger})
    : _logger = logger;

  final Logger _logger;

  Future<int> start({
    required String gamePath,
    required String modulePath,
    required int interfacePort,
    required int serverPort,
    required List<FrostyMod> gameplayMods,
    required List<String> gameArgs,
    required String? credentials,
  }) async {
    _validateGameExecutable(gamePath);
    final runtimeFiles = _resolveRuntimeFiles(modulePath);
    _installRuntimeFiles(gamePath: gamePath, runtimeFiles: runtimeFiles);

    int? pid;
    late final int hostPid;
    final licenseGuard = _BfiiLicenseGuard(logger: _logger);
    await licenseGuard.repairIfNeeded(reason: 'before BFII process start');

    try {
      try {
        hostPid = await _startDedicatedHostProcess(
          gamePath: gamePath,
          gameArgs: gameArgs,
          credentials: credentials,
        );
        pid = hostPid;
        await licenseGuard.waitUntilStableAfterProcessStart();
      } catch (e) {
        await stopDedicatedHostProcesses(
          logger: _logger,
          reason: 'BFII host-server process failed before readiness',
        );
        throw DedicatedServerRuntimeException(
          'Failed to start BFII host-server process: ${_formatStartError(e)}',
        );
      }

      _logger
        ..info('BFII host-server process started with PID: $hostPid')
        ..info('Injecting Kyber from ${runtimeFiles.kyberModule}');

      try {
        await injectKyber(pid: hostPid, path: runtimeFiles.kyberModule);
      } catch (e) {
        await stopDedicatedHostProcesses(
          logger: _logger,
          reason:
              'Kyber injection failed for BFII host-server process $hostPid',
        );
        throw DedicatedServerRuntimeException(
          'Failed to inject Kyber into BFII host-server process $hostPid: $e',
        );
      }

      sl.registerSingleton<MaximaGameInstance>(
        MaximaGameInstance(
          pid: hostPid,
          isDedicated: true,
          clientService: .new('', 0),
          mods: gameplayMods,
        ),
      );

      await _waitForDedicatedServerReady(
        interfacePort: interfacePort,
        expectedServerPort: serverPort,
      );
    } on DedicatedServerRuntimeException {
      final startedPid = pid;
      if (startedPid != null) {
        await stopDedicatedHostProcesses(
          logger: _logger,
          reason: 'BFII host-server process $startedPid did not become ready',
        );
      }
      rethrow;
    } catch (e) {
      await stopDedicatedHostProcesses(
        logger: _logger,
        reason: 'BFII host-server process $pid failed during readiness check',
      );
      throw DedicatedServerRuntimeException(
        'Dedicated server readiness check failed: $e',
      );
    }

    return hostPid;
  }

  static Future<void> stopDedicatedHostProcesses({
    required Logger logger,
    required String reason,
  }) async {
    if (!Platform.isWindows) {
      return;
    }

    logger.info('Stopping BFII host-server runtime after: $reason');

    await _stopMaximaService(logger);
    for (final imageName in const [
      'starwarsbattlefrontii.exe',
      'maxima-bootstrap.exe',
      'maxima-service.exe',
      'ActivationUI.exe',
      'activation.exe',
    ]) {
      await _killImage(logger: logger, imageName: imageName);
    }
  }

  static Future<void> _stopMaximaService(Logger logger) async {
    final result = await _runWindowsProcess('sc.exe', [
      'stop',
      'MaximaBackgroundService',
    ]);
    if (result.exitCode == 0) {
      logger.info('Requested MaximaBackgroundService stop.');
      await Future<void>.delayed(const Duration(seconds: 2));
      return;
    }

    final output = _processOutput(result);
    if (!_isExpectedMissingProcessOutput(output)) {
      logger.warn('MaximaBackgroundService stop returned: $output');
    }
  }

  static Future<void> _killImage({
    required Logger logger,
    required String imageName,
  }) async {
    final result = await _runWindowsProcess('taskkill', [
      '/F',
      '/T',
      '/IM',
      imageName,
    ]);
    if (result.exitCode == 0) {
      logger.info('Stopped dedicated runtime process image: $imageName');
      return;
    }
    if (result.exitCode == 128) {
      return;
    }

    final output = _processOutput(result);
    if (!_isExpectedMissingProcessOutput(output)) {
      logger.warn('Failed to stop $imageName: $output');
    }
  }

  static Future<ProcessResult> _runWindowsProcess(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments, runInShell: true);
  }

  static String _processOutput(ProcessResult result) {
    return [
      (result.stdout as String?)?.trim(),
      (result.stderr as String?)?.trim(),
    ].whereType<String>().where((line) => line.isNotEmpty).join(' ');
  }

  static bool _isExpectedMissingProcessOutput(String output) {
    final lower = output.toLowerCase();
    return output.isEmpty ||
        lower.contains('not found') ||
        lower.contains('no running instance') ||
        lower.contains('does not exist') ||
        lower.contains('1060') ||
        lower.contains('1062');
  }

  Future<int> _startDedicatedHostProcess({
    required String gamePath,
    required List<String> gameArgs,
    required String? credentials,
  }) {
    final parsedCredentials = _parseCredentials(credentials);
    return startGame(
      gameSlug: 'star-wars-battlefront-2',
      gamePathOverride: gamePath,
      gameArgs: gameArgs,
      user: parsedCredentials?.user,
      pass: parsedCredentials?.pass,
    );
  }

  _DedicatedServerCredentials? _parseCredentials(String? credentials) {
    if (credentials == null || credentials.trim().isEmpty) {
      return null;
    }

    final split = credentials.split(':');
    if (split.length != 2 || split.first.isEmpty || split.last.isEmpty) {
      throw const DedicatedServerRuntimeException(
        'Invalid credentials format. Use persona:password',
      );
    }

    return _DedicatedServerCredentials(user: split.first, pass: split.last);
  }

  String _formatStartError(Object error) {
    final message = error.toString();
    const credentiallessLicenseMarker =
        'credentialless launch requires a valid local license for content';
    if (message.contains(credentiallessLicenseMarker)) {
      return 'credentialless host mode requires a valid local BFII license '
          'in the Wine prefix. Import 1035052.dlf with '
          'KYBER_LICENSE_IMPORT_DIR, or run through the credentialed path once '
          'to provision the license.';
    }

    const credentiallessMachineMarker =
        'credentialless launch local license for content';
    if (message.contains(credentiallessMachineMarker)) {
      return 'credentialless host mode found a BFII license, but it was '
          'generated for a different machine/Wine prefix. Provision the '
          'license inside this exact WSL/Docker Wine prefix, or use a license '
          'sync endpoint that stores a prefix-matching 1035052.dlf.';
    }

    if (message.contains('INVALID_PASSWORD')) {
      return 'EA/Maxima credentials were rejected (INVALID_PASSWORD). '
          'Open BFII Dedicated Host settings, re-enter the account password, '
          'then retry.';
    }

    if (message.contains('Invalid Cipher') ||
        message.contains('Invalid license')) {
      return 'BFII rejected the local EA license (Invalid Cipher). '
          'Stop all BFII host processes, refresh the EA/Maxima credentials, '
          'and let Maxima request a fresh license on the next launch.';
    }

    return message.split('Stack backtrace:').first.trim();
  }

  void _validateGameExecutable(String gamePath) {
    if (!File(gamePath).existsSync()) {
      throw DedicatedServerRuntimeException(
        'game-path points to a missing file: $gamePath',
      );
    }
  }

  _DedicatedServerRuntimeFiles _resolveRuntimeFiles(String modulePath) {
    if (!Directory(modulePath).existsSync()) {
      throw DedicatedServerRuntimeException(
        'module-path points to a missing directory: $modulePath',
      );
    }

    final missing = <String>[];
    final kyberModule = join(modulePath, 'Kyber.dll');
    final vivoxSdk = join(modulePath, 'vivoxsdk.dll');
    for (final path in [kyberModule, vivoxSdk]) {
      if (!File(path).existsSync()) {
        missing.add(basename(path));
      }
    }

    if (missing.isNotEmpty) {
      throw DedicatedServerRuntimeException(
        'module-path is missing required runtime file(s): '
        '${missing.join(', ')}',
      );
    }

    return _DedicatedServerRuntimeFiles(
      kyberModule: kyberModule,
      vivoxSdk: vivoxSdk,
    );
  }

  void _installRuntimeFiles({
    required String gamePath,
    required _DedicatedServerRuntimeFiles runtimeFiles,
  }) {
    final gameDirectory = File(gamePath).parent;
    if (!gameDirectory.existsSync()) {
      throw DedicatedServerRuntimeException(
        'game-path parent directory does not exist: ${gameDirectory.path}',
      );
    }

    final targetVivox = File(join(gameDirectory.path, 'vivoxsdk.dll'));
    if (targetVivox.existsSync()) {
      _logger.info('vivoxsdk.dll already present at ${targetVivox.path}');
      return;
    }

    File(runtimeFiles.vivoxSdk).copySync(targetVivox.path);
    _logger.info('Installed vivoxsdk.dll to ${targetVivox.path}');
  }

  Future<void> _waitForDedicatedServerReady({
    required int interfacePort,
    required int expectedServerPort,
  }) async {
    final timeout = _resolveReadyTimeout();
    final deadline = DateTime.now().add(timeout);
    Object? lastError;

    while (DateTime.now().isBefore(deadline)) {
      final channel = ClientChannel(
        '127.0.0.1',
        port: interfacePort,
        options: const ChannelOptions(
          credentials: ChannelCredentials.insecure(),
        ),
      );
      final client = iface.CommonClient(channel);

      try {
        final state = await client.getInfo(
          common.Empty(),
          options: CallOptions(timeout: const Duration(seconds: 2)),
        );
        if (state.hasServer() && state.server.hasLevelSetup()) {
          if (expectedServerPort > 0 &&
              state.server.hasPort() &&
              state.server.port != expectedServerPort) {
            throw DedicatedServerRuntimeException(
              'Dedicated server reported unexpected port '
              '${state.server.port}; expected $expectedServerPort.',
            );
          }

          _logger.success(
            'Dedicated server ready: '
            '${state.server.levelSetup.map} '
            '${state.server.levelSetup.mode} '
            'port=${state.server.port}',
          );
          await channel.shutdown();
          return;
        }
      } catch (e) {
        lastError = e;
      } finally {
        await channel.shutdown();
      }

      await Future<void>.delayed(const Duration(seconds: 2));
    }

    throw DedicatedServerRuntimeException(
      'Dedicated server did not become ready on interface port '
      '$interfacePort within ${timeout.inSeconds} seconds. '
      'Last error: $lastError',
    );
  }

  Duration _resolveReadyTimeout() {
    final raw = Platform.environment['KYBER_DEDICATED_READY_TIMEOUT_SECONDS'];
    if (raw == null || raw.trim().isEmpty) {
      return const Duration(minutes: 4);
    }

    final seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds <= 0) {
      throw DedicatedServerRuntimeException(
        'KYBER_DEDICATED_READY_TIMEOUT_SECONDS must be a positive integer, '
        'got "$raw".',
      );
    }

    return Duration(seconds: seconds);
  }
}

final class _BfiiLicenseGuard {
  _BfiiLicenseGuard({required Logger logger}) : _logger = logger;

  static const _contentId = '1035052';
  static const _headerLength = 65;

  final Logger _logger;
  bool _reportedReady = false;

  Future<void> repairIfNeeded({required String reason}) async {
    if (!Platform.isWindows) {
      return;
    }

    final licenseDirectory = _licenseDirectory();
    if (licenseDirectory == null) {
      return;
    }

    final main = File(join(licenseDirectory.path, '$_contentId.dlf'));
    final cached = File(
      join(licenseDirectory.path, '${_contentId}_cached.dlf'),
    );

    if (main.existsSync() && _hasEncodedSignatureHeader(main)) {
      if (!_reportedReady) {
        _logger.info('BFII license signature is encoded and ready.');
        _reportedReady = true;
      }
      return;
    }

    if (main.existsSync()) {
      final mainBytes = await main.readAsBytes();
      if (mainBytes.length > _headerLength) {
        final repairedHeader = _encodeDecodedSignatureHeader(
          mainBytes.take(_headerLength).toList(growable: false),
        );
        if (repairedHeader != null) {
          await main.writeAsBytes([
            ...repairedHeader,
            ...mainBytes.skip(_headerLength),
          ], flush: true);
          _reportedReady = true;
          _logger.info(
            'Re-encoded BFII license signature header in-place ($reason): '
            '${main.path}',
          );
          return;
        }
      }
    }

    if (!cached.existsSync() || !_hasEncodedSignatureHeader(cached)) {
      return;
    }

    final repairedFromCache = await _repairFromCachedHeader(
      main: main,
      cached: cached,
    );
    if (repairedFromCache) {
      _reportedReady = true;
      _logger.info(
        'Repaired BFII license signature from cached license ($reason): '
        '${main.path}',
      );
      return;
    }

    if (!_reportedReady) {
      _logger.warn(
        'BFII license signature is invalid and cannot be repaired from cache '
        'without mixing mismatched license bodies: ${main.path}',
      );
      _reportedReady = true;
    }
  }

  Future<void> waitUntilStableAfterProcessStart() async {
    if (!Platform.isWindows) {
      return;
    }

    final startedAt = DateTime.now();
    final deadline = startedAt.add(const Duration(seconds: 12));
    const minimumWait = Duration(milliseconds: 1500);
    const quietPeriod = Duration(milliseconds: 500);
    const pollDelay = Duration(milliseconds: 150);
    Object? lastError;

    while (DateTime.now().isBefore(deadline)) {
      try {
        await repairIfNeeded(reason: 'before Kyber injection');

        final main = _mainLicenseFile();
        if (main != null &&
            main.existsSync() &&
            _hasEncodedSignatureHeader(main)) {
          final now = DateTime.now();
          final elapsed = now.difference(startedAt);
          final lastModified = main.lastModifiedSync();
          final quietFor = now.difference(lastModified);
          if (elapsed >= minimumWait && quietFor >= quietPeriod) {
            _logger.info(
              'BFII license signature is stable before Kyber injection '
              '(quiet=${quietFor.inMilliseconds}ms).',
            );
            return;
          }
        }
      } catch (e) {
        lastError = e;
      }

      await Future<void>.delayed(pollDelay);
    }

    throw DedicatedServerRuntimeException(
      'BFII license did not become stable before Kyber injection. '
      'Last error: $lastError',
    );
  }

  Directory? _licenseDirectory() {
    final programData = Platform.environment['ProgramData'];
    if (programData == null || programData.trim().isEmpty) {
      return null;
    }

    final directory = Directory(
      join(programData, 'Electronic Arts', 'EA Services', 'License'),
    );
    return directory.existsSync() ? directory : null;
  }

  File? _mainLicenseFile() {
    final licenseDirectory = _licenseDirectory();
    if (licenseDirectory == null) {
      return null;
    }

    return File(join(licenseDirectory.path, '$_contentId.dlf'));
  }

  bool _hasEncodedSignatureHeader(File file) {
    RandomAccessFile? handle;
    try {
      handle = file.openSync();
      if (handle.lengthSync() < _headerLength) {
        return false;
      }

      return _isValidEncodedSignatureHeader(handle.readSync(_headerLength));
    } on FileSystemException {
      return false;
    } finally {
      handle?.closeSync();
    }
  }

  Future<bool> _repairFromCachedHeader({
    required File main,
    required File cached,
  }) async {
    final cachedBytes = await cached.readAsBytes();
    if (cachedBytes.length <= _headerLength ||
        !_isValidEncodedSignatureHeader(
          cachedBytes.take(_headerLength).toList(growable: false),
        )) {
      return false;
    }

    if (main.existsSync()) {
      final mainBytes = await main.readAsBytes();
      if (mainBytes.length > _headerLength) {
        final mainBody = mainBytes.skip(_headerLength).toList(growable: false);
        final cachedBody = cachedBytes
            .skip(_headerLength)
            .toList(growable: false);
        if (!_sameBytes(mainBody, cachedBody)) {
          return false;
        }
      }
    }

    await main.writeAsBytes(cachedBytes, flush: true);
    return true;
  }

  List<int>? _encodeDecodedSignatureHeader(List<int> header) {
    if (_isValidEncodedSignatureHeader(header)) {
      return null;
    }

    final decodedLength = _derSequenceLength(header);
    if (decodedLength == null) {
      return null;
    }

    final decoded = header.take(decodedLength).toList(growable: false);
    final encoded = ascii.encode(base64.encode(decoded));
    if (encoded.length > _headerLength) {
      return null;
    }

    return [...encoded, ...List<int>.filled(_headerLength - encoded.length, 0)];
  }

  bool _isValidEncodedSignatureHeader(List<int> header) {
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

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }

    return true;
  }
}

final class _DedicatedServerRuntimeFiles {
  const _DedicatedServerRuntimeFiles({
    required this.kyberModule,
    required this.vivoxSdk,
  });

  final String kyberModule;
  final String vivoxSdk;
}

final class _DedicatedServerCredentials {
  const _DedicatedServerCredentials({required this.user, required this.pass});

  final String user;
  final String pass;
}
