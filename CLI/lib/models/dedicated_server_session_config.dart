import 'package:kyber/kyber.dart';

final class DedicatedServerSessionConfig {
  const DedicatedServerSessionConfig({
    required this.mapRotation,
    required this.startupCommands,
  });

  final List<LevelSetup> mapRotation;
  final List<String> startupCommands;
}
