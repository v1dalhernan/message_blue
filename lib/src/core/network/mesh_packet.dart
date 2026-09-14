class MeshPacket {
  MeshPacket({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.recipientId,
    this.hopCount = 0,
    this.maxHops = 6,
    List<String>? routePath,
    required this.payloadType,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    int? timestamp,
  })  : routePath = routePath ?? [senderId],
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  final String senderId;
  final String senderName;
  /// `*` for mesh broadcast, `group:<groupId>` for group chat, or `<endpointId>` for direct 1-on-1
  final String recipientId;
  final int hopCount;
  final int maxHops;
  final List<String> routePath;
  /// `direct_msg`, `group_msg`, `delivery_receipt`, `group_invite`, `connection_req`, `connection_ack`
  final String payloadType;
  final String nonce;
  final String ciphertext;
  final String mac;
  final int timestamp;

  bool get isBroadcast => recipientId == '*';
  bool get isGroup => recipientId.startsWith('group:');
  String? get groupId => isGroup ? recipientId.substring(6) : null;
  bool get canRelay => hopCount < maxHops;

  MeshPacket copyWithNextHop(String relayNodeId) {
    return MeshPacket(
      id: id,
      senderId: senderId,
      senderName: senderName,
      recipientId: recipientId,
      hopCount: hopCount + 1,
      maxHops: maxHops,
      routePath: [...routePath, relayNodeId],
      payloadType: payloadType,
      nonce: nonce,
      ciphertext: ciphertext,
      mac: mac,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
        'v': 2,
        'type': 'mesh_packet',
        'id': id,
        'sId': senderId,
        'sName': senderName,
        'rId': recipientId,
        'hops': hopCount,
        'maxHops': maxHops,
        'route': routePath,
        'pType': payloadType,
        'nonce': nonce,
        'ct': ciphertext,
        'mac': mac,
        'ts': timestamp,
      };

  factory MeshPacket.fromJson(Map<String, dynamic> json) {
    return MeshPacket(
      id: json['id'] as String,
      senderId: json['sId'] as String,
      senderName: json['sName'] as String,
      recipientId: json['rId'] as String,
      hopCount: json['hops'] as int? ?? 0,
      maxHops: json['maxHops'] as int? ?? 6,
      routePath: (json['route'] as List<dynamic>?)?.cast<String>() ?? [json['sId'] as String],
      payloadType: json['pType'] as String,
      nonce: json['nonce'] as String,
      ciphertext: json['ct'] as String,
      mac: json['mac'] as String,
      timestamp: json['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  static bool isMeshPacket(Map<String, dynamic> json) {
    return json['v'] == 2 && json['type'] == 'mesh_packet';
  }
}
