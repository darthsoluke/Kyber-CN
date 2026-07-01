import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/features/server_browser/models/server_filter.dart';
import 'package:kyber_launcher/features/server_browser/models/server_list_state.dart';
import 'package:kyber_launcher/features/server_browser/services/lan_server_discovery_service.dart';
import 'package:logging/logging.dart';

const _pageLimit = 12;

class LanServerListCubit extends Cubit<ServerListState> {
  LanServerListCubit({
    LanServerDiscoveryService? discoveryService,
  }) : _discoveryService = discoveryService ?? LanServerDiscoveryService(),
       super(const ServerListInitial()) {
    filter = ServerFilter();
    emit(const ServerListLoading());
    unawaited(loadServers());

    _updateTimer = Timer.periodic(const Duration(seconds: 12), (timer) {
      final route = router.routeInformationProvider.value.uri.toString();
      if (!route.startsWith('/home')) {
        _needsUpdate = true;
        return;
      }

      unawaited(loadServers());
    });
  }

  final LanServerDiscoveryService _discoveryService;
  final Logger _logger = Logger('lan_server_list');

  bool _needsUpdate = false;
  int _page = 1;
  List<Server> _allServers = const <Server>[];
  late Timer _updateTimer;
  Timer? _queryProbeTimer;

  late ServerFilter filter;

  @override
  Future<void> close() async {
    _queryProbeTimer?.cancel();
    _updateTimer.cancel();
    await super.close();
  }

  void checkUpdate() {
    if (_needsUpdate) {
      unawaited(loadServers());
      _needsUpdate = false;
    }
  }

  void setQuery(String value) {
    final query = value.trim();
    final nextFilter = filter.copyWith(query: query.isEmpty ? null : query);
    if (nextFilter == filter) {
      return;
    }

    filter = nextFilter;
    _page = 1;
    _queryProbeTimer?.cancel();
    if (_DirectEndpointQuery.tryParse(query) != null) {
      _queryProbeTimer = Timer(
        const Duration(milliseconds: 450),
        () => unawaited(loadServers()),
      );
    }
    _emitFilteredResults();
  }

  void nextPage() {
    if (state is! ServerListLoaded) {
      return;
    }

    final current = state as ServerListLoaded;
    if (current.page + 1 > current.pages) {
      return;
    }

    _page = current.page + 1;
    _emitFilteredResults();
  }

  void previousPage() {
    if (state is! ServerListLoaded) {
      return;
    }

    final current = state as ServerListLoaded;
    if (current.page - 1 < 1) {
      return;
    }

    _page = current.page - 1;
    _emitFilteredResults();
  }

  Future<void> loadServers() async {
    emit(ServerListLoading(page: _page, pages: state.pages, filter: filter));
    _needsUpdate = false;

    try {
      final servers = await _discoveryService.discover();
      final endpointServer = await _discoverEndpointFromQuery();
      final nextServers = [...servers];
      if (endpointServer != null) {
        nextServers.add(endpointServer);
      }
      _allServers = _mergeServers(nextServers);
      _emitFilteredResults();
    } on Object catch (error) {
      emit(ServerListError(error.toString()));
    }
  }

  Future<Server?> _discoverEndpointFromQuery() async {
    final target = _DirectEndpointQuery.tryParse(filter.query);
    if (target == null) {
      return null;
    }

    try {
      final server = await _discoveryService.discoverHost(host: target.host);
      if (target.port != null && server.port != target.port) {
        _logger.warning(
          'DIRECT_STAGE[list.query_probe.port_mismatch] '
          'queryHost=${target.host} queryPort=${target.port} '
          'metadataPort=${server.port}',
        );
        return null;
      }

      _logger.info(
        'DIRECT_STAGE[list.query_probe.accepted] '
        'host=${target.host} requestedPort=${target.port ?? 0} '
        'serverId=${server.id} serverIp=${server.ip} serverPort=${server.port}',
      );
      return server;
    } on Object catch (error, stackTrace) {
      _logger
        ..warning(
          'DIRECT_STAGE[list.query_probe.failed] '
          'host=${target.host} port=${target.port ?? 0} error=$error',
        )
        ..finer(stackTrace.toString());
      return null;
    }
  }

  void _emitFilteredResults() {
    final filtered = _allServers.where((server) {
      final query = filter.query;
      if (query == null || query.isEmpty) {
        return true;
      }

      final normalized = query.toLowerCase();
      final endpointQuery = _DirectEndpointQuery.tryParse(query);
      if (endpointQuery != null &&
          server.ip.toLowerCase() == endpointQuery.host.toLowerCase() &&
          (endpointQuery.port == null || server.port == endpointQuery.port)) {
        return true;
      }

      return server.name.toLowerCase().contains(normalized) ||
          server.creator.toLowerCase().contains(normalized) ||
          server.ip.toLowerCase().contains(normalized);
    }).toList();

    final pages = (filtered.length / _pageLimit).ceil();
    if (_page > pages && pages > 0) {
      _page = pages;
    }

    final paginated = pages == 0
        ? const <Object>[]
        : filtered.skip((_page - 1) * _pageLimit).take(_pageLimit).toList();

    emit(
      ServerListLoaded(
        servers: paginated,
        page: pages == 0 ? 1 : _page,
        pages: pages == 0 ? 1 : pages,
        filter: filter,
      ),
    );
  }

  List<Server> _mergeServers(List<Server> servers) {
    final merged = <String, Server>{};
    for (final server in servers) {
      merged[server.id] = server;
    }
    return merged.values.toList();
  }
}

class _DirectEndpointQuery {
  const _DirectEndpointQuery({
    required this.host,
    required this.port,
  });

  final String host;
  final int? port;

  static _DirectEndpointQuery? tryParse(String? value) {
    final query = value?.trim() ?? '';
    if (query.isEmpty || query.contains(RegExp(r'\s'))) {
      return null;
    }

    var host = query;
    int? port;
    if (query.contains(':')) {
      final index = query.lastIndexOf(':');
      host = query.substring(0, index).trim();
      port = int.tryParse(query.substring(index + 1).trim());
      if (host.isEmpty || port == null || port <= 0 || port > 65535) {
        return null;
      }
    }

    if (!_looksLikeNetworkHost(host)) {
      return null;
    }

    return _DirectEndpointQuery(host: host, port: port);
  }

  static bool _looksLikeNetworkHost(String host) {
    final lower = host.toLowerCase();
    if (lower == 'localhost' || lower.endsWith('.local')) {
      return true;
    }

    final ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
    if (ipv4.hasMatch(host)) {
      return true;
    }

    return host.contains('.') || host.contains('-');
  }
}
