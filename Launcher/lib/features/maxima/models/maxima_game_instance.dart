import 'dart:async';

import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/features/mods/constants/categories.dart';

class MaximaGameInstance {
  MaximaGameInstance({
    required this.pid,
    required this.isDedicated,
    required this.clientService,
    this.mods = const [],
    this.voipSettings,
    this.serverMetadata,
  }) {
    _eventStreamController = StreamController<String>.broadcast();
  }

  int pid;
  final bool isDedicated;
  ClientGRPCService clientService;
  List<FrostyMod> mods;
  VoipSettings? voipSettings;
  ServerInstanceMetadata? serverMetadata;

  String get roleName => isDedicated ? 'server' : 'client';
  bool _eventStreamClosed = false;

  late StreamController<String> _eventStreamController;

  void addEvent(String event) {
    if (_eventStreamClosed) {
      return;
    }

    _eventStreamController.add(event);
  }

  Future<void> closeStream() async {
    if (_eventStreamClosed) {
      return;
    }

    _eventStreamClosed = true;
    await _eventStreamController.close();
  }

  Stream<String> get eventStream => _eventStreamController.stream;

  List<FrostyMod> get gameplayMods => mods
      .where(
        (m) => kRequiredCategories.contains(m.details.category.toLowerCase()),
      )
      .toList(growable: false);

  MaximaGameInstance copyWith({
    int? pid,
    bool? isDedicated,
    ClientGRPCService? clientService,
    List<FrostyMod>? mods,
    VoipSettings? voipSettings,
    ServerInstanceMetadata? serverMetadata,
  }) {
    final dedicated = isDedicated ?? this.isDedicated;
    final instancePid = pid ?? this.pid;
    final instanceClientService = clientService ?? this.clientService;
    final instanceMods = mods ?? this.mods;
    final instanceVoipSettings = voipSettings ?? this.voipSettings;
    final instanceServerMetadata = serverMetadata ?? this.serverMetadata;

    if (dedicated) {
      return ServerInstance(
        pid: instancePid,
        clientService: instanceClientService,
        mods: instanceMods,
        voipSettings: instanceVoipSettings,
        serverMetadata: instanceServerMetadata,
      );
    }

    return ClientInstance(
      pid: instancePid,
      clientService: instanceClientService,
      mods: instanceMods,
      voipSettings: instanceVoipSettings,
    );
  }
}

class ServerInstance extends MaximaGameInstance {
  ServerInstance({
    required super.pid,
    required super.clientService,
    super.mods,
    super.voipSettings,
    super.serverMetadata,
  }) : super(isDedicated: true);
}

/// BFII/Frostbite host-server process, not a standalone backend server.
typedef BfiiHostInstance = ServerInstance;

class ClientInstance extends MaximaGameInstance {
  ClientInstance({
    required super.pid,
    required super.clientService,
    super.mods,
    super.voipSettings,
  }) : super(isDedicated: false);
}

class ServerInstanceMetadata {
  ServerInstanceMetadata({
    required this.name,
    required this.port,
    required this.onlineMode,
    required this.startedAt,
    this.map,
    this.mode,
    this.maxPlayers,
  });

  factory ServerInstanceMetadata.fromStartRequest(StartServerRequest request) {
    final firstLevel = request.mapRotation.isEmpty
        ? null
        : request.mapRotation.first;
    return ServerInstanceMetadata(
      name: request.name,
      port: request.port == 0 ? 25200 : request.port,
      onlineMode: request.onlineMode,
      startedAt: DateTime.now(),
      map: firstLevel?.map,
      mode: firstLevel?.mode,
      maxPlayers: request.maxPlayers == 0 ? null : request.maxPlayers,
    );
  }

  final String name;
  final int port;
  final bool onlineMode;
  final DateTime startedAt;
  final String? map;
  final String? mode;
  final int? maxPlayers;
}
