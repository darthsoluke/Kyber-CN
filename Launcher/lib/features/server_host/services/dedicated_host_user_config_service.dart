import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:path/path.dart' as p;

class DedicatedHostCredentials {
  const DedicatedHostCredentials({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  String get asEnvironmentValue => '$username:$password';
}

class DedicatedHostRuntimeLayout {
  const DedicatedHostRuntimeLayout({
    required this.rootPath,
    required this.commandPath,
    required this.scriptPath,
    required this.cliExePath,
    required this.modulePath,
    required this.workingDirectory,
  });

  final String rootPath;
  final String commandPath;
  final String scriptPath;
  final String cliExePath;
  final String modulePath;
  final String workingDirectory;
}

enum DedicatedHostLicenseMode {
  reuse('reuse'),
  refresh('refresh')
  ;

  const DedicatedHostLicenseMode(this.value);

  final String value;

  static DedicatedHostLicenseMode fromValue(String value) {
    final cleanValue = value.trim().toLowerCase();
    for (final mode in DedicatedHostLicenseMode.values) {
      if (mode.value == cleanValue) {
        return mode;
      }
    }

    throw FormatException('Invalid dedicated host license mode: $value');
  }
}

class DedicatedHostLaunchConfig {
  const DedicatedHostLaunchConfig({
    required this.gamePath,
    required this.runtime,
    required this.licenseMode,
    required this.denuvoToken,
  });

  final String gamePath;
  final DedicatedHostRuntimeLayout runtime;
  final DedicatedHostLicenseMode licenseMode;
  final String? denuvoToken;
}

class DedicatedHostConfigException implements Exception {
  const DedicatedHostConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DedicatedHostUserConfigService {
  DedicatedHostUserConfigService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _usernameKey = 'kyber.dedicatedHost.username';
  static const _passwordKey = 'kyber.dedicatedHost.password';
  static const _denuvoTokenKey = 'kyber.dedicatedHost.denuvoToken';

  final FlutterSecureStorage _secureStorage;

  String get gamePath => Preferences.hostServer.dedicatedGamePath.trim();

  set gamePath(String value) {
    Preferences.hostServer.dedicatedGamePath = value.trim();
  }

  String get runtimeRoot => Preferences.hostServer.dedicatedRuntimeRoot.trim();

  set runtimeRoot(String value) {
    Preferences.hostServer.dedicatedRuntimeRoot = value.trim();
  }

  DedicatedHostLicenseMode get licenseMode =>
      DedicatedHostLicenseMode.fromValue(
        Preferences.hostServer.dedicatedLicenseMode,
      );

  set licenseMode(DedicatedHostLicenseMode value) {
    Preferences.hostServer.dedicatedLicenseMode = value.value;
  }

  Future<String?> readUsername() async {
    final value = await _secureStorage.read(key: _usernameKey);
    return value?.trim().isEmpty == true ? null : value?.trim();
  }

  Future<String?> readDenuvoToken() async {
    final value = await _secureStorage.read(key: _denuvoTokenKey);
    return value?.trim().isEmpty == true ? null : value?.trim();
  }

  Future<bool> hasDenuvoToken() async {
    final token = await readDenuvoToken();
    return token != null;
  }

  Future<bool> hasCredentials() async {
    final credentials = await readCredentials();
    return credentials != null;
  }

  Future<DedicatedHostCredentials?> readCredentials() async {
    final username = (await _secureStorage.read(key: _usernameKey))?.trim();
    final password = await _secureStorage.read(key: _passwordKey);
    if (username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }

    return DedicatedHostCredentials(username: username, password: password);
  }

  Future<void> saveCredentials({
    required String username,
    required String password,
  }) async {
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty || password.isEmpty) {
      throw const DedicatedHostConfigException(
        'EA/Maxima username and password are required.',
      );
    }

    await _secureStorage.write(key: _usernameKey, value: cleanUsername);
    await _secureStorage.write(key: _passwordKey, value: password);
  }

  Future<void> saveLicenseSettings({
    required DedicatedHostLicenseMode mode,
    required String? denuvoToken,
    required bool preserveDenuvoToken,
  }) async {
    licenseMode = mode;
    final cleanToken = denuvoToken?.trim() ?? '';
    if (cleanToken.isNotEmpty) {
      await _secureStorage.write(key: _denuvoTokenKey, value: cleanToken);
      return;
    }

    if (!preserveDenuvoToken) {
      await _secureStorage.delete(key: _denuvoTokenKey);
    }
  }

  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: _usernameKey);
    await _secureStorage.delete(key: _passwordKey);
  }

  Future<void> clearDenuvoToken() async {
    await _secureStorage.delete(key: _denuvoTokenKey);
  }

  Future<bool> isLaunchConfigured() async {
    try {
      await resolveLaunchConfig();
      return true;
    } on DedicatedHostConfigException {
      return false;
    }
  }

  Future<List<String>> missingLaunchRequirements() async {
    final missing = <String>[];
    if (!_validFile(gamePath)) {
      missing.add('Battlefront II executable path');
    }
    try {
      resolveRuntimeLayout();
    } on DedicatedHostConfigException {
      missing.add('Dedicated runtime package');
    }
    return missing;
  }

  Future<DedicatedHostLaunchConfig> resolveLaunchConfig() async {
    final resolvedGamePath = gamePath;
    if (!_validFile(resolvedGamePath)) {
      throw const DedicatedHostConfigException(
        'Battlefront II executable is not configured. Open Settings > '
        'Accounts & Updates > BFII Dedicated Host and select '
        'starwarsbattlefrontii.exe.',
      );
    }

    return DedicatedHostLaunchConfig(
      gamePath: resolvedGamePath,
      runtime: resolveRuntimeLayout(),
      licenseMode: licenseMode,
      denuvoToken: await readDenuvoToken(),
    );
  }

  DedicatedHostRuntimeLayout resolveRuntimeLayout() {
    final configuredRoot = runtimeRoot;
    final roots = <String>[
      if (Platform.environment['KYBER_DEDICATED_RUNTIME_ROOT']?.trim()
          case final envRoot? when envRoot.isNotEmpty)
        envRoot,
      if (configuredRoot.isNotEmpty) configuredRoot,
      ..._runtimeRootsFromExecutable(),
      ..._runtimeRootsFromDevelopmentTree(),
    ];

    for (final root in _uniqueExistingDirectories(roots)) {
      final packageLayout = _packageLayout(root);
      if (_validRuntime(packageLayout)) {
        return packageLayout;
      }

      final devLayout = _developmentLayout(root);
      if (_validRuntime(devLayout)) {
        return devLayout;
      }
    }

    throw const DedicatedHostConfigException(
      'Dedicated runtime package was not found. Shipping builds must include '
      'scripts/run-dedicated.cmd, cli_bundle, and module_runtime under '
      'dedicated_runtime.',
    );
  }

  String? detectGamePath() {
    for (final candidate in _gamePathCandidates()) {
      if (_validFile(candidate)) {
        return candidate;
      }
    }

    return null;
  }

  String? detectRuntimeRoot() {
    try {
      return resolveRuntimeLayout().rootPath;
    } on DedicatedHostConfigException {
      return null;
    }
  }

  Iterable<String> _runtimeRootsFromExecutable() sync* {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    yield p.join(exeDir, 'dedicated_runtime');
    yield exeDir;
    yield p.normalize(p.join(exeDir, '..', 'dedicated_runtime'));
  }

  Iterable<String> _runtimeRootsFromDevelopmentTree() sync* {
    for (final start in [
      Directory.current.path,
      File(Platform.resolvedExecutable).parent.path,
    ]) {
      var dir = Directory(start);
      while (true) {
        if (File(
          p.join(dir.path, 'scripts', 'run-dedicated.ps1'),
        ).existsSync()) {
          yield dir.path;
        }

        final parent = dir.parent;
        if (parent.path == dir.path) {
          break;
        }
        dir = parent;
      }
    }
  }

  DedicatedHostRuntimeLayout _packageLayout(String root) {
    return DedicatedHostRuntimeLayout(
      rootPath: root,
      commandPath: p.join(root, 'scripts', 'run-dedicated.cmd'),
      scriptPath: p.join(root, 'scripts', 'run-dedicated.ps1'),
      cliExePath: p.join(
        root,
        'cli_bundle',
        'bundle',
        'bin',
        'kyber_cli.exe',
      ),
      modulePath: p.join(root, 'module_runtime'),
      workingDirectory: root,
    );
  }

  DedicatedHostRuntimeLayout _developmentLayout(String root) {
    return DedicatedHostRuntimeLayout(
      rootPath: root,
      commandPath: p.join(root, 'scripts', 'run-dedicated.cmd'),
      scriptPath: p.join(root, 'scripts', 'run-dedicated.ps1'),
      cliExePath: p.join(
        root,
        'CLI',
        'dev_build',
        'cli_bundle',
        'bundle',
        'bin',
        'kyber_cli.exe',
      ),
      modulePath: p.join(root, 'CLI', 'dev_build', 'module_runtime'),
      workingDirectory: root,
    );
  }

  bool _validRuntime(DedicatedHostRuntimeLayout layout) {
    return _validFile(layout.commandPath) &&
        _validFile(layout.scriptPath) &&
        _validFile(layout.cliExePath) &&
        _validFile(
          p.join(
            p.dirname(p.dirname(layout.cliExePath)),
            'lib',
            'rust_lib.dll',
          ),
        ) &&
        _validFile(p.join(layout.modulePath, 'Kyber.dll')) &&
        _validFile(p.join(layout.modulePath, 'vivoxsdk.dll'));
  }

  Iterable<String> _uniqueExistingDirectories(Iterable<String> roots) sync* {
    final seen = <String>{};
    for (final root in roots) {
      final cleanRoot = root.trim();
      if (cleanRoot.isEmpty) {
        continue;
      }

      final normalized = p.normalize(cleanRoot);
      if (!seen.add(normalized.toLowerCase())) {
        continue;
      }

      if (Directory(normalized).existsSync()) {
        yield normalized;
      }
    }
  }

  Iterable<String> _gamePathCandidates() sync* {
    final configured = gamePath;
    if (configured.isNotEmpty) {
      yield configured;
    }

    final envPath = Platform.environment['KYBER_GAME_PATH']?.trim();
    if (envPath != null && envPath.isNotEmpty) {
      yield envPath;
    }

    final programFiles = Platform.environment['ProgramFiles'];
    final programFilesX86 = Platform.environment['ProgramFiles(x86)'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final candidates = <String>[
      if (programFiles != null)
        p.join(
          programFiles,
          'EA Games',
          'STAR WARS Battlefront II',
          'starwarsbattlefrontii.exe',
        ),
      if (programFilesX86 != null)
        p.join(
          programFilesX86,
          'Origin Games',
          'STAR WARS Battlefront II',
          'starwarsbattlefrontii.exe',
        ),
      if (programFilesX86 != null)
        p.join(
          programFilesX86,
          'Steam',
          'steamapps',
          'common',
          'STAR WARS Battlefront II',
          'starwarsbattlefrontii.exe',
        ),
      if (localAppData != null)
        p.join(
          localAppData,
          'Programs',
          'EA Games',
          'STAR WARS Battlefront II',
          'starwarsbattlefrontii.exe',
        ),
      r'D:\Games\STAR WARS Battlefront II\starwarsbattlefrontii.exe',
    ];

    yield* candidates;
    yield* _steamLibraryGameCandidates();
  }

  Iterable<String> _steamLibraryGameCandidates() sync* {
    final programFilesX86 = Platform.environment['ProgramFiles(x86)'];
    if (programFilesX86 == null) {
      return;
    }

    final libraryFile = File(
      p.join(programFilesX86, 'Steam', 'steamapps', 'libraryfolders.vdf'),
    );
    if (!libraryFile.existsSync()) {
      return;
    }

    final content = libraryFile.readAsStringSync();
    final pathPattern = RegExp(r'"path"\s+"([^"]+)"');
    for (final match in pathPattern.allMatches(content)) {
      final libraryPath = match.group(1)?.replaceAll(r'\\', r'\');
      if (libraryPath == null || libraryPath.isEmpty) {
        continue;
      }

      yield p.join(
        libraryPath,
        'steamapps',
        'common',
        'STAR WARS Battlefront II',
        'starwarsbattlefrontii.exe',
      );
    }
  }

  bool _validFile(String path) {
    return path.trim().isNotEmpty && File(path).existsSync();
  }
}
