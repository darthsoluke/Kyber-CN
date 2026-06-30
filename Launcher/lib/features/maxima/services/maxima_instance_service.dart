import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kyber_launcher/core/services/hotkey_manager.dart';
import 'package:kyber_launcher/core/services/voip_service.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/gen/rust/api/maxima.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';

class MaximaInstanceService extends ChangeNotifier {
  final Set<MaximaGameInstance> _instances = {};
  final _logger = Logger('instance_service');

  Set<MaximaGameInstance> get instances => _instances;

  bool get hasInstances => _instances.isNotEmpty;

  ClientInstance? get clientInstance => _firstWhereOrNull(
    _instances.whereType<ClientInstance>(),
  );

  ServerInstance? get dedicatedServerInstance => _firstWhereOrNull(
    _instances.whereType<ServerInstance>(),
  );

  BfiiHostInstance? get bfiiHostInstance => dedicatedServerInstance;

  MaximaGameInstance? get primaryInstance =>
      clientInstance ?? dedicatedServerInstance;

  MaximaGameInstance? get serverControlInstance =>
      bfiiHostInstance ?? clientInstance;

  bool hasInstanceForRole({required bool dedicated}) {
    return dedicated ? dedicatedServerInstance != null : clientInstance != null;
  }

  MaximaGameInstance? instanceForRole({required bool dedicated}) {
    return dedicated ? dedicatedServerInstance : clientInstance;
  }

  Future<void> removeInstance(MaximaGameInstance instance) async {
    await instance.closeStream();
    _instances.removeWhere((e) => e.pid == instance.pid);

    _logger.info(
      'Instance ${instance.pid} stopped '
      'dedicated=${instance.isDedicated}',
    );

    if (_instances.isEmpty) {
      HotKeyService.unregisterIngameHotKey();
      sl.get<VoipService>().clearDevices();
    }
    notifyListeners();
  }

  Future<void> stopDedicatedServer() async {
    await stopBfiiHostServer();
  }

  Future<void> stopBfiiHostServer() async {
    final instance = bfiiHostInstance;
    if (instance == null) {
      throw StateError('No BFII host server is running.');
    }

    await stopInstance(instance);
  }

  Future<void> stopInstance(MaximaGameInstance instance) async {
    _logger.info(
      'Stopping instance ${instance.pid} dedicated=${instance.isDedicated}',
    );
    try {
      Process.killPid(instance.pid);
    } on Object catch (e, stack) {
      _logger.warning(
        'Failed to kill instance ${instance.pid}',
        e,
        stack,
      );
    }

    await removeInstance(instance);
  }

  void addInstance(MaximaGameInstance instance) {
    if (_instances.any((e) => e.pid == instance.pid)) {
      _logger.warning('Instance ${instance.pid} already exists');
      return;
    }

    _instances.add(instance);
    _logger.info(
      'Instance ${instance.pid} added dedicated=${instance.isDedicated}',
    );
    unawaited(HotKeyService.registerIngameHotKey());
    lsxGetEventStream(pid: instance.pid).listen(
      (event) => instance.addEvent(event),
      onDone: () => unawaited(removeInstance(instance)),
      onError: (e) => unawaited(removeInstance(instance)),
      cancelOnError: true,
    );
    notifyListeners();
  }

  T? _firstWhereOrNull<T extends MaximaGameInstance>(Iterable<T> instances) {
    for (final instance in instances) {
      return instance;
    }

    return null;
  }
}
