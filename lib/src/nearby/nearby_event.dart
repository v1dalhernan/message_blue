import '../models/chat_message.dart';

sealed class NearbyEvent {
  const NearbyEvent();
}

class PeerFound extends NearbyEvent {
  const PeerFound({
    required this.endpointId,
    required this.name,
    this.uniqueId,
    this.avatar,
    this.pin,
  });

  final String endpointId;
  final String name;
  final String? uniqueId;
  final String? avatar;
  final String? pin;

  String? get avatarBase64 => avatar;
  String? get personalPin => pin;
}

class PeerUpdated extends NearbyEvent {
  const PeerUpdated({
    required this.endpointId,
    this.name,
    this.avatar,
    this.uniqueId,
  });

  final String endpointId;
  final String? name;
  final String? avatar;
  final String? uniqueId;
}

class PeerLost extends NearbyEvent {
  const PeerLost(this.endpointId);

  final String endpointId;
}

class ConnectionApprovalRequired extends NearbyEvent {
  const ConnectionApprovalRequired({
    required this.endpointId,
    required this.name,
    required this.authenticationToken,
    required this.isIncoming,
  });

  final String endpointId;
  final String name;
  final String authenticationToken;
  final bool isIncoming;
}

enum ConnectionOutcome { connected, rejected, failed, disconnected }

class ConnectionChanged extends NearbyEvent {
  const ConnectionChanged({required this.endpointId, required this.outcome});

  final String endpointId;
  final ConnectionOutcome outcome;
}

class SecureChannelReady extends NearbyEvent {
  const SecureChannelReady(this.endpointId);

  final String endpointId;
}

class MessageReceived extends NearbyEvent {
  const MessageReceived(this.message);

  final ChatMessage message;
}

class MessageEdited extends NearbyEvent {
  const MessageEdited({
    required this.endpointId,
    required this.targetMessageId,
    required this.newText,
    required this.editedAt,
  });

  final String endpointId;
  final String targetMessageId;
  final String newText;
  final DateTime editedAt;
}

class MessageReadReceipt extends NearbyEvent {
  const MessageReadReceipt({
    required this.endpointId,
    required this.messageId,
  });

  final String endpointId;
  final String messageId;
}

class NearbyFailure extends NearbyEvent {
  const NearbyFailure(this.message);

  final String message;
}

