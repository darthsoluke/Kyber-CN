import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart' hide ServerMod;
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_proxy_cubit.dart';
import 'package:kyber_launcher/features/kyber/services/server_join_collection_service.dart';
import 'package:kyber_launcher/features/kyber/services/server_join_dispatch_service.dart';
import 'package:kyber_launcher/features/kyber/services/server_join_plan_service.dart';
import 'package:kyber_launcher/features/server_browser/helpers/lan_server_helper.dart';
import 'package:logging/logging.dart';

class KyberServerHelper {
  static final _logger = Logger('kyber_server_helper');

  static Future<void> joinServer(
    Server server, {
    ModCollectionMetaData? selectedCollection,
    bool? spectator,
    String? password,
  }) async {
    LanServerHelper.remember(server);

    try {
      final tmpCollection = ServerJoinCollectionService().build(
        server: server,
        selectedCollection: selectedCollection,
      );
      final proxyState = navigatorKey.currentContext!
          .read<KyberProxyCubit>()
          .state;
      final plan = await ServerJoinPlanService().build(
        server: server,
        proxies: proxyState.proxies.map((proxy) => proxy.proxy),
        preferredProxyId: Preferences.general.proxy,
        spectator: spectator,
        password: password,
      );

      final proxyFallback = plan.proxyFallback;
      if (proxyFallback != null) {
        NotificationService.showNotification(
          message:
              'Selected Proxy not available, using '
              '${proxyFallback.selectedProxyName} instead',
          severity: InfoBarSeverity.warning,
        );
      }

      await ServerJoinDispatchService().dispatch(
        plan: plan,
        collection: tmpCollection,
      );
    } on GrpcError catch (e) {
      _logger.severe('LAN_STAGE[join.error.grpc] message=${e.message}', e);
      NotificationService.error(
        message: 'Failed to join server: ${e.message}',
      );
    } on Object catch (e) {
      _logger.severe('LAN_STAGE[join.error] error=$e', e);
      NotificationService.error(
        message: 'Failed to join server: $e',
      );
    }
  }
}
