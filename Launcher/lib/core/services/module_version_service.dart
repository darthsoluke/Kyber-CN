import 'dart:io';

import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/gen/rust/api/archive.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/main.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rhttp/rhttp.dart';
import 'package:win32/win32.dart';
import 'package:win32_registry/win32_registry.dart';

const _launcherInstallerKey =
    r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\KyberLauncher_is1';

String _bundledModulePath() =>
    join(dirname(Platform.resolvedExecutable), 'module');

enum VersionModule {
  //launcher,
  module,
  installer,
}

extension VersionModuleExtension on VersionModule {
  Future<String?> getCurrentVersion() async {
    switch (this) {
      case VersionModule.module:
        final x = File(join(_bundledModulePath(), 'VERSION'));

        if (!x.existsSync()) {
          return null;
        }

        return x.readAsStringSync();
      case VersionModule.installer:
        final info = await PackageInfo.fromPlatform();

        return '${info.version}+${info.buildNumber}';
    }
  }

  Future<String> getDownloadDir() async {
    switch (this) {
      case VersionModule.installer:
        final tmpDir = await getTemporaryDirectory();

        return join(
          tmpDir.path,
          'kyber_launcher_${DateTime.now().millisecondsSinceEpoch}',
        );
      case VersionModule.module:
        return _bundledModulePath();
    }
  }

  Future<void> setReleaseChannel(String channel) async {
    await box.put('${name}_release_channel', channel);
  }

  String get releaseChannel {
    return box.get('${name}_release_channel') as String? ?? 'stable';
  }

  List<String> get requiredFiles {
    switch (this) {
      case VersionModule.installer:
        return [];
      case VersionModule.module:
        final modulePath = _bundledModulePath();
        return [
          '$modulePath/vivoxsdk.dll',
          '$modulePath/VanillaBundleAggregation.kb',
          '$modulePath/Kyber.dll',
          '$modulePath/ca_root.pem',
        ];
    }
  }

  String get name {
    switch (this) {
      case VersionModule.installer:
        return 'kyber-installer-win64';
      case VersionModule.module:
        return 'kyber-module';
    }
  }
}

class ModuleVersionService {
  final _logger = Logger('version_service');

  Directory get _bundledModuleDirectory =>
      Directory(join(dirname(Platform.resolvedExecutable), 'module'));
  File get _bundledModuleArchive =>
      File(join(_bundledModuleDirectory.path, 'kyber-module.zip'));

  void _tryClearReadOnly(String fileOrDirPath) {
    if (!Platform.isWindows) {
      return;
    }

    final pathPtr = fileOrDirPath.toNativeUtf16();
    try {
      final attrs = GetFileAttributes(pathPtr);
      // INVALID_FILE_ATTRIBUTES (0xFFFFFFFF)
      if (attrs == 0xFFFFFFFF) {
        return;
      }

      if ((attrs & FILE_ATTRIBUTE_READONLY) != 0) {
        SetFileAttributes(pathPtr, attrs & ~FILE_ATTRIBUTE_READONLY);
      }
    } catch (_) {
      // Best-effort only.
    } finally {
      calloc.free(pathPtr);
    }
  }

  void _prepareModuleDirectoryForOverwrite(
    String modulePath, {
    required bool includeModFiles,
  }) {
    _tryClearReadOnly(modulePath);
    for (final name in [
      'Kyber.dll',
      'vivoxsdk.dll',
      'ca_root.pem',
      if (includeModFiles) 'VanillaBundleAggregation.kb',
      'VERSION',
      'kyber-module.zip',
    ]) {
      final path = join(modulePath, name);
      if (File(path).existsSync()) {
        _tryClearReadOnly(path);
      }
    }
  }

  bool _hasModuleFiles(
    String modulePath, {
    bool requireModSupport = true,
  }) {
    final required = <String>[
      join(modulePath, 'Kyber.dll'),
      join(modulePath, 'vivoxsdk.dll'),
      join(modulePath, 'ca_root.pem'),
      if (requireModSupport) join(modulePath, 'VanillaBundleAggregation.kb'),
    ];

    return required.every((path) => File(path).existsSync());
  }

  String? _readModuleVersionSync(String modulePath) {
    final versionFile = File(join(modulePath, 'VERSION'));
    if (!versionFile.existsSync()) {
      return null;
    }

    final value = versionFile.readAsStringSync().trim();
    return value.isEmpty ? null : value;
  }

  bool hasBundledModule({bool requireModSupport = true}) {
    return _hasModuleFiles(
          _bundledModuleDirectory.path,
          requireModSupport: requireModSupport,
        ) ||
        _bundledModuleArchive.existsSync();
  }

  Future<bool> installBundledModuleIfAvailable({
    bool requireModSupport = true,
  }) async {
    final sourceDir = _bundledModuleDirectory;
    if (!sourceDir.existsSync()) {
      return false;
    }

    if (!_hasModuleFiles(
          sourceDir.path,
          requireModSupport: requireModSupport,
        ) &&
        !_bundledModuleArchive.existsSync()) {
      return false;
    }

    if (!sourceDir.existsSync()) {
      sourceDir.createSync(recursive: true);
    }

    if (_hasModuleFiles(
      sourceDir.path,
      requireModSupport: requireModSupport,
    )) {
      return true;
    }

    if (_bundledModuleArchive.existsSync()) {
      _prepareModuleDirectoryForOverwrite(
        sourceDir.path,
        includeModFiles: requireModSupport,
      );
      await extract(
        filePath: _bundledModuleArchive.path,
        targetDir: sourceDir.path,
      );
      final bundledVersion = _readModuleVersionSync(sourceDir.path);
      if (bundledVersion != null) {
        File(join(sourceDir.path, 'VERSION')).writeAsStringSync(bundledVersion);
      }
      _prepareModuleDirectoryForOverwrite(
        sourceDir.path,
        includeModFiles: requireModSupport,
      );
    }

    final prepared = _hasModuleFiles(
      sourceDir.path,
      requireModSupport: requireModSupport,
    );
    if (prepared) {
      _logger.info('Prepared bundled module in ${sourceDir.path}');
    }

    return prepared;
  }

  bool hasLaunchableModule({bool requireModSupport = true}) {
    return _hasModuleFiles(
      _bundledModuleDirectory.path,
      requireModSupport: requireModSupport,
    );
  }

  Future<String> getLaunchModuleDirectory({
    bool requireModSupport = true,
  }) async {
    if (await installBundledModuleIfAvailable(
      requireModSupport: requireModSupport,
    )) {
      return _bundledModuleDirectory.path;
    }

    return _bundledModuleDirectory.path;
  }

  Future<String> getRuntimeVersion({
    VersionModule module = VersionModule.module,
    String? moduleDirectory,
  }) async {
    if (module == VersionModule.module && moduleDirectory != null) {
      final versionFile = File(join(moduleDirectory, 'VERSION'));
      if (versionFile.existsSync()) {
        final bundledVersion = versionFile.readAsStringSync().trim();
        if (bundledVersion.isNotEmpty) {
          return bundledVersion;
        }
      }
    }

    final currentVersion = await module.getCurrentVersion();
    if (currentVersion != null && currentVersion.isNotEmpty) {
      return currentVersion;
    }

    final cachedVersion = box.get(module.name) as String?;
    if (cachedVersion != null && cachedVersion.isNotEmpty) {
      return cachedVersion;
    }

    return 'local';
  }

  bool isStandalone() {
    RegistryKey? key;
    try {
      key = Registry.openPath(
        RegistryHive.localMachine,
        path: _launcherInstallerKey,
      );

      final installationPath = key.getStringValue('InstallLocation');
      if (installationPath == null) {
        return true;
      }

      return normalize(installationPath) !=
          dirname(Platform.resolvedExecutable);
    } on WindowsException catch (_) {
      return true;
    } catch (e) {
      _logger.warning('Failed to check if standalone: $e');
      return false;
    } finally {
      key?.close();
    }
  }

  Future<bool> checkChannel({
    required VersionModule module,
    required String channel,
  }) async {
    if (module == VersionModule.installer) {
      final version = await getLatestLauncherVersion(channel);
      return version != null;
    }

    final rq = ServiceVersionsRequest(id: module.name, channel: channel);
    final versions = await sl.get<KyberGRPCService>().launcherClient.versions(
      rq,
    );
    return versions.versions.isNotEmpty &&
        versions.versions.firstWhereOrNull((x) => x.isLatest) != null;
  }

  Future<bool> updateAvailable({
    required VersionModule module,
    String? channel,
    KyberGRPCService? service,
  }) async {
    if (Platform.isMacOS && module == VersionModule.installer) {
      return false;
    }

    if ((kDebugMode || kProfileMode) && module == VersionModule.installer) {
      return false;
    }

    channel ??= module.releaseChannel;
    final rq = ServiceVersionsRequest(id: module.name, channel: channel);
    final versions = await (service ?? sl.get<KyberGRPCService>())
        .launcherClient
        .versions(rq);

    final currentVersion = await module.getCurrentVersion();
    final latestVersion = versions.versions.firstWhereOrNull((x) => x.isLatest);
    if (currentVersion == null) {
      _logger.info('No version found for ${module.name}.');
      return true;
    }

    if (latestVersion == null) {
      _logger.info(
        'No latest version found for ${module.name}. Switching to stable.',
      );
      await module.setReleaseChannel('stable');
      return true;
    }

    late bool updateAvailable;
    if (module == VersionModule.installer) {
      final latestVersion = await getLatestLauncherVersion();
      if (latestVersion == 'DISCONTINUED' || latestVersion == null) {
        _logger.info(
          'The branch ${VersionModule.installer.releaseChannel} has been discontinued. Switching to main.',
        );
        await VersionModule.installer.setReleaseChannel('stable');
        return true;
      }

      updateAvailable = latestVersion != currentVersion;
    } else {
      updateAvailable = latestVersion.version != currentVersion;
    }

    if (updateAvailable) {
      _logger.info(
        'New version available for ${module.name}: ${latestVersion.version}',
      );
      return true;
    }

    if (module.requiredFiles.any((x) => !File(x).existsSync())) {
      _logger.info('Required files missing for ${module.name}.');
      return true;
    }

    return false;
  }

  Future<void> updateVersion({
    required VersionModule module,
    String? channel,
    String? token,
    KyberGRPCService? service,
    void Function(int, int)? onProgress,
  }) async {
    if (!kReleaseMode && module == VersionModule.installer) {
      return;
    }

    final x = service ?? sl.get<KyberGRPCService>();
    channel ??= module.releaseChannel;
    final versions = await x.launcherClient.versions(
      ServiceVersionsRequest(id: module.name, channel: channel),
    );
    final latestVersion = versions.versions
        .where((x) => x.isLatest)
        .firstOrNull;

    if (latestVersion == null) {
      NotificationService.showNotification(
        message:
            'No latest version found for "${module.name}" on channel "$channel".',
      );
      _logger.warning('No latest version found for ${module.name}');
      return;
    }

    if (module == VersionModule.installer && isStandalone()) {
      NotificationService.showNotification(
        message:
            'The standalone version of the Launcher cannot be automatically updated.',
      );
      _logger.warning(
        'The standalone version of the Launcher cannot be automatically updated.',
      );
      return;
    }

    _logger.info('Updating ${module.name} to version ${latestVersion.version}');

    final download = await x.launcherClient.downloadUrl(
      ServiceVersionDownloadUrlRequest(
        id: module.name,
        version: latestVersion.version,
        channel: channel,
      ),
    );
    final filename = basename(download.url).split('?').first;
    final downloadDir = await module.getDownloadDir();
    final downloadPath = join(downloadDir, filename);
    final downloadDirectory = Directory(downloadDir);

    if (!downloadDirectory.existsSync()) {
      downloadDirectory.createSync(recursive: true);
    }

    _logger.fine('Downloading to $downloadPath');

    final file = File(downloadPath);
    if (file.existsSync()) {
      file.deleteSync();
    }

    final raf = file.openSync(mode: FileMode.write);

    try {
      final stream = await Rhttp.getStream(
        download.url,
        onReceiveProgress: onProgress,
      );

      await stream.body.forEach(raf.writeFromSync);
    } finally {
      raf.closeSync();
    }

    _logger.fine('Extracting artifact...');

    if (module == VersionModule.module) {
      _prepareModuleDirectoryForOverwrite(downloadDir, includeModFiles: true);
    }
    await extract(filePath: downloadPath, targetDir: downloadDir);
    if (module == VersionModule.module) {
      _prepareModuleDirectoryForOverwrite(downloadDir, includeModFiles: true);
    }

    try {
      File(downloadPath).deleteSync();
    } catch (_) {}

    await box.put(module.name, latestVersion.version);
    if (module == VersionModule.installer) {
      await Process.run('sc', ['stop', 'MaximaBackgroundService']);
      await Process.run(join(downloadDir, 'KyberLauncherInstaller.exe'), [
        '/VERYSILENT',
        '/FORCECLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
      ], runInShell: true);

      exit(0);
    } else {
      if (module == VersionModule.module) {
        File(join(downloadDir, 'VERSION')).writeAsStringSync(
          latestVersion.version,
        );
      }
    }

    _logger.info('Updated ${module.name} to version ${latestVersion.version}');
  }

  Future<String?> getLatestLauncherVersion([String? releaseChannel]) async {
    try {
      final rawVersion = await Rhttp.getText(
        'https://s3.kyber.gg/artifacts/launcher-versions/${releaseChannel ?? VersionModule.installer.releaseChannel}/latest-version',
      );

      return rawVersion.body.split(Platform.lineTerminator).first;
    } catch (e) {
      return null;
    }
  }
}
