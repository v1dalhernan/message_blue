import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/chat_message.dart';
import 'nearby_event.dart';
import 'nearby_transport.dart';
import 'secure_session.dart';

class NearbyConnectionsTransport implements NearbyTransport {
  static const _serviceId = 'com.threedors.message_blue';
  static const _strategy = Strategy.P2P_CLUSTER;

  final Nearby _nearby = Nearby();
  final StreamController<NearbyEvent> _events =
      StreamController<NearbyEvent>.broadcast();
  final Map<String, Future<SecureSession>> _sessions = {};
  final Set<String> _keyExchangeSent = {};
  final Set<String> _secureEndpoints = {};

  bool _started = false;

  @override
  bool get isSupported => Platform.isAndroid;

  @override
  bool get isDemo => false;

  @override
  Stream<NearbyEvent> get events => _events.stream;

  @override
  Future<void> start(String displayName) async {
    if (_started) return;
    if (!isSupported) {
      throw const NearbySetupException(
        'Esta POC usa Nearby Connections y por ahora requiere Android.',
      );
    }

    await _requestRequiredPermissions();

    try {
      final results = await Future.wait([
        _nearby.startAdvertising(
          displayName,
          _strategy,
          onConnectionInitiated: _onConnectionInitiated,
          onConnectionResult: _onConnectionResult,
          onDisconnected: _onDisconnected,
          serviceId: _serviceId,
        ),
        _nearby.startDiscovery(
          displayName,
          _strategy,
          onEndpointFound: (endpointId, endpointName, serviceId) {
            if (serviceId == _serviceId) {
              _events.add(
                PeerFound(endpointId: endpointId, name: endpointName),
              );
            }
          },
          onEndpointLost: (endpointId) {
            if (endpointId != null) _events.add(PeerLost(endpointId));
          },
          serviceId: _serviceId,
        ),
      ]);

      if (results.any((started) => !started)) {
        await stop();
        throw const NearbySetupException(
          'No fue posible anunciar y buscar dispositivos cercanos.',
        );
      }
      _started = true;
    } catch (error) {
      await _safeStopRadioOperations();
      if (error is NearbySetupException) rethrow;
      throw NearbySetupException(_friendlyPlatformError(error));
    }
  }

  Future<void> _requestRequiredPermissions() async {
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    final permissions = <Permission>[];

    if (sdk <= 32) permissions.add(Permission.location);
    if (sdk >= 31) {
      permissions.addAll([
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ]);
    }
    if (sdk >= 33) permissions.add(Permission.nearbyWifiDevices);
    final statuses = await permissions.request();
    final denied = statuses.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key.toString().split('.').last)
        .toList();

    if (denied.isNotEmpty) {
      throw NearbySetupException(
        'Faltan permisos de dispositivos cercanos: ${denied.join(', ')}.',
      );
    }

    final locationEnabled = await Permission.location.serviceStatus.isEnabled;
    if (!locationEnabled) {
      throw const NearbySetupException(
        'Activa el servicio de ubicación del teléfono para mantener estable la conexión cercana.',
      );
    }
  }

  @override
  Future<void> requestConnection(String endpointId, String displayName) async {
    try {
      final requested = await _nearby.requestConnection(
        displayName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      if (!requested) {
        throw const NearbySetupException(
          'El dispositivo no pudo recibir la solicitud de conexión.',
        );
      }
    } catch (error) {
      if (error is NearbySetupException) rethrow;
      throw NearbySetupException(_friendlyPlatformError(error));
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    _events.add(
      ConnectionApprovalRequired(
        endpointId: endpointId,
        name: info.endpointName,
        authenticationToken: info.authenticationToken,
        isIncoming: info.isIncomingConnection,
      ),
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    final outcome = switch (status) {
      Status.CONNECTED => ConnectionOutcome.connected,
      Status.REJECTED => ConnectionOutcome.rejected,
      Status.ERROR => ConnectionOutcome.failed,
    };
    _events.add(ConnectionChanged(endpointId: endpointId, outcome: outcome));
    if (status == Status.CONNECTED) {
      unawaited(_sendKeyExchange(endpointId).catchError(_emitSecureError));
    } else {
      _clearSecureSession(endpointId);
    }
  }

  void _onDisconnected(String endpointId) {
    _clearSecureSession(endpointId);
    _events.add(
      ConnectionChanged(
        endpointId: endpointId,
        outcome: ConnectionOutcome.disconnected,
      ),
    );
  }

  @override
  Future<void> acceptConnection(String endpointId) async {
    final accepted = await _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: _onPayloadReceived,
    );
    if (!accepted) {
      throw const NearbySetupException('No se pudo aceptar la conexión.');
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;

    unawaited(_handleBytesPayload(endpointId, payload.bytes!));
  }

  Future<void> _handleBytesPayload(String endpointId, Uint8List bytes) async {
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

  Future<SecureSession> _sessionFor(String endpointId) {
    return _sessions.putIfAbsent(endpointId, SecureSession.create);
  }

  Future<void> _sendKeyExchange(String endpointId) async {
    if (!_keyExchangeSent.add(endpointId)) return;
    try {
      final session = await _sessionFor(endpointId);
      await _nearby.sendBytesPayload(
        endpointId,
        Uint8List.fromList(session.createKeyExchangePayload()),
      );
    } catch (_) {
      _keyExchangeSent.remove(endpointId);
      rethrow;
    }
  }

  void _emitSecureError(Object error) {
    _events.add(NearbyFailure('No se pudo crear el canal cifrado: $error'));
  }

  void _clearSecureSession(String endpointId) {
    _keyExchangeSent.remove(endpointId);
    _secureEndpoints.remove(endpointId);
    final session = _sessions.remove(endpointId);
    if (session != null) {
      unawaited(session.then((value) => value.dispose()));
    }
  }

  @override
  Future<void> rejectConnection(String endpointId) async {
    await _nearby.rejectConnection(endpointId);
  }

  @override
  Future<void> disconnect(String endpointId) {
    return _nearby.disconnectFromEndpoint(endpointId);
  }

  @override
  Future<void> sendMessage(ChatMessage message) {
    return _sendEncryptedMessage(message);
  }

  Future<void> _sendEncryptedMessage(ChatMessage message) async {
    final session = await _sessionFor(message.endpointId);
    if (!session.isReady) {
      throw const NearbySetupException(
        'El intercambio de claves todavía no ha terminado.',
      );
    }
    final encrypted = await session.encrypt(message.toPayload());
    await _nearby.sendBytesPayload(
      message.endpointId,
      Uint8List.fromList(encrypted),
    );
  }

  @override
  Future<void> stop() async {
    _started = false;
    await _safeStopRadioOperations();
    await _nearby.stopAllEndpoints();
    for (final endpointId in _sessions.keys.toList()) {
      _clearSecureSession(endpointId);
    }
  }

  Future<void> _safeStopRadioOperations() async {
    await Future.wait([
      _nearby.stopAdvertising().catchError((_) {}),
      _nearby.stopDiscovery().catchError((_) {}),
    ]);
  }

  String _friendlyPlatformError(Object error) {
    final message = error.toString();
    if (message.toLowerCase().contains('permission')) {
      return 'Android bloqueó un permiso necesario para buscar dispositivos cercanos.';
    }
    return 'No se pudo iniciar la red local: $message';
  }

  @override
  Future<void> dispose() async {
    if (_started) await stop();
    await _events.close();
  }
}
