import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:message_blue/main.dart';
import 'package:message_blue/src/models/chat_message.dart';
import 'package:message_blue/src/nearby/nearby_event.dart';
import 'package:message_blue/src/nearby/nearby_transport.dart';

void main() {
  testWidgets('starts the local network and shows discovered peers', (
    tester,
  ) async {
    final transport = FakeNearbyTransport();
    await tester.pumpWidget(BlueMeshApp(transport: transport));

    expect(find.text('Mensajes sin Internet'), findsOneWidget);

    final enterButton = find.text('Entrar a la red local');
    await tester.ensureVisible(enterButton);
    await tester.tap(enterButton);
    await tester.pump();

    expect(transport.startedWith, 'Android cercano');
    expect(find.text('Dispositivos cercanos'), findsOneWidget);

    transport.add(
      const PeerFound(endpointId: 'peer-1', name: 'Teléfono de Ana'),
    );
    await tester.pump();

    expect(find.text('Teléfono de Ana'), findsOneWidget);
    expect(find.text('Conectar'), findsOneWidget);
  });

  testWidgets('requires verification before opening a chat', (tester) async {
    final transport = FakeNearbyTransport();
    await tester.pumpWidget(BlueMeshApp(transport: transport));
    final enterButton = find.text('Entrar a la red local');
    await tester.ensureVisible(enterButton);
    await tester.tap(enterButton);
    await tester.pump();

    transport.add(
      const ConnectionApprovalRequired(
        endpointId: 'peer-1',
        name: 'Teléfono de Ana',
        authenticationToken: '7391',
        isIncoming: true,
      ),
    );
    await tester.pump();

    expect(find.text('Solicitud recibida'), findsOneWidget);
    expect(find.text('7391'), findsOneWidget);

    await tester.tap(find.text('Aceptar'));
    await tester.pump();
    expect(transport.acceptedEndpoints, ['peer-1']);

    transport.add(
      const ConnectionChanged(
        endpointId: 'peer-1',
        outcome: ConnectionOutcome.connected,
      ),
    );
    transport.add(const SecureChannelReady('peer-1'));
    await tester.pump();

    expect(find.text('Abrir chat'), findsOneWidget);
  });
}

class FakeNearbyTransport implements NearbyTransport {
  final StreamController<NearbyEvent> _events =
      StreamController<NearbyEvent>.broadcast();

  String? startedWith;
  final List<String> acceptedEndpoints = [];

  void add(NearbyEvent event) => _events.add(event);

  @override
  bool get isSupported => true;

  @override
  bool get isDemo => false;

  @override
  Stream<NearbyEvent> get events => _events.stream;

  @override
  Future<void> acceptConnection(String endpointId) async {
    acceptedEndpoints.add(endpointId);
  }

  @override
  Future<void> disconnect(String endpointId) async {}

  @override
  Future<void> dispose() => _events.close();

  @override
  Future<void> rejectConnection(String endpointId) async {}

  @override
  Future<void> requestConnection(String endpointId, String displayName) async {}

  @override
  Future<void> sendMessage(ChatMessage message) async {}

  @override
  Future<void> start(String displayName) async {
    startedWith = displayName;
  }

  @override
  Future<void> stop() async {}
}
