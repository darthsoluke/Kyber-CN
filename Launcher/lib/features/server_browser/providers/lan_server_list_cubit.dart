import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/features/server_browser/models/server_filter.dart';
import 'package:kyber_launcher/features/server_browser/models/server_list_state.dart';
import 'package:kyber_launcher/features/server_browser/services/lan_server_discovery_service.dart';

const _pageLimit = 12;

class LanServerListCubit extends Cubit<ServerListState> {
  LanServerListCubit({
    LanServerDiscoveryService? discoveryService,
  }) : _discoveryService = discoveryService ?? LanServerDiscoveryService(),
       super(const ServerListInitial()) {
    filter = ServerFilter();
    emit(const ServerListLoading());
    loadServers();

    _updateTimer = Timer.periodic(const Duration(seconds: 12), (timer) {
      final route = router.routeInformationProvider.value.uri.toString();
      if (!route.startsWith('/home')) {
        _needsUpdate = true;
        return;
      }

      loadServers();
    });
  }

  final LanServerDiscoveryService _discoveryService;

  bool _needsUpdate = false;
  int _page = 1;
  List<Server> _allServers = const <Server>[];
  late Timer _updateTimer;

  late ServerFilter filter;

  @override
  Future<void> close() async {
    _updateTimer.cancel();
    await super.close();
  }

  void checkUpdate() {
    if (_needsUpdate) {
      loadServers();
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
      _allServers = await _discoveryService.discover();
      _emitFilteredResults();
    } catch (error) {
      emit(ServerListError(error.toString()));
    }
  }

  void _emitFilteredResults() {
    final filtered = _allServers.where((server) {
      final query = filter.query;
      if (query == null || query.isEmpty) {
        return true;
      }

      final normalized = query.toLowerCase();
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
}
