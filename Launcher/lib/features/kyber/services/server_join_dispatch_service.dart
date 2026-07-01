import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/features/kyber/services/server_join_confirmation_service.dart';
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
    final confirmation = ServerJoinConfirmationService();
    final clientInstance = sl.get<MaximaInstanceService>().clientInstance;
    _logger.info(
      'DIRECT_STAGE[join.dispatch.begin] '
      'hasClient=${clientInstance != null} '
      'isLan=${plan.isLanServer} apiBackedJoin=${plan.apiBackedJoin} '
      'id=${plan.request.id} ip=${plan.request.ip}:${plan.request.port} '
      'type=${plan.request.type.name} '
      'joinTokenPresent=${plan.request.joinToken.isNotEmpty} '
      'passwordPresent=${plan.request.password.isNotEmpty} '
      'collectionMods=${collection.mods.length}',
    );
    if (clientInstance == null) {
      _logger.info('LAN_STAGE[join.dispatch.launch_game]');
      final result = await showKyberDialog<MaximaLaunchResult>(
        context: navigatorKey.currentContext!,
        builder: (_) => MaximaStartGameDialog(
          mods: collection.getLocalMods().whereType<FrostyMod>().toList(),
          initializeRequest: InitializeRequest(
            joinServer: plan.request,
            modData: collection.getInterfaceData(),
          ),
        ),
      );
      if (result?.success != true) {
        _logger.warning(
          'DIRECT_STAGE[join.dispatch.launch_game.failed] '
          'message=${result?.message ?? ''}',
        );
        throw StateError(
          result?.message ?? 'BFII launch did not complete successfully.',
        );
      }
      _logger.info('DIRECT_STAGE[join.dispatch.launch_game.done]');
      return;
    }

    _logger.info('LAN_STAGE[join.dispatch.live_rpc]');
    confirmation.resetJoinSignal();
    await clientInstance.clientService.client.joinServer(plan.request);
    _logger.info(
      'DIRECT_STAGE[join.dispatch.live_rpc.sent] pid=${clientInstance.pid}',
    );
    await confirmation.waitForJoin(clientInstance, plan.request);
    _logger.info(
      'DIRECT_STAGE[join.dispatch.live_rpc.confirmed] '
      'pid=${clientInstance.pid}',
    );
  }
}
