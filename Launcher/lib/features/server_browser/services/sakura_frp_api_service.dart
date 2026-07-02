import 'package:dio/dio.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';

class SakuraFrpApiService {
  SakuraFrpApiService({Dio? dio}) : _dio = dio;

  final Dio? _dio;

  Future<Map<int, SakuraFrpNode>> listNodes() async {
    final response = await _client().get<Object?>('/nodes');
    final entries = _unwrapMap(response.data);
    final nodes = <int, SakuraFrpNode>{};

    for (final entry in entries.entries) {
      final id = int.tryParse(entry.key);
      final value = entry.value;
      if (id == null || value is! Map) {
        continue;
      }

      final node = SakuraFrpNode.fromJson(id, value.cast<String, dynamic>());
      if (node.host.isNotEmpty) {
        nodes[id] = node;
      }
    }

    return nodes;
  }

  Future<List<SakuraFrpTunnel>> listTunnels() async {
    final response = await _client().get<Object?>('/tunnels');
    final rawTunnels = _unwrapTunnelList(response.data);

    return rawTunnels
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => SakuraFrpTunnel.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Dio _client() {
    final configured = _dio;
    if (configured != null) {
      return configured;
    }

    final token = Preferences.sakuraFrp.apiToken.trim();
    if (token.isEmpty) {
      throw const SakuraFrpApiException(
        'SakuraFRP API token is not configured.',
      );
    }

    return Dio(
      BaseOptions(
        baseUrl: _normalizeBaseUrl(Preferences.sakuraFrp.apiBaseUrl),
        headers: {'Authorization': 'Bearer $token'},
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
  }

  static Map<String, Object?> _unwrapMap(Object? data) {
    if (data is Map) {
      final map = data.cast<String, Object?>();
      final nested = map['nodes'];
      if (nested is Map) {
        return nested.cast<String, Object?>();
      }
      final dataNested = map['data'];
      if (dataNested is Map) {
        return dataNested.cast<String, Object?>();
      }
      return map;
    }

    throw const SakuraFrpApiException(
      'SakuraFRP API returned an unexpected payload.',
    );
  }

  static Iterable<Object?> _unwrapTunnelList(Object? data) {
    if (data is List) {
      return data;
    }

    if (data is Map) {
      final map = data.cast<String, Object?>();
      final tunnels = map['tunnels'];
      if (tunnels is List) {
        return tunnels;
      }

      final nested = map['data'];
      if (nested is List) {
        return nested;
      }
      if (nested is Map) {
        return nested.values;
      }

      return map.values;
    }

    return const <Object?>[];
  }

  static String _normalizeBaseUrl(String value) {
    final normalized = value.trim().isEmpty
        ? 'https://api.natfrp.com/v4'
        : value.trim();
    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }
}

class SakuraFrpNode {
  const SakuraFrpNode({
    required this.id,
    required this.name,
    required this.host,
  });

  factory SakuraFrpNode.fromJson(int id, Map<String, dynamic> json) {
    return SakuraFrpNode(
      id: id,
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
    );
  }

  final int id;
  final String name;
  final String host;
}

class SakuraFrpTunnel {
  const SakuraFrpTunnel({
    required this.id,
    required this.name,
    required this.type,
    required this.node,
    required this.online,
    required this.status,
    required this.remote,
    required this.localPort,
  });

  factory SakuraFrpTunnel.fromJson(Map<String, dynamic> json) {
    return SakuraFrpTunnel(
      id: _parseInt(json['id']) ?? 0,
      name: json['name'] as String? ?? '',
      type: (json['type'] as String? ?? '').toLowerCase(),
      node: _parseInt(json['node']) ?? 0,
      online: _parseBool(json['online']),
      status: _parseInt(json['status']) ?? -1,
      remote: json['remote'],
      localPort:
          _parseInt(json['local_port']) ?? _parseInt(json['localPort']) ?? 0,
    );
  }

  final int id;
  final String name;
  final String type;
  final int node;
  final bool online;
  final int status;
  final Object? remote;
  final int localPort;

  int? get remotePort {
    final raw = remote;
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      final text = raw.trim();
      if (text.contains(':')) {
        return int.tryParse(text.substring(text.lastIndexOf(':') + 1));
      }
      return int.tryParse(text);
    }
    return null;
  }

  bool get isUdp => type == 'udp' || type == 'eudp';

  bool get isUsableUdp => online && status == 0 && isUdp && remotePort != null;

  static bool _parseBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      return value.trim().toLowerCase() == 'true';
    }
    if (value is num) {
      return value != 0;
    }
    return false;
  }

  static int? _parseInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }
}

class SakuraFrpApiException implements Exception {
  const SakuraFrpApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
