import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:message_blue/src/models/chat_message.dart';
import 'package:message_blue/src/nearby/lan_socket_transport.dart';
import 'package:message_blue/src/nearby/nearby_event.dart';

void main() {
  test('two peers communicate and exchange encrypted messages over LAN socket',
      () async {
    // 1. Iniciar un hub TCP local de pruebas en puerto efímero
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;

    final clients = <String, Socket>{};

    server.listen((Socket socket) {
      String? clientId;
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        final msg = jsonDecode(line) as Map<String, dynamic>;
        final action = msg['action'] as String?;

        if (action == 'register') {
          clientId = msg['endpointId'] as String;
          final name = msg['name'] as String;
          clients[clientId!] = socket;

          // Notificar descubrimiento mutuo
          for (final entry in clients.entries) {
            if (entry.key != clientId) {
              socket.write('${jsonEncode({
                    'action': 'peer_found',
                    'endpointId': entry.key,
                    'name': 'Peer ${entry.key}',
                  })}\n');
              entry.value.write('${jsonEncode({
                    'action': 'peer_found',
                    'endpointId': clientId,
                    'name': name,
                  })}\n');
            }
          }
        } else {
          final to = msg['to'] as String?;
          if (to != null && clients.containsKey(to)) {
            clients[to]!.write('$line\n');
          }
        }
      });
    });

    // 2. Crear las dos instancias de transporte
    final peerA = LanSocketTransport(customHost: '127.0.0.1', port: port);
    final peerB = LanSocketTransport(customHost: '127.0.0.1', port: port);

    final eventsA = <NearbyEvent>[];
    final eventsB = <NearbyEvent>[];
    final subA = peerA.events.listen(eventsA.add);
    final subB = peerB.events.listen(eventsB.add);

    addTearDown(() async {
      await subA.cancel();
      await subB.cancel();
      await peerA.dispose();
      await peerB.dispose();
      await server.close();
    });

    // 3. Iniciar ambos peers
    await peerA.start('Dispositivo A');
    await peerB.start('Dispositivo B');

    // Esperar a que se descubran
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(eventsA.any((e) => e is PeerFound), isTrue);
    expect(eventsB.any((e) => e is PeerFound), isTrue);

    final peerBFoundByA = eventsA.whereType<PeerFound>().first;

    // 4. Solicitar conexión de A a B
    await peerA.requestConnection(peerBFoundByA.endpointId, 'Dispositivo A');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final approvalReqB =
        eventsB.whereType<ConnectionApprovalRequired>().firstOrNull;
    expect(approvalReqB, isNotNull);

    // 5. B acepta la conexión
    await peerB.acceptConnection(approvalReqB!.endpointId);
    await Future<void>.delayed(const Duration(milliseconds: 400));

    // Ambos deben tener el canal seguro listo (SecureChannelReady)
    expect(eventsA.any((e) => e is SecureChannelReady), isTrue);
    expect(eventsB.any((e) => e is SecureChannelReady), isTrue);

    // 6. Enviar mensaje cifrado de A a B
    final msg = ChatMessage(
      id: 'test-msg-1',
      endpointId: peerBFoundByA.endpointId,
      author: 'Dispositivo A',
      text: '¡Hola por socket LAN!',
      sentAt: DateTime.now(),
      direction: MessageDirection.outgoing,
    );
    await peerA.sendMessage(msg);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final receivedByB = eventsB.whereType<MessageReceived>().firstOrNull;
    expect(receivedByB, isNotNull);
    expect(receivedByB!.message.text, '¡Hola por socket LAN!');

    // 7. A edita el mensaje
    await peerA.sendEdit(
      endpointId: peerBFoundByA.endpointId,
      targetMessageId: 'test-msg-1',
      newText: '¡Mensaje editado con éxito!',
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final editReceivedByB = eventsB.whereType<MessageEdited>().firstOrNull;
    expect(editReceivedByB, isNotNull);
    expect(editReceivedByB!.newText, '¡Mensaje editado con éxito!');
    expect(editReceivedByB.targetMessageId, 'test-msg-1');
  });

  test('peer updates profile and notifies connected peers', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final clients = <String, Socket>{};

    server.listen((Socket socket) {
      String? clientId;
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        final msg = jsonDecode(line) as Map<String, dynamic>;
        final action = msg['action'] as String?;

        if (action == 'register') {
          clientId = msg['endpointId'] as String;
          final name = msg['name'] as String;
          clients[clientId!] = socket;

          for (final entry in clients.entries) {
            if (entry.key != clientId) {
              socket.write('${jsonEncode({
                    'action': 'peer_found',
                    'endpointId': entry.key,
                    'name': 'Peer ${entry.key}',
                  })}\n');
              entry.value.write('${jsonEncode({
                    'action': 'peer_found',
                    'endpointId': clientId,
                    'name': name,
                  })}\n');
            }
          }
        } else if (action == 'update_profile') {
          for (final entry in clients.entries) {
            if (entry.key != clientId) {
              entry.value.write('${jsonEncode({
                    'action': 'peer_updated',
                    'endpointId': clientId,
                    'name': msg['name'],
                    'avatar': msg['avatar'],
                  })}\n');
            }
          }
        }
      });
    });

    final peerA = LanSocketTransport(customHost: '127.0.0.1', port: port);
    final peerB = LanSocketTransport(customHost: '127.0.0.1', port: port);

    final eventsB = <NearbyEvent>[];
    final subB = peerB.events.listen(eventsB.add);

    addTearDown(() async {
      await subB.cancel();
      await peerA.dispose();
      await peerB.dispose();
      await server.close();
    });

    await peerA.start('Alpha');
    await peerB.start('Beta');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // A actualiza su avatar a un preset
    await peerA.sendProfileUpdate(avatar: 'preset:🚀', name: 'Alpha Actualizado');
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final updatedEvent = eventsB.whereType<PeerUpdated>().firstOrNull;
    expect(updatedEvent, isNotNull);
    expect(updatedEvent!.avatar, 'preset:🚀');
    expect(updatedEvent.name, 'Alpha Actualizado');
  });
}
