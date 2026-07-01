import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/features/map_rotation/models/map_rotation_entry.dart';
import 'package:kyber_launcher/features/mod_collections/providers/mod_collection_cubit.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/features/server_host/models/host_start_progress_event.dart';
import 'package:kyber_launcher/features/server_host/services/dedicated_host_user_config_service.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:path/path.dart' as p;

enum ExternalDedicatedHostStatus {
  idle,
  starting,
  running,
  failed,
  stopping,
}

class ExternalDedicatedHostState {
  const ExternalDedicatedHostState({
    required this.status,
    this.pid,
    this.serverName,
    this.port,
    this.stdoutPath,
    this.stderrPath,
    this.error,
    this.startedAt,
    this.logs = const [],
  });

  const ExternalDedicatedHostState.idle()
    : this(status: ExternalDedicatedHostStatus.idle);

  final ExternalDedicatedHostStatus status;
  final int? pid;
  final String? serverName;
  final int? port;
  final String? stdoutPath;
  final String? stderrPath;
  final String? error;
  final DateTime? startedAt;
  final List<String> logs;

  bool get isRunning => status == ExternalDedicatedHostStatus.running;

  ExternalDedicatedHostState copyWith({
    ExternalDedicatedHostStatus? status,
    int? pid,
    String? serverName,
    int? port,
    String? stdoutPath,
    String? stderrPath,
    String? error,
    DateTime? startedAt,
    List<String>? logs,
  }) {
    return ExternalDedicatedHostState(
      status: status ?? this.status,
      pid: pid ?? this.pid,
      serverName: serverName ?? this.serverName,
      port: port ?? this.port,
      stdoutPath: stdoutPath ?? this.stdoutPath,
      stderrPath: stderrPath ?? this.stderrPath,
      error: error,
      startedAt: startedAt ?? this.startedAt,
      logs: logs ?? this.logs,
    );
  }
}

class ExternalDedicatedHostException implements Exception {
  const ExternalDedicatedHostException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _HostHelperResult {
  const _HostHelperResult.ready() : exitCode = null;

  const _HostHelperResult.exit(this.exitCode);

  final int? exitCode;

  bool get isReady => exitCode == null;
}

class ExternalDedicatedHostService extends ChangeNotifier {
  ExternalDedicatedHostState _state = const ExternalDedicatedHostState.idle();

  ExternalDedicatedHostState get state => _state;

  Future<void> start({
    required String serverName,
    required int port,
    required int maxPlayers,
    required String? password,
    required bool passwordPresent,
    required ModCollectionMetaData collection,
    required List<MapRotationEntry> mapEntries,
    required List<String> startupCommands,
    HostStartProgressSink? onProgress,
  }) async {
    if (_state.status == ExternalDedicatedHostStatus.starting) {
      throw const ExternalDedicatedHostException(
        'A BFII host server is already starting.',
      );
    }

    if (_state.status == ExternalDedicatedHostStatus.running) {
      throw const ExternalDedicatedHostException(
        'A BFII host server is already running.',
      );
    }

    final launchConfig = await sl
        .get<DedicatedHostUserConfigService>()
        .resolveLaunchConfig();
    final runtime = launchConfig.runtime;

    final tempDir = await Directory.systemTemp.createTemp('kyber_host_');
    final rawMods = await _writeRawModsIfNeeded(tempDir, collection);
    final startupFile = await _writeStartupCommandsIfNeeded(
      tempDir,
      startupCommands,
    );
    final firstMap = mapEntries.first;

    final args = [
      '-Action',
      'Host',
      '-CliExe',
      runtime.cliExePath,
      '-GamePath',
      launchConfig.gamePath,
      '-ModulePath',
      runtime.modulePath,
      '-ServerName',
      serverName,
      '-ServerPort',
      port.toString(),
      '-MaxPlayers',
      maxPlayers.toString(),
      '-Map',
      firstMap.map,
      '-Mode',
      firstMap.mode,
      '-LicenseMode',
      launchConfig.licenseMode.value,
      '-CredentiallessHost',
      '-ReadyTimeoutSeconds',
      '180',
      '-LogStallTimeoutSeconds',
      '35',
      '-CleanupOrphans',
      if (passwordPresent) ...[
        '-ServerPassword',
        password!,
      ],
      if (rawMods != null) ...[
        '-RawMods',
        rawMods.path,
      ],
      if (startupFile != null) ...[
        '-StartupCommands',
        startupFile.path,
      ],
    ];

    final environment = Map<String, String>.from(Platform.environment)
      ..['KYBER_DEDICATED_LICENSE_MODE'] = launchConfig.licenseMode.value
      ..['KYBER_CREDENTIALLESS_HOST'] = '1'
      ..['KYBER_MAP_ROTATION'] = _encodeMapRotation(mapEntries)
      ..['KYBER_ONLINE_MODE'] = '0'
      ..remove('KYBER_DEDICATED_CREDENTIALS')
      ..remove('KYBER_BFII_HOST_CREDENTIALS')
      ..remove('MAXIMA_CREDENTIALS');
    if (launchConfig.denuvoToken?.isNotEmpty == true) {
      environment['KYBER_DEDICATED_DENUVO_TOKEN'] = launchConfig.denuvoToken!;
    }

    _setState(
      ExternalDedicatedHostState(
        status: ExternalDedicatedHostStatus.starting,
        serverName: serverName,
        port: port,
        logs: [
          'Checking for orphaned BFII/Kyber host processes before startup...',
          'Using passwordless direct host mode; EA passwords are not passed.',
          'BFII license mode: ${launchConfig.licenseMode.value}.',
          'Starting external BFII host helper...',
        ],
      ),
    );
    _emitProgressLine(
      onProgress,
      'Checking for orphaned BFII/Kyber host processes before startup...',
    );
    _emitProgressLine(
      onProgress,
      'Using passwordless direct host mode; EA passwords are not passed.',
    );
    _emitProgressLine(
      onProgress,
      'BFII license mode: ${launchConfig.licenseMode.value}.',
    );
    _emitProgressLine(onProgress, 'Starting external BFII host helper...');

    late final Process process;
    try {
      process = await Process.start(
        'cmd.exe',
        _cmdArgs(runtime.commandPath, args),
        environment: environment,
        workingDirectory: runtime.workingDirectory,
      );
    } on Object catch (e) {
      await _stopRuntimeAfterFailedStart(port: port, onProgress: onProgress);
      final message = 'Failed to start external BFII host helper: $e';
      _setState(
        _state.copyWith(
          status: ExternalDedicatedHostStatus.failed,
          error: message,
        ),
      );
      _emitProgressLine(
        onProgress,
        message,
        status: HostStartProgressStatus.error,
      );
      throw ExternalDedicatedHostException(message);
    }

    final stdoutLines = <String>[];
    final stderrLines = <String>[];
    final ready = Completer<_HostHelperResult>();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    // The subscriptions are cancelled by _cleanupHelperStreams after either
    // the helper exits or the ready marker lets the UI return early.
    // ignore: cancel_subscriptions
    final stdoutSub = process.stdout
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stdoutLines.add(line);
          _appendLog(line);
          _emitProgressLine(onProgress, line);
          _completeReadyIfMatched(line, ready);
        }, onDone: stdoutDone.complete);
    // The subscriptions are cancelled by _cleanupHelperStreams after either
    // the helper exits or the ready marker lets the UI return early.
    // ignore: cancel_subscriptions
    final stderrSub = process.stderr
        .transform(systemEncoding.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final logLine = 'ERR: $line';
          stderrLines.add(line);
          _appendLog(logLine);
          _emitProgressLine(onProgress, logLine);
        }, onDone: stderrDone.complete);

    final result = await Future.any([
      ready.future,
      process.exitCode.then(_HostHelperResult.exit),
    ]);

    if (result.isReady) {
      _setRunning(stdoutLines);
      _emitProgressLine(
        onProgress,
        'External BFII host helper completed; server process is running.',
        status: HostStartProgressStatus.success,
      );
      unawaited(
        _cleanupHelperStreams(
          stdoutDone: stdoutDone.future,
          stderrDone: stderrDone.future,
          stdoutSub: stdoutSub,
          stderrSub: stderrSub,
        ),
      );
      return;
    }

    final exitCode = result.exitCode!;
    await _cleanupHelperStreams(
      stdoutDone: stdoutDone.future,
      stderrDone: stderrDone.future,
      stdoutSub: stdoutSub,
      stderrSub: stderrSub,
    );

    if (exitCode == 0 && _hasReadyOutput(stdoutLines)) {
      _setRunning(stdoutLines);
      _emitProgressLine(
        onProgress,
        'External BFII host helper completed; server process is running.',
        status: HostStartProgressStatus.success,
      );
      return;
    }

    if (exitCode != 0) {
      final diagnostics = await _collectFailureDiagnostics(
        runtime: runtime,
        stdoutLines: stdoutLines,
        stderrLines: stderrLines,
      );
      final message = [
        'External BFII host helper exited with code $exitCode.',
        ..._tail(stderrLines, 80),
        ..._tail(stdoutLines, 80),
        ...diagnostics,
      ].where((line) => line.trim().isNotEmpty).join('\n');
      await _stopRuntimeAfterFailedStart(port: port, onProgress: onProgress);
      _setState(
        _state.copyWith(
          status: ExternalDedicatedHostStatus.failed,
          error: message,
        ),
      );
      _emitProgressLine(
        onProgress,
        message,
        status: HostStartProgressStatus.error,
      );
      throw ExternalDedicatedHostException(message);
    }

    final diagnostics = await _collectFailureDiagnostics(
      runtime: runtime,
      stdoutLines: stdoutLines,
      stderrLines: stderrLines,
    );
    final message = [
      'External BFII host helper exited before the ready marker.',
      ..._tail(stderrLines, 80),
      ..._tail(stdoutLines, 80),
      ...diagnostics,
    ].where((line) => line.trim().isNotEmpty).join('\n');
    await _stopRuntimeAfterFailedStart(port: port, onProgress: onProgress);
    _setState(
      _state.copyWith(
        status: ExternalDedicatedHostStatus.failed,
        error: message,
      ),
    );
    _emitProgressLine(
      onProgress,
      message,
      status: HostStartProgressStatus.error,
    );
    throw ExternalDedicatedHostException(message);
  }

  Future<void> _stopRuntimeAfterFailedStart({
    required int port,
    HostStartProgressSink? onProgress,
  }) async {
    _emitProgressLine(
      onProgress,
      'Startup failed; stopping any leftover BFII host-server processes.',
    );
    try {
      final runtime = sl
          .get<DedicatedHostUserConfigService>()
          .resolveRuntimeLayout();
      final result = await Process.run(
        'cmd.exe',
        _cmdArgs(runtime.commandPath, [
          '-Action',
          'Stop',
          '-ServerPort',
          port.toString(),
        ]),
        workingDirectory: runtime.workingDirectory,
      );

      final stdout = (result.stdout as String).trim();
      final stderr = (result.stderr as String).trim();
      if (stdout.isNotEmpty) {
        for (final line in const LineSplitter().convert(stdout)) {
          _appendLog(line);
          _emitProgressLine(onProgress, line);
        }
      }
      if (stderr.isNotEmpty) {
        for (final line in const LineSplitter().convert(stderr)) {
          final logLine = 'ERR: $line';
          _appendLog(logLine);
          _emitProgressLine(onProgress, logLine);
        }
      }
    } on Object catch (e) {
      final message = 'Failed to run dedicated cleanup after startup error: $e';
      _appendLog(message);
      _emitProgressLine(onProgress, message);
    }
  }

  Future<void> cleanupOrphans({HostStartProgressSink? onProgress}) async {
    final port = _state.port ?? 25200;
    _emitProgressLine(
      onProgress,
      'Running dedicated orphan cleanup on port $port...',
    );
    final runtime = sl
        .get<DedicatedHostUserConfigService>()
        .resolveRuntimeLayout();
    final result = await Process.run(
      'cmd.exe',
      _cmdArgs(runtime.commandPath, [
        '-Action',
        'Cleanup',
        '-ServerPort',
        port.toString(),
      ]),
      workingDirectory: runtime.workingDirectory,
    );

    _appendProcessRunOutput(
      stdout: result.stdout as String,
      stderr: result.stderr as String,
      onProgress: onProgress,
    );

    if (result.exitCode != 0) {
      throw ExternalDedicatedHostException(
        'Dedicated orphan cleanup exited with code ${result.exitCode}.',
      );
    }

    _setState(
      ExternalDedicatedHostState(
        status: ExternalDedicatedHostStatus.idle,
        logs: _state.logs,
      ),
    );
  }

  Future<void> stop() async {
    if (_state.status == ExternalDedicatedHostStatus.idle) {
      return;
    }

    final port = _state.port ?? 25200;
    _setState(_state.copyWith(status: ExternalDedicatedHostStatus.stopping));
    final runtime = sl
        .get<DedicatedHostUserConfigService>()
        .resolveRuntimeLayout();
    final result = await Process.run(
      'cmd.exe',
      _cmdArgs(runtime.commandPath, [
        '-Action',
        'Stop',
        '-ServerPort',
        port.toString(),
      ]),
      workingDirectory: runtime.workingDirectory,
    );

    final logs = <String>[
      ..._state.logs,
      if ((result.stdout as String).trim().isNotEmpty) result.stdout as String,
      if ((result.stderr as String).trim().isNotEmpty) 'ERR: ${result.stderr}',
    ];
    _setState(
      ExternalDedicatedHostState(
        status: ExternalDedicatedHostStatus.idle,
        logs: logs,
      ),
    );
  }

  void _appendProcessRunOutput({
    required String stdout,
    required String stderr,
    HostStartProgressSink? onProgress,
  }) {
    final cleanStdout = stdout.trim();
    final cleanStderr = stderr.trim();
    if (cleanStdout.isNotEmpty) {
      for (final line in const LineSplitter().convert(cleanStdout)) {
        _appendLog(line);
        _emitProgressLine(onProgress, line);
      }
    }
    if (cleanStderr.isNotEmpty) {
      for (final line in const LineSplitter().convert(cleanStderr)) {
        final logLine = 'ERR: $line';
        _appendLog(logLine);
        _emitProgressLine(onProgress, logLine);
      }
    }
  }

  String _encodeMapRotation(List<MapRotationEntry> mapEntries) {
    final lines = mapEntries
        .map((entry) => '${entry.mode};${entry.map}')
        .join('\n');
    return base64.encode(utf8.encode(lines));
  }

  Future<File?> _writeRawModsIfNeeded(
    Directory tempDir,
    ModCollectionMetaData collection,
  ) async {
    final modPaths = collection.getModPaths();
    if (modPaths.isEmpty) {
      return null;
    }

    final file = File(p.join(tempDir.path, 'raw_mods.json'));
    await file.writeAsString(
      jsonEncode({
        'basePath': ModService.getBasePath(),
        'modPaths': modPaths,
      }),
    );
    return file;
  }

  Future<File?> _writeStartupCommandsIfNeeded(
    Directory tempDir,
    List<String> startupCommands,
  ) async {
    if (startupCommands.isEmpty) {
      return null;
    }

    final file = File(p.join(tempDir.path, 'startup_commands.txt'));
    await file.writeAsString(startupCommands.join('\n'));
    return file;
  }

  int? _parseHostPid(List<String> lines) {
    final patterns = [
      RegExp(r'Dedicated server ready\. PID: (\d+)'),
      RegExp(r'Dedicated server already running\. PID: (\d+)'),
    ];
    for (final line in lines) {
      for (final pattern in patterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          return int.tryParse(match.group(1)!);
        }
      }
    }

    return null;
  }

  bool _hasReadyOutput(List<String> lines) {
    return lines.any(_lineMarksReadyToReturn);
  }

  bool _lineMarksReadyToReturn(String line) {
    return line.startsWith('Dedicated server ready.') ||
        line.startsWith('Server log:') ||
        line.startsWith('Dedicated server already running.') ||
        line.startsWith('Leave the BFII server host process');
  }

  void _completeReadyIfMatched(
    String line,
    Completer<_HostHelperResult> ready,
  ) {
    if (!ready.isCompleted && _lineMarksReadyToReturn(line)) {
      ready.complete(const _HostHelperResult.ready());
    }
  }

  Future<List<String>> _collectFailureDiagnostics({
    required DedicatedHostRuntimeLayout runtime,
    required List<String> stdoutLines,
    required List<String> stderrLines,
  }) async {
    final paths = <String>{};
    for (final path in [
      ..._pathsFromLatestMarkers(runtime),
      ..._pathsFromHelperOutput([...stdoutLines, ...stderrLines]),
    ]) {
      final cleanPath = path.trim();
      if (cleanPath.isEmpty) {
        continue;
      }
      paths.add(p.normalize(cleanPath));
    }

    final diagnostics = <String>[];
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) {
        continue;
      }

      diagnostics
        ..add('--- ${file.path} ---')
        ..addAll(await _readTailLines(file, maxLines: 60));
    }

    return diagnostics;
  }

  Iterable<String> _pathsFromLatestMarkers(
    DedicatedHostRuntimeLayout runtime,
  ) sync* {
    for (final logDir in [
      p.join(runtime.rootPath, 'logs'),
      p.join(runtime.rootPath, 'CLI', 'dev_build', 'one_click_logs'),
    ]) {
      for (final markerName in const [
        'latest.stdout.path',
        'latest.stderr.path',
      ]) {
        final marker = File(p.join(logDir, markerName));
        if (!marker.existsSync()) {
          continue;
        }

        final path = marker.readAsStringSync().trim();
        if (path.isNotEmpty) {
          yield path;
        }
      }
    }
  }

  Iterable<String> _pathsFromHelperOutput(List<String> lines) sync* {
    final pattern = RegExp(
      r'([A-Za-z]:\\[^\r\n]+?host_server_\d{8}_\d{6}\.(?:stdout|stderr)\.log)',
    );
    for (final line in lines) {
      for (final match in pattern.allMatches(line)) {
        final path = match.group(1);
        if (path != null && path.trim().isNotEmpty) {
          yield path;
        }
      }
    }
  }

  Future<List<String>> _readTailLines(
    File file, {
    required int maxLines,
  }) async {
    try {
      final lines = await file.readAsLines();
      return _tail(
        lines.where((line) => line.trim().isNotEmpty).toList(),
        maxLines,
      );
    } on Object catch (e) {
      return ['Failed to read ${file.path}: $e'];
    }
  }

  List<String> _tail(List<String> lines, int maxLines) {
    if (lines.length <= maxLines) {
      return lines;
    }

    return lines.sublist(lines.length - maxLines);
  }

  String? _parsePath(List<String> lines, String prefix) {
    for (final line in lines) {
      if (line.startsWith(prefix)) {
        return line.substring(prefix.length).trim();
      }
    }

    return null;
  }

  void _appendLog(String line) {
    _setState(_state.copyWith(logs: [..._state.logs, line]));
  }

  void _setRunning(List<String> stdoutLines) {
    _setState(
      _state.copyWith(
        status: ExternalDedicatedHostStatus.running,
        pid: _parseHostPid(stdoutLines),
        stdoutPath: _parsePath(stdoutLines, 'Server log:'),
        startedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _cleanupHelperStreams({
    required Future<void> stdoutDone,
    required Future<void> stderrDone,
    required StreamSubscription<String> stdoutSub,
    required StreamSubscription<String> stderrSub,
  }) async {
    try {
      await Future.wait([stdoutDone, stderrDone]).timeout(
        const Duration(seconds: 2),
      );
    } on Object {
      // The host process is already ready; stream cleanup must not keep the UI
      // dialog open if the helper keeps a pipe alive longer than expected.
    }

    await stdoutSub.cancel();
    await stderrSub.cancel();
  }

  void _emitProgressLine(
    HostStartProgressSink? onProgress,
    String message, {
    HostStartProgressStatus status = HostStartProgressStatus.running,
  }) {
    onProgress?.call(
      HostStartProgressEvent(
        message: message,
        status: status,
      ),
    );
  }

  void _setState(ExternalDedicatedHostState state) {
    _state = state;
    notifyListeners();
  }

  List<String> _cmdArgs(String commandPath, List<String> args) {
    return ['/d', '/s', '/c', 'call', commandPath, ...args];
  }
}
