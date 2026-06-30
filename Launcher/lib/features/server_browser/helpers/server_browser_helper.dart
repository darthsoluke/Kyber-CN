import 'package:collection/collection.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/maxima/services/maxima_instance_service.dart';
import 'package:kyber_launcher/features/mods/helper/mod_helper.dart';
import 'package:kyber_launcher/features/server_browser/helpers/lan_server_helper.dart';
import 'package:kyber_launcher/features/server_browser/models/server_filter.dart';
import 'package:kyber_launcher/features/server_browser/providers/server_browser_cubit.dart';
import 'package:kyber_launcher/injection_container.dart';

class ServerBrowserHelper {
  static bool canJoinServer(
    BuildContext context, {
    required Server server,
    bool ignoreInstalled = false,
  }) {
    if (LanServerHelper.isLanServer(server) &&
        !LanServerHelper.isJoinable(server)) {
      return false;
    }

    if (server.isFull(context)) {
      return false;
    }

    final installed = server.mods.every(
      (m) => ModHelper.isInstalled(m.name, m.version, ignoreCorrupted: true),
    );
    final gameInstance = sl.get<MaximaInstanceService>().clientInstance;
    final gameRunning = gameInstance != null;

    if (!gameRunning) {
      return installed ||
          ignoreInstalled &&
              context.read<ServerBrowserCubit>().state.joiningServer == null;
    }

    final instanceGameplayMods = ModHelper.getGameplayMods(gameInstance.mods);

    if (instanceGameplayMods.isEmpty && server.mods.isNotEmpty ||
        server.mods.isEmpty && instanceGameplayMods.isNotEmpty) {
      return false;
    }

    final mappedServerMods = server.mods
        .map((e) => '${e.name}@${e.version}')
        .toList();
    final mappedInstanceMods = instanceGameplayMods
        .map((e) => '${e.details.name}@${e.details.version}')
        .toList();
    return const ListEquality<String>().equals(
      mappedServerMods,
      mappedInstanceMods,
    );
  }
}
