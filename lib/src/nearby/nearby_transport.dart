import '../models/chat_message.dart';
import 'nearby_event.dart';

abstract interface class NearbyTransport {
  bool get isSupported;

  Stream<NearbyEvent> get events;

  Future<void> start(String displayName);

  Future<void> stop();

  Future<void> requestConnection(String endpointId, String displayName);

  Future<void> acceptConnection(String endpointId);

  Future<void> rejectConnection(String endpointId);

  Future<void> disconnect(String endpointId);

  Future<void> sendMessage(ChatMessage message);

  Future<void> dispose();
}

class NearbySetupException implements Exception {
  const NearbySetupException(this.message);

  final String message;

  @override
  String toString() => message;
}
