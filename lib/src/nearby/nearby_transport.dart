import '../models/chat_message.dart';
import 'nearby_event.dart';

abstract interface class NearbyTransport {
  bool get isSupported;

  bool get isDemo;

  Stream<NearbyEvent> get events;

  Future<void> start(String displayName);

  Future<void> stop();

  Future<void> requestConnection(
    String endpointId,
    String displayName, {
    String? enteredCode,
  });

  Future<void> acceptConnection(String endpointId);

  Future<void> rejectConnection(String endpointId);

  Future<void> disconnect(String endpointId);

  Future<void> sendMessage(ChatMessage message);

  Future<void> sendEdit({
    required String endpointId,
    required String targetMessageId,
    required String newText,
  });

  Future<void> sendReadReceipt(String endpointId, String messageId);

  Future<void> sendProfileUpdate({String? name, String? avatar});

  Future<void> dispose();
}

class NearbySetupException implements Exception {
  const NearbySetupException(this.message);

  final String message;

  @override
  String toString() => message;
}
