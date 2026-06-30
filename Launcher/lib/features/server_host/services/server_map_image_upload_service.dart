import 'dart:async';

import 'package:fixnum/fixnum.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber/gen/Proto/kyber_common.pb.dart';
import 'package:kyber/kyber.dart' hide ServerMod;
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/i18n/localization.dart';
import 'package:kyber_launcher/core/services/image_helper.dart';
import 'package:kyber_launcher/features/map_rotation/models/map_rotation_entry.dart';
import 'package:kyber_launcher/features/mods/services/level_declaration_service.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:logging/logging.dart';

class ServerMapImageUploadService {
  ServerMapImageUploadService({
    KyberGRPCService? kyber,
    LevelDeclarationService? levels,
    Logger? logger,
  }) : _kyber = kyber ?? sl.get<KyberGRPCService>(),
       _levels = levels ?? sl.get<LevelDeclarationService>(),
       _logger = logger ?? Logger('server_map_image_upload');

  final KyberGRPCService _kyber;
  final LevelDeclarationService _levels;
  final Logger _logger;

  Future<void> uploadMissingHashes(
    BuildContext context, {
    required ModCollectionMetaData collection,
    required Iterable<MapRotationEntry> entries,
  }) async {
    final l10n = context.l10n;
    final imageHashes = _collectImageHashes(collection, entries);
    if (imageHashes.isEmpty) {
      return;
    }

    final result = await _kyber.serverBrowserClient.checkModImages(
      CheckModImagesRequest(
        items: imageHashes.entries
            .map(
              (entry) => CheckModImageItem(
                hash: entry.value,
                level: entry.key.map,
                mode: entry.key.mode,
              ),
            )
            .toList(),
      ),
    );

    final missingHashes = imageHashes.values
        .where((hash) => !result.hashes.contains(hash))
        .toList();
    if (missingHashes.isEmpty) {
      return;
    }

    final images = _buildMissingImages(collection, imageHashes, missingHashes);
    final stopwatch = Stopwatch()..start();
    if (!context.mounted) {
      return;
    }

    await showKyberDialog(
      context: context,
      builder: (dialogContext) {
        unawaited(
          _kyber.serverBrowserClient
              .uploadModImages(UploadModImagesRequest(images: images))
              .then((_) {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              }),
        );

        return KyberContentDialog(
          title: Text(l10n.text('host.mapImages.title')),
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 300),
          content: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    height: 15,
                    width: 15,
                    child: ProgressRing(),
                  ),
                  const SizedBox(width: 15),
                  Text(
                    l10n.text('host.mapImages.uploading'),
                    style: const TextStyle(fontSize: 17),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                l10n.text(
                  'host.mapImages.description',
                  params: {'count': missingHashes.length},
                ),
                style: FluentTheme.of(
                  dialogContext,
                ).typography.body?.copyWith(color: kWhiteColor),
              ),
            ],
          ),
        );
      },
    );

    stopwatch.stop();
    _logger.info(
      'Uploaded ${missingHashes.length} map images '
      'in ${stopwatch.elapsedMilliseconds}ms',
    );
  }

  Map<MapRotationEntry, String> _collectImageHashes(
    ModCollectionMetaData collection,
    Iterable<MapRotationEntry> entries,
  ) {
    final imageHashes = <MapRotationEntry, String>{};
    for (final entry in entries.where((entry) => entry.isCustom)) {
      final imageData = _levels.getMapImage(collection, entry.map);
      if (imageData == null || imageData.isEmpty) {
        continue;
      }

      imageHashes[entry] = ImageHelper.generateHash(imageData);
    }

    return imageHashes;
  }

  List<ModImage> _buildMissingImages(
    ModCollectionMetaData collection,
    Map<MapRotationEntry, String> imageHashes,
    Iterable<String> missingHashes,
  ) {
    final images = <ModImage>[];
    for (final hash in missingHashes) {
      final entry = imageHashes.entries
          .firstWhere(
            (entry) => entry.value == hash,
          )
          .key;
      final imageData = _levels.getMapImage(collection, entry.map);
      final mod = _levels.getModByMap(
        map: entry.map,
        collection: collection,
      );

      images.add(
        ModImage(
          image: imageData,
          level: entry.map,
          mode: entry.mode,
          mod: ServerMod(
            name: mod.details.name,
            version: mod.details.version,
            fileSize: Int64(),
            link: '',
          ),
        ),
      );
    }

    return images;
  }
}
