import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

class PathLauncherService {
  PathLauncherService._();

  static Future<void> openDirectory(String path) async {
    final entityType = await FileSystemEntity.type(path);
    if (entityType == FileSystemEntityType.notFound) {
      throw FileSystemException('Path does not exist', path);
    }

    if (Platform.isWindows) {
      await Process.start('explorer.exe', [path], mode: ProcessStartMode.detached);
      return;
    }

    final uri = entityType == FileSystemEntityType.directory ? Uri.directory(path) : Uri.file(path);
    final opened = await launchUrl(uri);
    if (!opened) {
      throw FileSystemException('Failed to open path', path);
    }
  }
}
