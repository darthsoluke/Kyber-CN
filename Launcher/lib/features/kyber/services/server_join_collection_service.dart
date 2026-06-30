import 'package:collection/collection.dart';
import 'package:kyber/kyber.dart' hide ServerMod;
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/features/mod_collections/providers/mod_collection_cubit.dart';
import 'package:kyber_launcher/features/mods/extensions/frosty_collection_extension.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/injection_container.dart';

class ServerJoinCollectionService {
  ServerJoinCollectionService({ModService? mods})
    : _mods = mods ?? sl.get<ModService>();

  final ModService _mods;

  ModCollectionMetaData build({
    required Server server,
    ModCollectionMetaData? selectedCollection,
  }) {
    final requiredMods = _resolveRequiredMods(server).toList();

    return ModCollectionMetaData(
      title: server.name,
      mods: [
        if (selectedCollection != null &&
            !selectedCollection.containsGameplayMods())
          ...requiredMods,
        if (selectedCollection != null) ...selectedCollection.mods,
      ],
      localId: server.id,
    );
  }

  Iterable<CollectionMod> _resolveRequiredMods(Server server) sync* {
    for (final serverMod in server.mods) {
      final localMod = _mods.mods.firstWhere(
        (mod) =>
            mod.toKyberString() == '${serverMod.name} (${serverMod.version})',
      );

      if (!localMod.isCollection) {
        yield localMod.toCollectionMod();
        continue;
      }

      final collectionMods = localMod.getMods()!.map(
        (filename) => _mods.mods
            .firstWhereOrNull((mod) => mod.filename == filename)
            ?.toCollectionMod(),
      );
      if (collectionMods.contains(null)) {
        throw Exception(
          '"${localMod.details.name}" is corrupted. Please reinstall it',
        );
      }

      yield* collectionMods.whereType<CollectionMod>();
    }
  }
}
