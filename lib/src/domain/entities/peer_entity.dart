enum PeerConnectionStatus {
  discovered,
  connecting,
  incomingRequest,
  awaitingVerification,
  connected,
  disconnected,
  rejected,
}

class PeerEntity {
  const PeerEntity({
    required this.id,
    required this.name,
    this.status = PeerConnectionStatus.discovered,
    this.publicKey,
    this.pin,
    this.qrPayload,
    this.isVerified = false,
    this.isDirectNeighbor = true,
    this.hops = 1,
    this.viaNode,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final PeerConnectionStatus status;
  final List<int>? publicKey;
  final String? pin;
  final String? qrPayload;
  final bool isVerified;
  final bool isDirectNeighbor;
  final int hops;
  final String? viaNode;
  final DateTime lastSeen;

  bool get isConnected => status == PeerConnectionStatus.connected;
  bool get canConnect => status == PeerConnectionStatus.discovered || status == PeerConnectionStatus.disconnected;

  PeerEntity copyWith({
    String? id,
    String? name,
    PeerConnectionStatus? status,
    List<int>? publicKey,
    String? pin,
    String? qrPayload,
    bool? isVerified,
    bool? isDirectNeighbor,
    int? hops,
    String? viaNode,
    DateTime? lastSeen,
  }) {
    return PeerEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      publicKey: publicKey ?? this.publicKey,
      pin: pin ?? this.pin,
      qrPayload: qrPayload ?? this.qrPayload,
      isVerified: isVerified ?? this.isVerified,
      isDirectNeighbor: isDirectNeighbor ?? this.isDirectNeighbor,
      hops: hops ?? this.hops,
      viaNode: viaNode ?? this.viaNode,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
