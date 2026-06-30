final class DedicatedServerLaunchConfig {
  const DedicatedServerLaunchConfig({
    required this.serverName,
    required this.gamePath,
    required this.onlineMode,
    required this.serverPort,
    required this.maxPlayers,
    required this.map,
    required this.mode,
    required this.modulePath,
    required this.gameArgs,
  });

  final String serverName;
  final String gamePath;
  final bool onlineMode;
  final int serverPort;
  final int maxPlayers;
  final String map;
  final String mode;
  final String modulePath;
  final List<String> gameArgs;
}
