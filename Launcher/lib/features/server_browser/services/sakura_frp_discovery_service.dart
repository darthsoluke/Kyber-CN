import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/features/server_browser/models/lan_server_metadata.dart';
import 'package:kyber_launcher/features/server_browser/services/sakura_frp_api_service.dart';
import 'package:logging/logging.dart';

class SakuraFrpDiscoveryService {
  SakuraFrpDiscoveryService({SakuraFrpApiService? apiService})
    : _apiService = apiService ?? SakuraFrpApiService();

  final SakuraFrpApiService _apiService;
  final Logger _logger = Logger('sakura_frp_discovery');

  Future<List<SakuraFrpEndpoint>> resolveEndpoints() async {
    if (!Preferences.sakuraFrp.enabled) {
      return const <SakuraFrpEndpoint>[];
    }

    final manualEndpoints = _parseManualEndpoints(
      Preferences.sakuraFrp.manualEndpoints,
      source: 'sakura_frp_manual',
      label: 'Manual SakuraFRP endpoint',
    );
    final cachedEndpoints = _parseManualEndpoints(
      Preferences.sakuraFrp.cachedEndpoints,
      source: 'sakura_frp_cached',
      label: 'Saved SakuraFRP endpoint',
    );
    final token = Preferences.sakuraFrp.apiToken.trim();
    if (token.isEmpty) {
      final storedEndpoints = _deduplicate([
        ...manualEndpoints,
        ...cachedEndpoints,
      ]);
      if (storedEndpoints.isNotEmpty) {
        _logger.info(
          'SAKURA_STAGE[resolve.stored_only] count=${storedEndpoints.length}',
        );
        return storedEndpoints;
      }

      throw const SakuraFrpApiException(
        'SakuraFRP scanning is enabled, but no API token or manual '
        'endpoints are configured.',
      );
    }

    final apiEndpoints = await _resolveApiEndpoints();
    final endpoints = <SakuraFrpEndpoint>[
      ...manualEndpoints,
      ...cachedEndpoints,
      ...apiEndpoints,
    ];

    _logger.info(
      'SAKURA_STAGE[resolve.finished] '
      'manual=${manualEndpoints.length} cached=${cachedEndpoints.length} '
      'api=${apiEndpoints.length} '
      'total=${endpoints.length}',
    );
    return _deduplicate(endpoints);
  }

  void rememberSuccessfulEndpoints(Iterable<SakuraFrpEndpoint> endpoints) {
    final current = _parseManualEndpoints(
      Preferences.sakuraFrp.cachedEndpoints,
      source: 'sakura_frp_cached',
      label: 'Saved SakuraFRP endpoint',
    );
    final merged = _deduplicate([...current, ...endpoints]);
    Preferences.sakuraFrp.cachedEndpoints = merged
        .map((endpoint) => endpoint.toEndpointLine())
        .join('\n');
    _logger.info(
      'SAKURA_STAGE[cache.update] count=${merged.length}',
    );
  }

  List<SakuraFrpEndpoint> resolveStoredEndpointsFor({
    required String host,
    int? port,
  }) {
    final endpoints = _deduplicate([
      ..._parseManualEndpoints(
        Preferences.sakuraFrp.manualEndpoints,
        source: 'sakura_frp_manual',
        label: 'Manual SakuraFRP endpoint',
      ),
      ..._parseManualEndpoints(
        Preferences.sakuraFrp.cachedEndpoints,
        source: 'sakura_frp_cached',
        label: 'Saved SakuraFRP endpoint',
      ),
    ]);
    final normalizedHost = host.toLowerCase();

    return endpoints.where((endpoint) {
      final sameHost = endpoint.host.toLowerCase() == normalizedHost;
      if (!sameHost) {
        return false;
      }

      return port == null ||
          endpoint.gamePort == port ||
          endpoint.metadataPort == port;
    }).toList();
  }

  Future<List<SakuraFrpEndpoint>> _resolveApiEndpoints() async {
    _logger.info('SAKURA_STAGE[api.resolve.start]');
    final nodes = await _apiService.listNodes();
    final tunnels = await _apiService.listTunnels();
    final overrides = _parseNodeHostOverrides(
      Preferences.sakuraFrp.nodeHostOverrides,
    );
    final endpoints = <SakuraFrpEndpoint>[];

    final grouped = <int, List<SakuraFrpTunnel>>{};
    for (final tunnel in tunnels.where((item) => item.isUsableUdp)) {
      grouped.putIfAbsent(tunnel.node, () => <SakuraFrpTunnel>[]).add(tunnel);
    }

    for (final entry in grouped.entries) {
      final nodeId = entry.key;
      final host = overrides[nodeId] ?? nodes[nodeId]?.host ?? '';
      if (host.isEmpty) {
        _logger.warning(
          'SAKURA_STAGE[api.node.skip] node=$nodeId reason=missing_host',
        );
        continue;
      }

      final metadataTunnels = entry.value
          .where(
            (tunnel) => tunnel.localPort == LanServerProtocol.discoveryPort,
          )
          .toList();
      if (metadataTunnels.isEmpty) {
        _logger.warning(
          'SAKURA_STAGE[api.node.skip] node=$nodeId host=$host '
          'reason=missing_metadata_udp '
          'localPort=${LanServerProtocol.discoveryPort}',
        );
        continue;
      }

      final gameTunnels = entry.value
          .where(
            (tunnel) => tunnel.localPort != LanServerProtocol.discoveryPort,
          )
          .toList();
      if (gameTunnels.isEmpty) {
        _logger.warning(
          'SAKURA_STAGE[api.node.skip] node=$nodeId host=$host '
          'reason=missing_game_udp',
        );
        continue;
      }

      for (final gameTunnel in gameTunnels) {
        final metadataTunnel = _chooseMetadataTunnel(
          metadataTunnels,
          gameTunnel,
        );
        final metadataPort = metadataTunnel.remotePort;
        final gamePort = gameTunnel.remotePort;
        if (metadataPort == null || gamePort == null) {
          continue;
        }

        endpoints.add(
          SakuraFrpEndpoint(
            host: host,
            metadataPort: metadataPort,
            gamePort: gamePort,
            label: gameTunnel.name.isNotEmpty
                ? gameTunnel.name
                : 'SakuraFRP tunnel ${gameTunnel.id}',
            source: 'sakura_frp_api',
          ),
        );
      }
    }

    _logger.info(
      'SAKURA_STAGE[api.resolve.finished] '
      'nodes=${nodes.length} tunnels=${tunnels.length} '
      'endpoints=${endpoints.length}',
    );
    return endpoints;
  }

  SakuraFrpTunnel _chooseMetadataTunnel(
    List<SakuraFrpTunnel> metadataTunnels,
    SakuraFrpTunnel gameTunnel,
  ) {
    final name = gameTunnel.name.trim().toLowerCase();
    if (name.isNotEmpty) {
      for (final tunnel in metadataTunnels) {
        final metadataName = tunnel.name.trim().toLowerCase();
        if (metadataName.contains(name) || name.contains(metadataName)) {
          return tunnel;
        }
      }
    }

    return metadataTunnels.first;
  }

  List<SakuraFrpEndpoint> _parseManualEndpoints(
    String value, {
    required String source,
    required String label,
  }) {
    final endpoints = <SakuraFrpEndpoint>[];
    final lines = value
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'));

    for (final line in lines) {
      final endpoint = _parseManualEndpoint(
        line,
        source: source,
        label: label,
      );
      if (endpoint == null) {
        _logger.warning(
          'SAKURA_STAGE[manual.skip] line="$line" reason=invalid_format',
        );
        continue;
      }
      endpoints.add(endpoint);
    }

    return endpoints;
  }

  SakuraFrpEndpoint? _parseManualEndpoint(
    String line, {
    required String source,
    required String label,
  }) {
    final parts = line
        .split(RegExp(r'\s*(?:->|=)\s*'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length != 2) {
      return null;
    }

    final hostAndMetadata = _splitHostPort(parts[0]);
    final gamePort = int.tryParse(parts[1]);
    if (hostAndMetadata == null || !_isValidPort(gamePort)) {
      return null;
    }

    return SakuraFrpEndpoint(
      host: hostAndMetadata.$1,
      metadataPort: hostAndMetadata.$2,
      gamePort: gamePort!,
      label: label,
      source: source,
    );
  }

  (String, int)? _splitHostPort(String value) {
    final index = value.lastIndexOf(':');
    if (index <= 0 || index == value.length - 1) {
      return null;
    }

    final host = value.substring(0, index).trim();
    final port = int.tryParse(value.substring(index + 1).trim());
    if (host.isEmpty || !_isValidPort(port)) {
      return null;
    }

    return (host, port!);
  }

  Map<int, String> _parseNodeHostOverrides(String value) {
    final overrides = <int, String>{};
    final lines = value
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'));

    for (final line in lines) {
      final index = line.indexOf('=');
      if (index <= 0 || index == line.length - 1) {
        continue;
      }

      final nodeId = int.tryParse(line.substring(0, index).trim());
      final host = line.substring(index + 1).trim();
      if (nodeId != null && host.isNotEmpty) {
        overrides[nodeId] = host;
      }
    }

    return overrides;
  }

  List<SakuraFrpEndpoint> _deduplicate(List<SakuraFrpEndpoint> endpoints) {
    final byKey = <String, SakuraFrpEndpoint>{};
    for (final endpoint in endpoints) {
      byKey['${endpoint.host}:${endpoint.metadataPort}:${endpoint.gamePort}'] =
          endpoint;
    }
    return byKey.values.toList();
  }

  bool _isValidPort(int? port) => port != null && port > 0 && port <= 65535;
}

class SakuraFrpEndpoint {
  const SakuraFrpEndpoint({
    required this.host,
    required this.metadataPort,
    required this.gamePort,
    required this.label,
    required this.source,
  });

  final String host;
  final int metadataPort;
  final int gamePort;
  final String label;
  final String source;

  String toEndpointLine() => '$host:$metadataPort->$gamePort';
}
