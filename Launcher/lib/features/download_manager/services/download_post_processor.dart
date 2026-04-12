import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:kyber_launcher/features/download_manager/services/archive_extractor.dart';
import 'package:kyber_launcher/features/download_manager/services/platform/download_platform_integration.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';

class DownloadPostProcessor {
  DownloadPostProcessor({
    DownloadPlatformIntegration? platformIntegration,
  }) : _platformIntegration = platformIntegration;

  final DownloadPlatformIntegration? _platformIntegration;
  final Logger _logger = Logger('download_post_processor');

  Future<void> processCompletedDownload(
    TaskStatusUpdate update, {
    ProgressCallback? onProgress,
  }) async {
    if (update.status != TaskStatus.complete) {
      return;
    }

    try {
      _logger.info('Processing completed download: ${update.task.filename}');
      final sourcePath = join(update.task.directory, update.task.filename);
      final processingLock = File('$sourcePath.kyber_processing');
      try {
        await processingLock.create(exclusive: true);
      } on FileSystemException {
        _logger.info(
          'Skipping duplicate post-processing for ${update.task.filename}',
        );
        return;
      }

      await _platformIntegration?.setIndeterminate();

      final extractor = ArchiveExtractor(basePath: update.task.directory);

      if (!extractor.isArchive(update.task.filename)) {
        _logger.info('File is not an archive, skipping extraction');
        return;
      }

      _logger.info('Extracting archive: ${update.task.filename}');
      final result = await extractor.extract(
        update.task.filename,
        onProgress: onProgress,
      );

      if (!result.success) {
        _logger.warning('Extraction failed: ${result.error}');
        return;
      }

      _logger.info('Extraction successful');
    } catch (e, s) {
      _logger.severe('Failed to process completed download', e, s);
    } finally {
      final sourcePath = join(update.task.directory, update.task.filename);
      final processingLock = File('$sourcePath.kyber_processing');
      if (processingLock.existsSync()) {
        await processingLock.delete();
      }
      await _platformIntegration?.clear();
    }
  }
}
