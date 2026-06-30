import 'package:collection/collection.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/server_browser/helpers/lan_server_helper.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';

class ServerJoinPlan {
  const ServerJoinPlan({
    required this.request,
    required this.isLanServer,
    required this.apiBackedJoin,
    this.selectedProxy,
    this.proxyFallback,
  });

  final JoinServerRequest request;
  final bool isLanServer;
  final bool apiBackedJoin;
  final ProxyInfo? selectedProxy;
  final ServerJoinProxyFallback? proxyFallback;
}

class ServerJoinProxyFallback {
  const ServerJoinProxyFallback({
    required this.requestedProxyId,
    required this.selectedProxyName,
  });

  final String requestedProxyId;
  final String selectedProxyName;
}

class ServerJoinRejectedException implements Exception {
  const ServerJoinRejectedException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ServerJoinPlanService {
  ServerJoinPlanService({
    KyberGRPCService? kyber,
    Logger? logger,
  }) : _kyber = kyber ?? sl.get<KyberGRPCService>(),
       _logger = logger ?? Logger('server_join_plan');

  final KyberGRPCService _kyber;
  final Logger _logger;

  Future<ServerJoinPlan> build({
    required Server server,
    required Iterable<ProxyInfo> proxies,
    String preferredProxyId = '',
    bool? spectator,
    String? password,
  }) async {
    final isLanServer = LanServerHelper.isLanServer(server);
    final apiBackedJoin = LanServerHelper.hasApiBackedJoin(server);
    final passwordValue = password ?? '';

    _logger.info(
      'LAN_STAGE[join.classify] '
      'id=${server.id} isLan=$isLanServer '
      'apiBackedJoin=$apiBackedJoin '
      'joinable=${LanServerHelper.isJoinable(server)} '
      'ip=${server.ip} port=${server.port} '
      'requiresProxy=${server.requiresProxy} '
      'passwordPresent=${passwordValue.isNotEmpty} '
      'spectator=${spectator ?? false}',
    );

    final plan = isLanServer
        ? await _buildLanPlan(
            server,
            apiBackedJoin: apiBackedJoin,
            spectator: spectator,
            password: passwordValue,
          )
        : await _buildOfficialPlan(
            server,
            proxies: proxies,
            preferredProxyId: preferredProxyId,
            spectator: spectator,
            password: passwordValue,
          );

    _logger.info(
      'LAN_STAGE[join.request.built] '
      'id=${plan.request.id} ip=${plan.request.ip} '
      'port=${plan.request.port} '
      'type=${plan.request.type.name} '
      'joinTokenPresent=${plan.request.joinToken.isNotEmpty} '
      'passwordPresent=${plan.request.password.isNotEmpty} '
      'spectate=${plan.request.spectate}',
    );

    return plan;
  }

  Future<ServerJoinPlan> _buildLanPlan(
    Server server, {
    required bool apiBackedJoin,
    required bool? spectator,
    required String password,
  }) async {
    if (!LanServerHelper.isJoinable(server)) {
      _logger.warning('LAN_STAGE[join.lan.unavailable] id=${server.id}');
      throw const ServerJoinRejectedException(
        'This LAN server is running in online mode but is not registered '
        'with Kyber.',
      );
    }

    var joinToken = '';
    var joinServerId = server.id;
    if (apiBackedJoin) {
      _logger.info('LAN_STAGE[join.lan.api_token.request] id=${server.id}');
      final tokenResponse = await _kyber.clientServerClient.createJoinToken(
        .new(server: server.id, password: password),
      );
      joinToken = tokenResponse.token;
      _logger.info(
        'LAN_STAGE[join.lan.api_token.received] '
        'id=${server.id} joinTokenPresent=${joinToken.isNotEmpty}',
      );
    } else {
      joinServerId = server.id.isEmpty
          ? LanServerHelper.makeSyntheticId(server.ip, server.port)
          : server.id;
      _logger.info(
        'LAN_STAGE[join.lan.direct] '
        'id=$joinServerId ip=${server.ip} port=${server.port}',
      );
    }

    return ServerJoinPlan(
      isLanServer: true,
      apiBackedJoin: apiBackedJoin,
      request: JoinServerRequest(
        id: joinServerId,
        ip: server.ip,
        port: server.port,
        type: .DIRECT,
        spectate: spectator ?? false,
        joinToken: joinToken,
        password: password,
      ),
    );
  }

  Future<ServerJoinPlan> _buildOfficialPlan(
    Server server, {
    required Iterable<ProxyInfo> proxies,
    required String preferredProxyId,
    required bool? spectator,
    required String password,
  }) async {
    var serverIp = server.ip;
    final currentIp = await KyberNetworkHelper.getCurrentIpAddress();
    if (serverIp == currentIp) {
      serverIp = '127.0.0.1';
    }
    _logger.info(
      'LAN_STAGE[join.official.target] '
      'id=${server.id} originalIp=${server.ip} resolvedIp=$serverIp '
      'selfIpMatched=${server.ip == currentIp}',
    );

    ProxyInfo? selectedProxy;
    ServerJoinProxyFallback? proxyFallback;
    if (server.requiresProxy) {
      (selectedProxy, proxyFallback) = _selectProxy(
        proxies: proxies,
        preferredProxyId: preferredProxyId,
      );
      _logger.info(
        'LAN_STAGE[join.official.proxy.selected] '
        'name=${selectedProxy.name} ip=${selectedProxy.ip} '
        'requiresProxy=${server.requiresProxy}',
      );
      serverIp = selectedProxy.ip;
    }

    _logger.info('LAN_STAGE[join.official.api_token.request] id=${server.id}');
    final tokenResponse = await _kyber.clientServerClient.createJoinToken(
      .new(server: server.id, password: password),
    );
    final joinToken = tokenResponse.token;
    _logger.info(
      'LAN_STAGE[join.official.api_token.received] '
      'id=${server.id} joinTokenPresent=${joinToken.isNotEmpty}',
    );

    return ServerJoinPlan(
      isLanServer: false,
      apiBackedJoin: true,
      selectedProxy: selectedProxy,
      proxyFallback: proxyFallback,
      request: JoinServerRequest(
        id: server.id,
        ip: serverIp,
        port: server.requiresProxy
            ? LanServerHelper.defaultGamePort
            : server.port,
        type: server.requiresProxy ? .PROXIED : .DIRECT,
        spectate: spectator ?? false,
        joinToken: joinToken,
        password: password,
      ),
    );
  }

  (ProxyInfo, ServerJoinProxyFallback?) _selectProxy({
    required Iterable<ProxyInfo> proxies,
    required String preferredProxyId,
  }) {
    final proxyList = proxies.toList();
    var selectedProxy = proxyList.firstWhereOrNull(
      (proxy) => proxy.id == preferredProxyId,
    );
    if (selectedProxy != null) {
      return (selectedProxy, null);
    }

    selectedProxy = proxyList.firstOrNull;
    _logger.warning(
      'No proxy selected, using ${selectedProxy?.name} instead',
    );
    if (selectedProxy == null) {
      _logger.severe('No proxy available');
      throw const ServerJoinRejectedException('No proxy available');
    }

    return (
      selectedProxy,
      ServerJoinProxyFallback(
        requestedProxyId: preferredProxyId,
        selectedProxyName: selectedProxy.name,
      ),
    );
  }
}
