/// A validated POS login QR (payload version 2).
class LoginChallenge {
  const new({
    required this.challengeId,
    required this.nonce,
    required this.posConfigId,
    required this.apiBase,
    required this.expiresAt,
  });

  final String challengeId;
  final String nonce;
  final int posConfigId;

  /// Mobile API base of the POS server that issued the QR.
  final Uri apiBase;
  final DateTime expiresAt;

  @override
  String toString() => 'LoginChallenge(redacted)';
}
