enum PairingStatus {
  idle,
  incomingPrompt,
  awaitingVerification,
  verified,
  rejected,
}

class PairingSessionEntity {
  const PairingSessionEntity({
    required this.peerId,
    required this.peerName,
    required this.isInitiator,
    this.status = PairingStatus.idle,
    this.sixDigitPin,
    this.qrPayload,
    this.fingerprint,
    this.errorMessage,
  });

  final String peerId;
  final String peerName;
  final bool isInitiator;
  final PairingStatus status;
  final String? sixDigitPin;
  final String? qrPayload;
  final String? fingerprint;
  final String? errorMessage;

  bool get isWaitingForPrompt => status == PairingStatus.incomingPrompt;
  bool get isAwaitingVerification => status == PairingStatus.awaitingVerification;
  bool get isVerified => status == PairingStatus.verified;

  PairingSessionEntity copyWith({
    String? peerId,
    String? peerName,
    bool? isInitiator,
    PairingStatus? status,
    String? sixDigitPin,
    String? qrPayload,
    String? fingerprint,
    String? errorMessage,
  }) {
    return PairingSessionEntity(
      peerId: peerId ?? this.peerId,
      peerName: peerName ?? this.peerName,
      isInitiator: isInitiator ?? this.isInitiator,
      status: status ?? this.status,
      sixDigitPin: sixDigitPin ?? this.sixDigitPin,
      qrPayload: qrPayload ?? this.qrPayload,
      fingerprint: fingerprint ?? this.fingerprint,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
