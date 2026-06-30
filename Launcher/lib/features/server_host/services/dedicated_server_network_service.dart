import 'dart:io';

class DedicatedServerJoinAddress {
  const DedicatedServerJoinAddress({
    required this.host,
    required this.port,
    required this.interfaceName,
  });

  final String host;
  final int port;
  final String interfaceName;

  String get endpoint => '$host:$port';
}

class DedicatedServerNetworkService {
  const DedicatedServerNetworkService();

  Future<List<DedicatedServerJoinAddress>> getJoinAddresses({
    required int port,
  }) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final addresses = <DedicatedServerJoinAddress>[];

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (_isUsableIpv4(address.address)) {
          addresses.add(
            DedicatedServerJoinAddress(
              host: address.address,
              port: port,
              interfaceName: interface.name,
            ),
          );
        }
      }
    }

    addresses.sort((a, b) {
      final aScore = _addressPriority(a);
      final bScore = _addressPriority(b);
      final priority = aScore.compareTo(bScore);
      if (priority != 0) {
        return priority;
      }

      return a.host.compareTo(b.host);
    });

    return addresses;
  }

  bool _isUsableIpv4(String value) {
    return value != '0.0.0.0' &&
        !value.startsWith('127.') &&
        !value.startsWith('169.254.');
  }

  int _addressPriority(DedicatedServerJoinAddress address) {
    final interfaceName = address.interfaceName.toLowerCase();
    if (interfaceName.contains('vethernet') ||
        interfaceName.contains('hyper-v') ||
        interfaceName.contains('wsl') ||
        interfaceName.contains('default switch')) {
      return 3;
    }

    if (interfaceName.contains('vpn') || interfaceName.contains('radmin')) {
      return 2;
    }

    final value = address.host;
    if (value.startsWith('192.168.') ||
        value.startsWith('10.') ||
        _is172Private(value)) {
      return 0;
    }

    return 1;
  }

  bool _is172Private(String value) {
    final parts = value.split('.');
    if (parts.length != 4 || parts.first != '172') {
      return false;
    }

    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }
}
