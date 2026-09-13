import '../models/chat_message.dart';

sealed class NearbyEvent {
  const NearbyEvent();
}

class PeerFound extends NearbyEvent {
  const PeerFound({required this.endpointId, required this.name});

  final String endpointId;
  final String name;
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

class MessageReceived extends NearbyEvent {
  const MessageReceived(this.message);

  final ChatMessage message;
}

class NearbyFailure extends NearbyEvent {
  const NearbyFailure(this.message);

  final String message;
}
