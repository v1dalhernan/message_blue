enum PeerConnectionStatus {
  discovered,
  connecting,
  awaitingApproval,
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
  });

  final String id;
  final String name;
  final PeerConnectionStatus status;
  final String? authenticationToken;
  final bool isIncoming;

  bool get isConnected => status == PeerConnectionStatus.connected;

  NearbyPeer copyWith({
    String? name,
    PeerConnectionStatus? status,
    String? authenticationToken,
    bool? isIncoming,
    bool clearAuthenticationToken = false,
  }) {
    return NearbyPeer(
      id: id,
      name: name ?? this.name,
      status: status ?? this.status,
      authenticationToken: clearAuthenticationToken
          ? null
          : authenticationToken ?? this.authenticationToken,
      isIncoming: isIncoming ?? this.isIncoming,
    );
  }
}
