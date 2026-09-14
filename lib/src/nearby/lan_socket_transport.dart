import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../models/chat_message.dart';
import 'nearby_event.dart';
import 'nearby_transport.dart';
import 'secure_session.dart';

class LanSocketTransport implements NearbyTransport {
  LanSocketTransport({this.customHost, this.port = 8765});

  final String? customHost;
  final int port;

  final StreamController<NearbyEvent> _events =
      StreamController<NearbyEvent>.broadcast();
  final Map<String, Future<SecureSession>> _sessions = {};
  final Set<String> _keyExchangeSent = {};
  final Set<String> _secureEndpoints = {};
  final Map<String, String> _peerNames = {};

  Socket? _socket;
  String _localId = '';
  bool _running = false;
  StreamSubscription<String>? _socketSub;

  @override
  bool get isSupported => true;

  @override
  bool get isDemo => false;

  @override
  Stream<NearbyEvent> get events => _events.stream;

  String get _targetHost {
    if (customHost != null && customHost!.isNotEmpty) return customHost!;
    const envHost = String.fromEnvironment('HUB_HOST');
    if (envHost.isNotEmpty) return envHost;
    // En emulador Android, 10.0.2.2 apunta al localhost de la máquina host (Mac/PC)
    return Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';
  }

  @override
  Future<void> start(String displayName) async {
    if (_running) return;
    _localId = 'lan-${DateTime.now().microsecondsSinceEpoch % 1000000}';

    try {
      _socket = await Socket.connect(_targetHost, port,
          timeout: const Duration(seconds: 4));
    } catch (e) {
      throw NearbySetupException(
        'No se pudo conectar al LAN Dev Hub en $_targetHost:$port.\n'
        'Asegúrate de ejecutar primero en tu terminal: dart run bin/lan_hub.dart',
      );
    }

    _running = true;
    _socketSub = _socket!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleFrame,
          onDone: () => stop(),
          onError: (e) {
            _events.add(NearbyFailure('Error de conexión LAN: $e'));
            stop();
          },
        );

    _sendFrame({
      'action': 'register',
      'endpointId': _localId,
      'name': displayName,
    });
  }

  void _handleFrame(String line) {
    if (!_running || line.trim().isEmpty) return;
    try {
      final msg = jsonDecode(line) as Map<String, dynamic>;
      final action = msg['action'] as String?;

      switch (action) {
        case 'peer_found':
          final id = msg['endpointId'] as String;
          final name = msg['name'] as String;
          _peerNames[id] = name;
          _events.add(PeerFound(endpointId: id, name: name));

        case 'peer_lost':
          final id = msg['endpointId'] as String;
          _peerNames.remove(id);
          _clearSecureSession(id);
          _events.add(PeerLost(id));

        case 'connect_request':
          final from = msg['from'] as String;
          final fromName = msg['fromName'] as String;
          final token = msg['token'] as String;
          _peerNames[from] = fromName;
          _events.add(
            ConnectionApprovalRequired(
              endpointId: from,
              name: fromName,
              authenticationToken: token,
              isIncoming: true,
            ),
          );

        case 'connect_response':
          final from = msg['from'] as String;
          final accepted = msg['accepted'] as bool;
          if (accepted) {
            _events.add(
              ConnectionChanged(
                endpointId: from,
                outcome: ConnectionOutcome.connected,
              ),
            );
            unawaited(_sendKeyExchange(from).catchError(_emitSecureError));
          } else {
            _events.add(
              ConnectionChanged(
                endpointId: from,
                outcome: ConnectionOutcome.rejected,
              ),
            );
          }

        case 'data':
          final from = msg['from'] as String;
          final bytesBase64 = msg['bytes'] as String;
          final bytes = base64Decode(bytesBase64);
          unawaited(_handleBytesPayload(from, bytes));

        case 'disconnect':
          final from = msg['from'] as String;
          _clearSecureSession(from);
          _events.add(
            ConnectionChanged(
              endpointId: from,
              outcome: ConnectionOutcome.disconnected,
            ),
          );
      }
    } catch (e) {
      _events.add(NearbyFailure('Error procesando mensaje: $e'));
    }
  }

  Future<void> _handleBytesPayload(String endpointId, List<int> bytes) async {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic> &&
          SecureSession.isKeyExchangePayload(decoded)) {
        final session = await _sessionFor(endpointId);
        await session.establish(SecureSession.keyFromPayload(decoded));
        await _sendKeyExchange(endpointId);
        if (_secureEndpoints.add(endpointId)) {
          _events.add(SecureChannelReady(endpointId));
        }
        return;
      }

      final session = await _sessionFor(endpointId);
      final clearText = await session.decrypt(bytes);
      final jsonPayload = jsonDecode(utf8.decode(clearText));

      if (jsonPayload is Map<String, dynamic> && jsonPayload['type'] == 'edit') {
        final edit = ChatMessageEdit.fromJson(jsonPayload);
        _events.add(
          MessageEdited(
            endpointId: endpointId,
            targetMessageId: edit.targetId,
            newText: edit.text,
            editedAt: edit.editedAt,
          ),
        );
        return;
      }

      final message = ChatMessage.fromPayload(
        endpointId: endpointId,
        bytes: clearText,
      );
      _events.add(MessageReceived(message));
    } on SecretBoxAuthenticationError {
      _events.add(
        const NearbyFailure(
          'Se rechazó un mensaje porque su autenticación cifrada no es válida.',
        ),
      );
    } on FormatException catch (error) {
      _events.add(NearbyFailure(error.message));
    } catch (_) {
      _events.add(
        const NearbyFailure('Se recibió un mensaje que no se pudo descifrar.'),
      );
    }
  }

  @override
  Future<void> requestConnection(String endpointId, String displayName) async {
    final token =
        '${(endpointId.hashCode.abs() % 900000 + 100000)}'; // Token visual de 6 dígitos
    _sendFrame({
      'action': 'connect_request',
      'from': _localId,
      'fromName': displayName,
      'to': endpointId,
      'token': token,
    });
    _events.add(
      ConnectionApprovalRequired(
        endpointId: endpointId,
        name: _peerNames[endpointId] ?? 'Dispositivo',
        authenticationToken: token,
        isIncoming: false,
      ),
    );
  }

  @override
  Future<void> acceptConnection(String endpointId) async {
    _sendFrame({
      'action': 'connect_response',
      'from': _localId,
      'to': endpointId,
      'accepted': true,
    });
    _events.add(
      ConnectionChanged(
        endpointId: endpointId,
        outcome: ConnectionOutcome.connected,
      ),
    );
    unawaited(_sendKeyExchange(endpointId).catchError(_emitSecureError));
  }

  @override
  Future<void> rejectConnection(String endpointId) async {
    _sendFrame({
      'action': 'connect_response',
      'from': _localId,
      'to': endpointId,
      'accepted': false,
    });
    _events.add(
      ConnectionChanged(
        endpointId: endpointId,
        outcome: ConnectionOutcome.rejected,
      ),
    );
  }

  @override
  Future<void> disconnect(String endpointId) async {
    _sendFrame({
      'action': 'disconnect',
      'from': _localId,
      'to': endpointId,
    });
    _clearSecureSession(endpointId);
    _events.add(
      ConnectionChanged(
        endpointId: endpointId,
        outcome: ConnectionOutcome.disconnected,
      ),
    );
  }

  @override
  Future<void> sendMessage(ChatMessage message) async {
    final session = await _sessionFor(message.endpointId);
    if (!session.isReady) {
      throw const NearbySetupException(
        'El canal cifrado aún no está listo.',
      );
    }
    final encrypted = await session.encrypt(message.toPayload());
    _sendFrame({
      'action': 'data',
      'from': _localId,
      'to': message.endpointId,
      'bytes': base64Encode(encrypted),
    });
  }

  @override
  Future<void> sendEdit({
    required String endpointId,
    required String targetMessageId,
    required String newText,
  }) async {
    final session = await _sessionFor(endpointId);
    if (!session.isReady) {
      throw const NearbySetupException(
        'El canal cifrado aún no está listo.',
      );
    }
    final edit = ChatMessageEdit(
      id: 'edit-${DateTime.now().microsecondsSinceEpoch}',
      targetId: targetMessageId,
      text: newText,
      editedAt: DateTime.now(),
    );
    final encrypted = await session.encrypt(edit.toPayload());
    _sendFrame({
      'action': 'data',
      'from': _localId,
      'to': endpointId,
      'bytes': base64Encode(encrypted),
    });
  }

  Future<SecureSession> _sessionFor(String endpointId) {
    return _sessions.putIfAbsent(endpointId, SecureSession.create);
  }

  Future<void> _sendKeyExchange(String endpointId) async {
    if (!_keyExchangeSent.add(endpointId)) return;
    try {
      final session = await _sessionFor(endpointId);
      final payload = session.createKeyExchangePayload();
      _sendFrame({
        'action': 'data',
        'from': _localId,
        'to': endpointId,
        'bytes': base64Encode(payload),
      });
    } catch (_) {
      _keyExchangeSent.remove(endpointId);
      rethrow;
    }
  }

  void _clearSecureSession(String endpointId) {
    _keyExchangeSent.remove(endpointId);
    _secureEndpoints.remove(endpointId);
    final session = _sessions.remove(endpointId);
    if (session != null) {
      unawaited(session.then((v) => v.dispose()));
    }
  }

  void _sendFrame(Map<String, dynamic> data) {
    if (_socket == null) return;
    try {
      _socket!.write('${jsonEncode(data)}\n');
    } catch (_) {}
  }

  void _emitSecureError(Object error) {
    _events.add(NearbyFailure('Error creando canal cifrado: $error'));
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _socketSub?.cancel();
    _socketSub = null;
    await _socket?.close();
    _socket = null;
    for (final id in _sessions.keys.toList()) {
      _clearSecureSession(id);
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _events.close();
  }
}
