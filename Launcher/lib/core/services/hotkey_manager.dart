import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/maxima/services/maxima_instance_service.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';
import 'package:super_hot_key/super_hot_key.dart';
import 'package:window_manager/window_manager.dart';

class HotKeyService {
  static final _logger = Logger('hotkey_service');
  static HotKey? _ingameHotKey;

  static Future<void> registerIngameHotKey() async {
    if (!Preferences.general.ingameHotkeyEnabled) {
      return;
    }

    _logger.info('Registering ingame hotkey');
    try {
      _ingameHotKey = await HotKey.create(
        definition: HotKeyDefinition(key: PhysicalKeyboardKey.insert),
        onPressed: _onIngameHotKey,
      );
    } catch (e, s) {
      var errorMessage = 'Unknown error';

      if (e is PlatformException) {
        errorMessage = e.message ?? 'Unknown OS error';
      }

      NotificationService.error(message: errorMessage);
      Logger.root.severe('Failed to register hotkey', e, s);
    }
  }

  static void unregisterIngameHotKey() {
    _logger.info('Unregistering ingame hotkey');
    _ingameHotKey?.dispose();
  }

  static Future<void> _onIngameHotKey() async {
    if (await windowManager.isFocused()) {
      return;
    }

    final servers = await sl
        .get<KyberGRPCService>()
        .serverManagementClient
        .moderatedServers(Empty());
    final instance = sl.get<MaximaInstanceService>().primaryInstance;
    if (instance == null) {
      _logger.warning('No running game instance found, ignoring hotkey');
      return;
    }

    final state = await instance.clientService.commonClient.getInfo(Empty());

    late String id;
    if (state.hasClient()) {
      id = state.client.serverId;
    } else if (state.hasServer()) {
      id = state.server.id;
    } else {
      _logger.warning('No server or client found, ignoring hotkey');
      return;
    }

    // Open the normal ingame panel for non moderators
    if (!servers.servers.map((s) => s.id).contains(id)) {
      final currentRoute = router
          .routerDelegate
          .currentConfiguration
          .last
          .matchedLocation
          .split('?')
          .first;
      if (currentRoute == '/ingame') {
        return;
      }

      await router.push('/ingame');
      return;
    }

    _logger.info('Ingame hotkey pressed');
    await windowManager.focus();
    router.goNamed('server_host');

    await navigatorKey.currentContext!.read<ModerationCubit>().selectServer(
      serverId: id,
    );
  }
}
