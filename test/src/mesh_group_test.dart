import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_blue/src/chat_controller.dart';
import 'package:message_blue/src/models/chat_message.dart';
import 'package:message_blue/src/nearby/nearby_event.dart';
import 'package:message_blue/src/nearby/nearby_transport.dart';

void main() {
  test('Mesh routing: group broadcast, multi-hop relay and loop prevention',
      () async {
    final transport = _MockMeshTransport();
    final controller = ChatController(transport);

    await controller.start('Nodo Intermedio B');

    // Simular que Nodo B está conectado con Nodo A y Nodo C
    transport.emit(const PeerFound(endpointId: 'peer-A', name: 'Nodo A'));
    transport.emit(const PeerFound(endpointId: 'peer-C', name: 'Nodo C'));

    transport.emit(const ConnectionChanged(
      endpointId: 'peer-A',
      outcome: ConnectionOutcome.connected,
    ));
    transport.emit(const SecureChannelReady('peer-A'));

    transport.emit(const ConnectionChanged(
      endpointId: 'peer-C',
      outcome: ConnectionOutcome.connected,
    ));
    transport.emit(const SecureChannelReady('peer-C'));

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.connectedCount, 2);

    // 1. Nodo B envía mensaje a la sala grupal
    await controller.sendGroupText('¡Hola a toda la malla!');
    expect(controller.groupMessages.length, 1);
    expect(controller.groupMessages.first.text, '¡Hola a toda la malla!');

    // Verifica que se intentó enviar a ambos pares (A y C)
    expect(
      transport.sentMessages.where((m) => m.endpointId == 'peer-A').length,
      1,
    );
    expect(
      transport.sentMessages.where((m) => m.endpointId == 'peer-C').length,
      1,
    );

    transport.sentMessages.clear();

    // 2. Nodo B recibe un mensaje grupal proveniente de Nodo A (hopCount = 0)
    final msgFromA = ChatMessage(
      id: 'msg-from-A-100',
      endpointId: 'peer-A',
      author: 'Nodo A',
      text: 'Mensaje originado en A',
      sentAt: DateTime.now(),
      direction: MessageDirection.incoming,
      isGroup: true,
      hopCount: 0,
    );

    transport.emit(MessageReceived(msgFromA));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Debe aparecer en la sala grupal de B
    expect(controller.groupMessages.length, 2);
    expect(
      controller.groupMessages.any((m) => m.id == 'msg-from-A-100'),
      isTrue,
    );

    // Nodo B debe retransmitirlo (relay) únicamente a Nodo C con hopCount = 1
    expect(
      transport.sentMessages.where((m) => m.endpointId == 'peer-C').length,
      1,
    );
    final relayedToC =
        transport.sentMessages.firstWhere((m) => m.endpointId == 'peer-C');
    expect(relayedToC.hopCount, 1);
    expect(relayedToC.id, 'msg-from-A-100');

    // NO debe retransmitirlo de vuelta a Nodo A
    expect(
      transport.sentMessages.where((m) => m.endpointId == 'peer-A').length,
      0,
    );

    transport.sentMessages.clear();

    // 3. Prevención de bucles (Loop Prevention):
    // Si Nodo B recibe de nuevo el mismo mensaje 'msg-from-A-100' (por ejemplo, desde otro nodo),
    // debe ignorarlo y NO retransmitirlo.
    transport.emit(MessageReceived(msgFromA));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // La lista de mensajes no se duplica
    expect(controller.groupMessages.length, 2);
    // No se retransmite nada
    expect(transport.sentMessages.isEmpty, isTrue);

    controller.dispose();
  });
}

class _MockMeshTransport implements NearbyTransport {
  final StreamController<NearbyEvent> _events =
      StreamController<NearbyEvent>.broadcast();
  final List<ChatMessage> sentMessages = [];

  void emit(NearbyEvent event) => _events.add(event);

  @override
  bool get isSupported => true;

  @override
  bool get isDemo => false;

  @override
  Stream<NearbyEvent> get events => _events.stream;

  @override
  Future<void> acceptConnection(String endpointId) async {}

  @override
  Future<void> disconnect(String endpointId) async {}

  @override
  Future<void> dispose() => _events.close();

  @override
  Future<void> rejectConnection(String endpointId) async {}

  @override
  Future<void> requestConnection(
    String endpointId,
    String displayName, {
    String? enteredCode,
  }) async {}

  @override
  Future<void> sendEdit({
    required String endpointId,
    required String targetMessageId,
    required String newText,
  }) async {}

  @override
  Future<void> sendMessage(ChatMessage message) async {
    sentMessages.add(message);
  }

  @override
  Future<void> sendReadReceipt(String endpointId, String messageId) async {}

  @override
  Future<void> sendProfileUpdate({String? name, String? avatar}) async {}

  @override
  Future<void> start(String displayName) async {}

  @override
  Future<void> stop() async {}
}
