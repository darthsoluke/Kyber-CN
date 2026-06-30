import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';

final class DedicatedServerModConfig {
  const DedicatedServerModConfig({
    required this.modData,
    required this.gameplayMods,
  });

  final ModData? modData;
  final List<FrostyMod> gameplayMods;

  bool get hasGameplayMods => gameplayMods.isNotEmpty;
}
