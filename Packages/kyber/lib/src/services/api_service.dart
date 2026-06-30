// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:kyber/gen/Proto/kyber_api.pbgrpc.dart';
import 'package:uuid/uuid.dart';

const _kServicePort = 443;

class KyberGRPCService {
  KyberGRPCService(
    this.host,
    this.port, {
    required this.httpHostname,
    this.isInsecure = false,
  }) {
    _channel = ClientChannel(
      host,
      port: port,
      options: isInsecure
          ? const ChannelOptions(credentials: ChannelCredentials.insecure())
          : const ChannelOptions(),
    );

    _setChannels();
  }

  factory KyberGRPCService.fromDefaults() => KyberGRPCService.fromEnv('prod');

  factory KyberGRPCService.local() => KyberGRPCService(
        '0.0.0.0',
        9027,
        isInsecure: true,
        httpHostname: 'localhost',
      );

  factory KyberGRPCService.fromEnv(String env) {
    final target = _envApiTarget(env);
    return KyberGRPCService(
      target.host,
      target.port,
      httpHostname:
          Platform.environment['KYBER_HTTP_HOSTNAME'] ?? 'api.$env.kyber.gg',
      isInsecure: _envFlag('KYBER_API_INSECURE'),
    );
  }

  final String httpHostname;
  final bool isInsecure;

  String get moduleRpcTarget => port == _kServicePort ? host : '$host:$port';
  String get httpScheme => _envScheme(
        'KYBER_HTTP_SCHEME',
        {'http', 'https'},
        isInsecure ? 'http' : 'https',
      );
  String get webSocketScheme =>
      _envScheme('KYBER_WS_SCHEME', {'ws', 'wss'}, isInsecure ? 'ws' : 'wss');
  String get httpBaseUrl => '$httpScheme://$httpHostname';

  Uri webSocketUri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$webSocketScheme://$httpHostname$normalizedPath');
  }

  String imageUrl(String imageId) => '$httpBaseUrl/images/$imageId.jpeg';

  void _setChannels() {
    final id = const Uuid().v4();
    final callOptions = CallOptions(
      metadata: {
        'x-session-id': id,
        'x-kv2-dsid': '53ff61a4-b751-40f6-a0c8-31d362f29936',
        'authorization': _token ?? '',
      },
    );

    authClient = AuthenticationClient(_channel, options: callOptions);
    statsClient = StatisticsClient(_channel, options: callOptions);
    clientServerClient = ClientServerClient(_channel, options: callOptions);
    serverBrowserClient = ServerBrowserClient(_channel, options: callOptions);
    serverManagementClient =
        ServerManagementClient(_channel, options: callOptions);
    proxyClient = ProxyClient(_channel, options: callOptions);
    launcherClient = LauncherClient(_channel, options: callOptions);
    reportServiceClient = ReportServiceClient(_channel, options: callOptions);
  }

  late ClientChannel _channel;
  late ServerBrowserClient serverBrowserClient;
  late AuthenticationClient authClient;
  late StatisticsClient statsClient;
  late ClientServerClient clientServerClient;
  late ServerManagementClient serverManagementClient;
  late ProxyClient proxyClient;
  late LauncherClient launcherClient;
  late ReportServiceClient reportServiceClient;

  final String host;
  final int port;

  String? _token;

  set token(String? value) {
    _token = value;
    _setChannels();
  }

  String? get token => _token;

  Future<LoginResponse> login(String token) async {
    final response = await authClient.login(LoginRequest(token: token));
    _token = response.token;

    _setChannels();

    return response;
  }

  Future<String> getAuthToken(String token, {bool force = false}) async {
    if (_token != null && !force) {
      return _token!;
    }

    final response = await authClient.login(LoginRequest(token: token));
    _token = response.token;

    return _token!;
  }

  void dispose() {
    _channel.shutdown();
  }

  static bool _envFlag(String name) {
    final value = Platform.environment[name]?.toLowerCase();
    return value == '1' || value == 'true' || value == 'yes';
  }

  static String _envScheme(String name, Set<String> allowed, String fallback) {
    final value = Platform.environment[name]?.toLowerCase();
    if (value != null && allowed.contains(value)) {
      return value;
    }

    return fallback;
  }

  static _ApiTarget _envApiTarget(String env) {
    final rawHost =
        (Platform.environment['KYBER_API_HOSTNAME'] ?? 'api-rpc.$env.kyber.gg')
            .trim();
    final parsedTarget = _splitHostPort(rawHost);
    final explicitPort = int.tryParse(
      Platform.environment['KYBER_API_PORT'] ?? '',
    );

    return _ApiTarget(
      parsedTarget?.host ?? rawHost,
      explicitPort ?? parsedTarget?.port ?? _kServicePort,
    );
  }

  static _ApiTarget? _splitHostPort(String target) {
    final bracketEnd = target.indexOf(']');
    if (target.startsWith('[') && bracketEnd > 1) {
      final portStart = bracketEnd + 1;
      if (target.length > portStart && target[portStart] == ':') {
        final port = int.tryParse(target.substring(portStart + 1));
        if (port != null) {
          return _ApiTarget(target.substring(1, bracketEnd), port);
        }
      }
    }

    final firstColon = target.indexOf(':');
    final lastColon = target.lastIndexOf(':');
    if (firstColon <= 0 || firstColon != lastColon) {
      return null;
    }

    final port = int.tryParse(target.substring(lastColon + 1));
    if (port == null) {
      return null;
    }

    return _ApiTarget(target.substring(0, lastColon), port);
  }
}

class _ApiTarget {
  const _ApiTarget(this.host, this.port);

  final String host;
  final int port;
}
