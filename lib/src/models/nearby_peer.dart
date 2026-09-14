enum PeerConnectionStatus {
  discovered,
  connecting,
  awaitingApproval,
  securing,
  connected,
  rejected,
  disconnected,
  failed,
}

class NearbyPeer {
  const NearbyPeer({
    required this.id,
    required this.name,
    required this.status,
    this.authenticationToken,
    this.isIncoming = false,
    this.uniqueId,
    this.avatarBase64,
    this.personalPin,
    this.isSpoofed = false,
  });

  final String id;
  final String name;
  final PeerConnectionStatus status;
  final String? authenticationToken;
  final bool isIncoming;
  final String? uniqueId;
  final String? avatarBase64;
  final String? personalPin;
  final bool isSpoofed;

  bool get isConnected => status == PeerConnectionStatus.connected;

  NearbyPeer copyWith({
    String? name,
    PeerConnectionStatus? status,
    String? authenticationToken,
    bool? isIncoming,
    bool clearAuthenticationToken = false,
    String? uniqueId,
    String? avatarBase64,
    String? personalPin,
    bool? isSpoofed,
  }) {
    return NearbyPeer(
      id: id,
      name: name ?? this.name,
      status: status ?? this.status,
      authenticationToken: clearAuthenticationToken
          ? null
          : authenticationToken ?? this.authenticationToken,
      isIncoming: isIncoming ?? this.isIncoming,
      uniqueId: uniqueId ?? this.uniqueId,
      avatarBase64: avatarBase64 ?? this.avatarBase64,
      personalPin: personalPin ?? this.personalPin,
      isSpoofed: isSpoofed ?? this.isSpoofed,
    );
  }
}
