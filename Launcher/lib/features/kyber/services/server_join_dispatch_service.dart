import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/features/kyber/services/server_join_plan_service.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_start_game_dialog.dart';
import 'package:kyber_launcher/features/maxima/services/maxima_instance_service.dart';
import 'package:kyber_launcher/features/mod_collections/providers/mod_collection_cubit.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:logging/logging.dart';

class ServerJoinDispatchService {
  ServerJoinDispatchService({Logger? logger})
    : _logger = logger ?? Logger('server_join_dispatch');

  final Logger _logger;

  Future<void> dispatch({
    required ServerJoinPlan plan,
    required ModCollectionMetaData collection,
  }) async {
    final clientInstance = sl.get<MaximaInstanceService>().clientInstance;
    if (clientInstance == null) {
      _logger.info('LAN_STAGE[join.dispatch.launch_game]');
      await showKyberDialog(
        context: navigatorKey.currentContext!,
        builder: (_) => MaximaStartGameDialog(
          mods: collection.getLocalMods().whereType<FrostyMod>().toList(),
          initializeRequest: InitializeRequest(
            joinServer: plan.request,
            modData: collection.getInterfaceData(),
          ),
        ),
      );
      return;
    }

    _logger.info('LAN_STAGE[join.dispatch.live_rpc]');
    await clientInstance.clientService.client.joinServer(plan.request);
  }
}
