import 'dart:io';

class FileHelper {
  FileHelper._();

  static Directory? _getConfiguredModuleDirectory() {
    final configuredPath = Platform.environment['KYBER_MODULE_DIR'];
    if (configuredPath == null || configuredPath.trim().isEmpty) {
      return null;
    }

    return Directory(configuredPath);
  }

  static Directory? _getExecutableScopedModuleDirectory() {
    final executablePath = Platform.resolvedExecutable.toLowerCase();
    const runtimeExecutables = <String>[
      r'\dart.exe',
      r'\dartaotruntime.exe',
      r'\flutter_tester.exe',
      '/dart',
      '/dartaotruntime',
      '/flutter_tester',
    ];

    if (runtimeExecutables.any(executablePath.endsWith)) {
      return null;
    }

    final executableDir = File(Platform.resolvedExecutable).parent.path;
    return Directory('${executableDir}${Platform.pathSeparator}module');
  }

  static Directory _getDevelopmentModuleDirectory() {
    return Directory(
        '${Directory.current.path}${Platform.pathSeparator}module');
  }

  static Directory getLauncherDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers\\Kyber\\Launcher'
          : '${Platform.environment['HOME']}/.local/share/kyber/launcher',
    );

    return baseDir;
  }

  static Directory getArmchairDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers'
          : '${Platform.environment['HOME']}/.local/share/kyber',
    );

    return baseDir;
  }

  static Directory getModuleDirectory() {
    final configuredDir = _getConfiguredModuleDirectory();
    if (configuredDir != null) {
      return configuredDir;
    }

    final executableScopedDir = _getExecutableScopedModuleDirectory();
    if (executableScopedDir != null) {
      return executableScopedDir;
    }

    return _getDevelopmentModuleDirectory();
  }

  static Directory getModsDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers\\Kyber\\Mods'
          : '${Platform.environment['HOME']}/.local/share/kyber/mods',
    );

    return baseDir;
  }

  static Directory getCollectionDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers\\Kyber\\Mods'
          : '${Platform.environment['HOME']}/.local/share/kyber/mods',
    );

    return baseDir;
  }
}
