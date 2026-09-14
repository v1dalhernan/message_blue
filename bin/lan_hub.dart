// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Servidor de retransmisión local (Dev Relay Hub) para BlueMesh.
/// Permite que dos o más emuladores de Android (o instancias de macOS/iOS)
/// se descubran y comuniquen localmente en tu computadora sin hardware Bluetooth.
///
/// Soporta:
/// 1. Registro con ID único criptográfico, avatar de perfil y PIN personal.
/// 2. Verificación de código PIN introducido por el solicitante.
/// 3. Buzón Store-and-Forward para mensajes a dispositivos fuera de línea.
/// 4. Retransmisión transparente de paquetes E2EE y telemetría IoT.
void main(List<String> args) {
  runZonedGuarded(() async {
    final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8765;
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    print('====================================================');
    print('🌐 BlueMesh Dev LAN Hub activo en el puerto $port');
    print('   - En emuladores Android: conecta a 10.0.2.2:$port');
    print('   - En macOS / iOS Simulator: conecta a 127.0.0.1:$port');
    print('====================================================');

    final clients = <String, _ConnectedClient>{};
    final mailbox = <String, List<Map<String, dynamic>>>{}; // targetId -> list of frames

    server.listen((Socket socket) {
      _ConnectedClient? currentClient;
      socket.done.catchError((_) => null);

      socket
          .cast<List<int>>()
          .handleError((Object e) {
            if (currentClient != null) {
              clients.remove(currentClient!.id);
            }
          })
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.trim().isEmpty) return;
          try {
            final msg = jsonDecode(line) as Map<String, dynamic>;
            final action = msg['action'] as String?;

            switch (action) {
              case 'register':
                final id = msg['endpointId'] as String;
                final name = msg['name'] as String;
                final uniqueId = msg['uniqueId'] as String?;
                final avatar = msg['avatar'] as String?;
                final pin = msg['pin'] as String?;

                currentClient = _ConnectedClient(
                  id: id,
                  name: name,
                  socket: socket,
                  uniqueId: uniqueId,
                  avatar: avatar,
                  pin: pin,
                );
                clients[id] = currentClient!;
                print('🟢 Dispositivo registrado: $name ($id) [ID: $uniqueId, PIN: $pin]');

                // Entregar mensajes pendientes del buzón offline si existen
                if (mailbox.containsKey(id)) {
                  final pendingList = mailbox[id]!;
                  print('📬 Entregando ${pendingList.length} mensajes pendientes del buzón para $name ($id)');
                  for (final pending in pendingList) {
                    currentClient!.send(pending);
                  }
                  mailbox.remove(id);
                }

                // Notificar al nuevo cliente de los peers existentes
                for (final peer in clients.values) {
                  if (peer.id != id) {
                    currentClient!.send({
                      'action': 'peer_found',
                      'endpointId': peer.id,
                      'name': peer.name,
                      'uniqueId': peer.uniqueId,
                      'avatar': peer.avatar,
                      'pin': peer.pin,
                    });
                    // Notificar al peer existente del nuevo cliente
                    peer.send({
                      'action': 'peer_found',
                      'endpointId': id,
                      'name': name,
                      'uniqueId': uniqueId,
                      'avatar': avatar,
                      'pin': pin,
                    });
                  }
                }

              case 'connect_request':
                final to = msg['to'] as String;
                final target = clients[to];
                if (target != null) {
                  print('🤝 Solicitud de conexión de ${currentClient?.name} a ${target.name} con código');
                  target.send(msg);
                }

              case 'connect_response':
                final to = msg['to'] as String;
                final target = clients[to];
                if (target != null) {
                  print('✅ Respuesta de conexión de ${currentClient?.name} a ${target.name}');
                  target.send(msg);
                }

              case 'data':
                final to = msg['to'] as String;
                final target = clients[to];
                if (target != null) {
                  target.send(msg);
                } else {
                  // Destinatario offline: guardar en buzón Store-and-Forward
                  print('📦 Destinatario $to offline. Guardando mensaje en buzón de la malla.');
                  mailbox.putIfAbsent(to, () => []).add(msg);
                }

              case 'update_profile':
                if (currentClient != null) {
                  final newName = msg['name'] as String?;
                  final newAvatar = msg['avatar'] as String?;
                  if (newName != null && newName.isNotEmpty) {
                    currentClient!.name = newName;
                  }
                  if (newAvatar != null) {
                    currentClient!.avatar = newAvatar;
                  }
                  print('👤 Perfil actualizado para ${currentClient!.name} (${currentClient!.id})');
                  for (final peer in clients.values) {
                    if (peer.id != currentClient!.id) {
                      peer.send({
                        'action': 'peer_updated',
                        'endpointId': currentClient!.id,
                        'name': currentClient!.name,
                        'avatar': currentClient!.avatar,
                        'uniqueId': currentClient!.uniqueId,
                      });
                    }
                  }
                }

              case 'disconnect':
                final to = msg['to'] as String;
                final target = clients[to];
                if (target != null) {
                  target.send(msg);
                }
            }
          } catch (e) {
            print('⚠️ Error procesando frame: $e');
          }
        },
        onDone: () {
          if (currentClient != null) {
            print('🔴 Desconectado: ${currentClient!.name} (${currentClient!.id})');
            clients.remove(currentClient!.id);
            for (final peer in clients.values) {
              peer.send({
                'action': 'peer_lost',
                'endpointId': currentClient!.id,
              });
            }
          }
        },
        onError: (e) {
          if (currentClient != null) {
            clients.remove(currentClient!.id);
          }
        },
      );
    });
  }, (error, stack) {
    print('ℹ️ Hub red resiliente: $error');
  });
}

class _ConnectedClient {
  _ConnectedClient({
    required this.id,
    required this.name,
    required this.socket,
    this.uniqueId,
    this.avatar,
    this.pin,
  });

  final String id;
  String name;
  final Socket socket;
  final String? uniqueId;
  String? avatar;
  final String? pin;

  void send(Map<String, dynamic> data) {
    try {
      socket.write('${jsonEncode(data)}\n');
    } catch (_) {}
  }
}
