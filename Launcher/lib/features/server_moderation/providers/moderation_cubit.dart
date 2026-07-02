import 'dart:async';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/maxima/services/maxima_instance_service.dart';
import 'package:kyber_launcher/features/server_browser/helpers/lan_server_helper.dart';
import 'package:kyber_launcher/features/server_host/services/external_dedicated_host_service.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/server_settings_box.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ModerationCubit extends Cubit<ModerationServerState> {
  ModerationCubit() : super(const ModerationServerState()) {
    botChangeStream = ReplaySubject<(int, int)>();
    botChangeStream!
        .debounceTime(const Duration(milliseconds: 300))
        .listen(
          (event) => sendCommand(
            '/AutoPlayers.ForceFillGameplayBotsTeam${event.$1} ${event.$2}',
          ),
        );
  }

  final _logger = Logger('moderation_cubit');
  final _pendingBlacklistKicks = <String>{};
  ClientGRPCService? _externalControlClient;
  int? _externalControlPort;
  Timer? _keepAliveTimer;
  Timer? _localPollTimer;

  ReplaySubject<(int, int)>? botChangeStream;

  WebSocketChannel? _channel;

  @override
  Future<void> close() {
    unloadServer();
    return super.close();
  }

  Future<void> loadModerators() async {
    if (state.localControl) {
      emit(state.copyWith(moderators: <KyberPlayer>[]));
      return;
    }

    final moderators = await sl
        .get<KyberGRPCService>()
        .serverManagementClient
        .getModerators(ModeratorsRequest(serverId: state.id));
    emit(state.copyWith(moderators: moderators.users.toList()));
  }

  Future<void> loadPunishments() async {
    if (state.localControl) {
      emit(state.copyWith(localBlacklistEntries: _loadLocalBlacklist()));
      return;
    }

    final punishments = await sl
        .get<KyberGRPCService>()
        .serverManagementClient
        .getPunishments(PunishmentsRequest(serverId: state.id));
    punishments.punishments.sort((a, b) {
      final isAExpired = DateTime.fromMillisecondsSinceEpoch(
        a.expiresAt.toInt(),
      );
      final isBExpired = DateTime.fromMillisecondsSinceEpoch(
        b.expiresAt.toInt(),
      );

      if (isAExpired.isBefore(DateTime.now()) &&
          isBExpired.isBefore(DateTime.now())) {
        return 0;
      }

      if (isAExpired.isBefore(DateTime.now())) {
        return 1;
      }

      if (isBExpired.isBefore(DateTime.now())) {
        return -1;
      }

      return isAExpired.compareTo(isBExpired);
    });
    emit(state.copyWith(punishments: punishments.punishments));
  }

  Future<void> unbanPlayer(String id) async {
    if (state.localControl) {
      _logger.info('Removing local blacklist entry $id');
      final entries = _loadLocalBlacklist()
          .where((entry) => entry.id != id)
          .toList();
      _saveLocalBlacklist(entries);
      emit(state.copyWith(localBlacklistEntries: entries));
      _appendCommand('LOCAL: removed $id from dedicated server blacklist');
      return;
    }

    _logger.info('Unbanning player $id');
    await sl.get<KyberGRPCService>().serverManagementClient.unbanPlayer(
      UnbanPlayerRequest(userId: id, serverId: state.id),
    );

    await loadPunishments();
  }

  Future<void> promotePlayer(String id) {
    if (state.localControl) {
      NotificationService.info(
        message: 'Local dedicated servers do not use Kyber moderators.',
      );
      return Future.value();
    }

    _logger.info('Promoting player $id');
    return sl
        .get<KyberGRPCService>()
        .serverManagementClient
        .addModerator(
          AddModeratorRequest(id: id),
        )
        .then((_) => loadModerators());
  }

  Future<void> demotePlayer(String id) {
    if (state.localControl) {
      NotificationService.info(
        message: 'Local dedicated servers do not use Kyber moderators.',
      );
      return Future.value();
    }

    _logger.info('Demoting player $id');
    return sl
        .get<KyberGRPCService>()
        .serverManagementClient
        .removeModerator(
          RemoveModeratorRequest(id: id),
        )
        .then((_) => loadModerators());
  }

  Future<void> banPlayer({
    required String id,
    required String reason,
    required Duration duration,
  }) async {
    if (state.localControl) {
      final normalizedReason = reason.trim().isEmpty
          ? 'Banned by host'
          : reason.trim();
      final player = _findPlayer(id);
      final entry = LocalBlacklistEntry(
        id: id,
        name: player?.name ?? id,
        reason: normalizedReason,
        expiresAt: duration == Duration.zero
            ? null
            : DateTime.now().add(duration),
      );
      final entries =
          _loadLocalBlacklist().where((item) => item.id != id).toList()
            ..add(entry);
      _saveLocalBlacklist(entries);
      emit(state.copyWith(localBlacklistEntries: entries));
      await _sendLocalCommand(
        'Kyber.BanPlayerById $id ${_consoleText(normalizedReason)}',
      );
      return;
    }

    _logger.info('Banning player $id');
    await sl.get<KyberGRPCService>().serverManagementClient.banPlayer(
      ServerBanPlayerRequest(
        id: state.id,
        userId: id,
        reason: reason.isEmpty ? 'Banned by moderator' : reason,
        duration: Int64(duration.inSeconds),
      ),
    );
  }

  void swapTeam(ServerPlayer player) {
    _logger.info('Swapping team for player ${player.id}');

    final team = player.teamId == 1 ? 2 : 1;
    sendCommand('/Kyber.SetTeamById ${player.id} $team');
  }

  void shuffleTeams() {
    sendCommand('/Kyber.ShuffleTeams');
  }

  void swapAllTeams() {
    sendCommand('/Kyber.FullTeamSwap');
  }

  Future<void> kickAllPlayers({String reason = 'Kicked by host'}) async {
    final players = List<ServerPlayer>.from(state.players);
    for (final player in players) {
      await kickPlayer(player.id, reason: reason);
    }
  }

  Future<void> banAllPlayers({String reason = 'Banned by host'}) async {
    final players = List<ServerPlayer>.from(state.players);
    for (final player in players) {
      await banPlayer(id: player.id, reason: reason, duration: Duration.zero);
    }
  }

  Future<void> clearLocalBlacklist() async {
    if (!state.localControl) {
      return;
    }

    _saveLocalBlacklist(<LocalBlacklistEntry>[]);
    emit(state.copyWith(localBlacklistEntries: <LocalBlacklistEntry>[]));
    _appendCommand('LOCAL: dedicated server blacklist cleared');
  }

  Future<void> kickPlayer(String id, {String? reason = 'Kicked by moderator'}) {
    if (state.localControl) {
      final normalizedReason = (reason ?? '').trim().isEmpty
          ? 'Kicked by host'
          : reason!.trim();
      _logger.info('Kicking local player $id');
      return _sendLocalCommand(
        'Kyber.KickPlayerById $id ${_consoleText(normalizedReason)}',
      );
    }

    _logger.info('Kicking player $id');
    return sl.get<KyberGRPCService>().serverManagementClient.kickPlayer(
      ServerKickPlayerRequest(
        id: state.id,
        userId: id,
        reason: reason,
      ),
    );
  }

  void sendCommand(String input) {
    if (state.server == null) {
      return;
    }

    final command = _normalizeCommand(input);

    if (state.localControl) {
      unawaited(
        _sendLocalCommand(command).catchError((Object error, StackTrace stack) {
          _logger.severe('Local command failed', error, stack);
          _appendCommand('ERR: local command failed: $error');
        }),
      );
      return;
    }

    _logger.info('Sending command: $command');
    unawaited(
      sl.get<KyberGRPCService>().serverManagementClient.runCommand(
        ServerRunCommandRequest(
          id: state.id,
          command: command,
        ),
      ),
    );
  }

  void unloadServer() {
    _logger.info('Unloading server');

    unawaited(_channel?.sink.close());
    _keepAliveTimer?.cancel();
    _localPollTimer?.cancel();
    _pendingBlacklistKicks.clear();
    _shutdownExternalControlClient();

    emit(const ModerationServerState());

    if (isClosed) {
      return;
    }
  }

  Future<void> loadServer(Server server) async {
    emit(ModerationServerState(id: server.id, server: server));
  }

  Future<void> selectServer({String? serverId}) async {
    final localControlClient = _resolveLocalControlClient();
    if (state.server == null &&
        serverId == null &&
        localControlClient == null) {
      return;
    }

    await _channel?.sink.close();
    _keepAliveTimer?.cancel();
    _localPollTimer?.cancel();

    final id = serverId ?? state.id;
    final shouldUseLocalControl =
        localControlClient != null &&
        (id == null || id.isEmpty || LanServerHelper.isLanServerId(id));

    if (shouldUseLocalControl) {
      await _selectLocalServer(requestedId: id);
      return;
    }

    try {
      if (id == null || id.isEmpty) {
        throw StateError('No server id was provided for moderation.');
      }

      _logger.info('Loading server $id');
      emit(ModerationServerState(id: id, selected: true));
      final service = sl.get<KyberGRPCService>();
      final server = await service.serverBrowserClient.getServer(
        ServerRequest(id: id),
      );
      emit(state.copyWith(id: id, server: server));

      hostingForm.currentState?.fields['serverName']?.didChange(server.name);

      _logger.info('Subscribing to server events');

      final url = service.webSocketUri('/ws/client/${server.id}');
      _logger.info('Subscribing to server events at $url');
      _channel = IOWebSocketChannel.connect(
        url,
        headers: {
          'Authorization': service.token,
        },
        connectTimeout: const Duration(seconds: 10),
      );

      await _channel?.ready;

      _channel?.stream.listen(
        (event) {
          try {
            final data = ServerManagementAPIEvent.fromBuffer(
              event as List<int>,
            );
            if (data.hasPlayers()) {
              _logger.fine('Received players event');
              emit(state.copyWith(players: data.players.players));
            } else if (data.hasConsole()) {
              _logger.fine('Received console event');
              final commands = List<String>.from(state.commands)
                ..add(data.console.message);
              emit(state.copyWith(commands: commands));
            }
          } on Object catch (e, s) {
            _logger.severe('Error parsing event', e, s);
          }
        },
        onDone: () {
          _logger.info('Stream done');
          unloadServer();
        },
        onError: (dynamic e, StackTrace s) {
          NotificationService.showNotification(
            title: 'Server error',
            message: 'An error occurred while communicating with the server',
          );
          _logger.severe('Stream error', e, s);
          unloadServer();
        },
      );

      _keepAliveTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) async => _channel?.sink.add(''),
      );

      _logger.info('Fetching moderators');
      await loadModerators();

      _logger.info('Fetching punishments');
      await loadPunishments();

      await Future<void>.delayed(const Duration(seconds: 3));

      final instance = sl.get<MaximaInstanceService>().serverControlInstance;
      if (instance != null && state.players.isEmpty) {
        final data = await instance.clientService.commonClient.getInfo(Empty());
        if (data.hasServer() &&
            state.players.isEmpty &&
            data.server.playerList.isNotEmpty) {
          _logger.info('Received players from game instance');
          emit(state.copyWith(players: data.server.playerList));
        }
      }
    } on WebSocketException catch (e, s) {
      var error = 'Failed to connect to websocket';
      switch (e.httpStatusCode ?? 0) {
        case 401:
          error = 'Failed to connect to websocket: Unauthorized';
        case 404:
          error = 'The specified server was not found';
      }

      _logger.severe('Failed to connect to websocket', e, s);
      NotificationService.error(message: error);
      unloadServer();
    } on GrpcError catch (e, s) {
      _logger.severe('Error loading server:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message:
            e.message ??
            'An error occurred while communicating with the server',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    } on SocketException catch (e, s) {
      _logger.severe('Socket error:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message: 'An error occurred while communicating with the server',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    } on Object catch (e, s) {
      _logger.severe('Error loading server:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message: 'An error occurred while communicating with the server',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    }
  }

  Future<void> refreshLocalState() => _refreshLocalState();

  String _normalizeCommand(String input) => switch (input) {
    final command when command.startsWith('/') => command.substring(1),
    _ => 'Kyber.Broadcast $input',
  };

  String _consoleText(String input) =>
      input.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

  ServerPlayer? _findPlayer(String id) {
    for (final player in state.players) {
      if (player.id == id) {
        return player;
      }
    }

    return null;
  }

  ClientGRPCService? _resolveLocalControlClient() {
    final instance = sl.get<MaximaInstanceService>().serverControlInstance;
    if (instance != null) {
      return instance.clientService;
    }

    final externalState = sl.get<ExternalDedicatedHostService>().state;
    if (externalState.status != ExternalDedicatedHostStatus.running) {
      return null;
    }

    final port = externalState.interfacePort ?? 19103;
    if (_externalControlClient == null || _externalControlPort != port) {
      _shutdownExternalControlClient();
      _externalControlPort = port;
      _externalControlClient = ClientGRPCService(
        '127.0.0.1',
        port,
        connectTimeout: const Duration(seconds: 3),
      );
      _logger.info('Attached external dedicated control port $port');
    }

    return _externalControlClient;
  }

  void _shutdownExternalControlClient() {
    final client = _externalControlClient;
    if (client == null) {
      return;
    }

    unawaited(client.channel.shutdown());
    _externalControlClient = null;
    _externalControlPort = null;
  }

  Future<void> _selectLocalServer({String? requestedId}) async {
    try {
      final client = _resolveLocalControlClient();
      if (client == null) {
        throw StateError('Local dedicated server control instance is missing.');
      }

      final data = await client.commonClient.getInfo(Empty());
      if (!data.hasServer()) {
        throw StateError(
          'Local dedicated server is not exposing server state.',
        );
      }

      final server = _buildLocalServer(data.server, requestedId: requestedId);
      final blacklist = _loadLocalBlacklist();
      emit(
        ModerationServerState(
          id: server.id,
          server: server,
          selected: true,
          players: data.server.playerList.toList(),
          commands: const [
            'LOCAL: dedicated server control channel attached',
          ],
          localControl: true,
          localBlacklistEntries: blacklist,
        ),
      );
      hostingForm.currentState?.fields['serverName']?.didChange(server.name);
      _startLocalPolling();
      await _enforceLocalBlacklist(data.server.playerList);
    } on Object catch (e, s) {
      _logger.severe('Error loading local dedicated server:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message: 'Unable to attach local dedicated server control channel',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    }
  }

  Server _buildLocalServer(ServerState serverState, {String? requestedId}) {
    final host = Preferences.hostServer;
    final port = serverState.port == 0 ? host.port : serverState.port;
    final id = requestedId != null && requestedId.isNotEmpty
        ? requestedId
        : LanServerHelper.makeSyntheticId('127.0.0.1', port);
    final name = host.name.trim().isEmpty
        ? 'Local Dedicated Server'
        : host.name.trim();

    return Server(
      id: id,
      name: name,
      official: false,
      levelSetup: serverState.hasLevelSetup()
          ? serverState.levelSetup
          : LevelSetup(),
      creator: 'Local Host',
      creatorId: 'local-host',
      requiresPassword: host.password.isNotEmpty,
      playerCount: serverState.playerList.length,
      maxPlayerCount: host.maxPlayers,
      requiresProxy: false,
      ip: '127.0.0.1',
      port: port,
      description: host.description,
    );
  }

  void _startLocalPolling() {
    _localPollTimer?.cancel();
    _localPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(
        _refreshLocalState().catchError((Object error, StackTrace stack) {
          _logger.warning(
            'Local dedicated server refresh failed',
            error,
            stack,
          );
        }),
      ),
    );
  }

  Future<void> _refreshLocalState() async {
    if (!state.localControl) {
      return;
    }

    final client = _resolveLocalControlClient();
    if (client == null) {
      _appendCommand('ERR: local dedicated server control instance is missing');
      return;
    }

    final data = await client.commonClient.getInfo(Empty());
    if (!data.hasServer()) {
      _appendCommand('ERR: local dedicated server state is unavailable');
      return;
    }

    final blacklist = _loadLocalBlacklist();
    emit(
      state.copyWith(
        server: _buildLocalServer(data.server, requestedId: state.id),
        players: data.server.playerList.toList(),
        localBlacklistEntries: blacklist,
      ),
    );
    await _enforceLocalBlacklist(data.server.playerList);
  }

  Future<void> _sendLocalCommand(
    String command, {
    bool refreshAfter = true,
  }) async {
    _logger.info('Sending local dedicated command: $command');
    _appendCommand('> $command');
    final client = _resolveLocalControlClient();
    if (client == null) {
      throw StateError('Local dedicated server control instance is missing.');
    }

    await client.commonClient.runCommand(
      RunCommandRequest(command: command),
    );

    if (refreshAfter) {
      await _refreshLocalState();
    }
  }

  Future<void> _enforceLocalBlacklist(Iterable<ServerPlayer> players) async {
    final entries = _loadLocalBlacklist();
    if (entries.isEmpty) {
      return;
    }

    for (final player in players) {
      LocalBlacklistEntry? entry;
      for (final item in entries) {
        if (item.id == player.id) {
          entry = item;
          break;
        }
      }

      if (entry == null || _pendingBlacklistKicks.contains(player.id)) {
        continue;
      }

      _pendingBlacklistKicks.add(player.id);
      try {
        final reason = entry.reason.trim().isEmpty
            ? 'Banned by host'
            : entry.reason.trim();
        _appendCommand(
          'LOCAL: auto-kicking blacklisted player '
          '${player.name} (${player.id})',
        );
        await _sendLocalCommand(
          'Kyber.BanPlayerById ${player.id} ${_consoleText(reason)}',
          refreshAfter: false,
        );
      } finally {
        _pendingBlacklistKicks.remove(player.id);
      }
    }
  }

  List<LocalBlacklistEntry> _loadLocalBlacklist() {
    final rawEntries = Preferences.hostServer.dedicatedBlacklistEntries;
    final entries = rawEntries
        .map(LocalBlacklistEntry.tryDecode)
        .whereType<LocalBlacklistEntry>()
        .where((entry) => !entry.isExpired)
        .toList();

    final encoded = entries.map((entry) => entry.encode()).toList();
    if (encoded.length != rawEntries.length ||
        !_sameStringList(encoded, rawEntries)) {
      Preferences.hostServer.dedicatedBlacklistEntries = encoded;
    }

    return entries;
  }

  void _saveLocalBlacklist(List<LocalBlacklistEntry> entries) {
    Preferences.hostServer.dedicatedBlacklistEntries = entries
        .where((entry) => !entry.isExpired)
        .map((entry) {
          return entry.encode();
        })
        .toList();
  }

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }

    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) {
        return false;
      }
    }

    return true;
  }

  void _appendCommand(String command) {
    if (isClosed) {
      return;
    }

    emit(
      state.copyWith(commands: List<String>.from(state.commands)..add(command)),
    );
  }
}

class LocalBlacklistEntry {
  const LocalBlacklistEntry({
    required this.id,
    required this.name,
    required this.reason,
    required this.expiresAt,
  });

  final String id;
  final String name;
  final String reason;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  String encode() => [
    id,
    name,
    reason,
    expiresAt?.millisecondsSinceEpoch.toString() ?? '0',
  ].map(Uri.encodeComponent).join('\t');

  static LocalBlacklistEntry? tryDecode(String value) {
    final parts = value.split('\t');
    if (parts.length != 4) {
      return null;
    }

    final expiresAtMs = int.tryParse(Uri.decodeComponent(parts[3])) ?? 0;
    return LocalBlacklistEntry(
      id: Uri.decodeComponent(parts[0]),
      name: Uri.decodeComponent(parts[1]),
      reason: Uri.decodeComponent(parts[2]),
      expiresAt: expiresAtMs == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
    );
  }
}

class ModerationServerState {
  const ModerationServerState({
    this.id,
    this.server,
    this.players = const [],
    this.commands = const [],
    this.moderators = const [],
    this.punishments = const [],
    this.selected = false,
    this.localControl = false,
    this.localBlacklistEntries = const [],
  });

  final String? id;
  final bool selected;
  final bool localControl;
  final Server? server;
  final List<ServerPlayer> players;
  final List<Punishment> punishments;
  final List<String> commands;
  final List<KyberPlayer> moderators;
  final List<LocalBlacklistEntry> localBlacklistEntries;

  bool isModerator(String userId) {
    return moderators.any((moderator) => moderator.id == userId);
  }

  ModerationServerState copyWith({
    String? id,
    Server? server,
    List<KyberPlayer>? moderators,
    List<ServerPlayer>? players,
    List<String>? commands,
    List<Punishment>? punishments,
    bool? selected,
    bool? localControl,
    List<LocalBlacklistEntry>? localBlacklistEntries,
  }) {
    return ModerationServerState(
      id: id ?? this.id,
      server: server ?? this.server,
      players: players ?? this.players,
      commands: commands ?? this.commands,
      punishments: punishments ?? this.punishments,
      selected: selected ?? this.selected,
      localControl: localControl ?? this.localControl,
      moderators: moderators ?? this.moderators,
      localBlacklistEntries:
          localBlacklistEntries ?? this.localBlacklistEntries,
    );
  }
}
