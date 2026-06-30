import 'package:get_it/get_it.dart';
import 'package:kyber/kyber.dart';

class ProxyHelper {
  ProxyHelper._();

  static Future<List<KyberProxy>> getProxies() async {
    final getIt = GetIt.instance;
    final hasRegisteredApi = getIt.isRegistered<KyberGRPCService>();
    final api = hasRegisteredApi
        ? getIt<KyberGRPCService>()
        : KyberGRPCService.fromDefaults();
    try {
      final proxies = await api.proxyClient.getList(Empty());
      final result = <KyberProxy>[];
      for (final proxy in proxies.proxies) {
        result.add(KyberProxy(ping: 0, proxyInfo: proxy));
      }

      return result;
    } finally {
      if (!hasRegisteredApi) {
        api.dispose();
      }
    }
  }

  static Future<KyberProxy> getOptimalProxy() async {
    final proxies = await getProxies();
    if (proxies.isEmpty) {
      throw StateError(
        'No Kyber proxies are available from the configured API',
      );
    }

    proxies.sort((a, b) => a.ping.compareTo(b.ping));
    return proxies.first;
  }
}

class KyberProxy {
  KyberProxy({required this.ping, required this.proxyInfo});

  final int ping;
  final ProxyInfo proxyInfo;
}
