final class DedicatedServerAuthContext {
  const DedicatedServerAuthContext({
    required this.playerName,
    required this.kyberToken,
    required this.licenseId,
    required this.denuvoId,
    required this.credentials,
  });

  final String playerName;
  final String kyberToken;
  final String licenseId;
  final String denuvoId;
  final String? credentials;
}
