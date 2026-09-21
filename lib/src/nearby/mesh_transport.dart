import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../core/identity/user_identity_service.dart';
import '../models/chat_message.dart';
import 'nearby_event.dart';
import 'nearby_transport.dart';
import 'secure_session.dart';

/// End-to-end overlay over authenticated radio/LAN links. A relay only sees
/// addresses and ciphertext. Node addresses are hashes of their public keys.
class MeshTransport implements NearbyTransport {
  MeshTransport(this.link, {this.identitySecret, this.validatePin});

  final NearbyTransport link;
  final String? identitySecret;
  final bool Function(String)? validatePin;
  final _events = StreamController<NearbyEvent>.broadcast();
  final _links = <String>{};
  final _nodes = <String, _MeshNode>{};
  final _seen = <String>{};
  final _receivedMessages = <String>{};
  final _blocked = <String>{};
  final _approved = <String>{};
  final _localConsent = <String>{};
  final _remoteConsent = <String>{};
  final _pending = <String, Completer<void>>{};
  StreamSubscription<NearbyEvent>? _subscription;
  Timer? _beacon;
  Future<void> _queue = Future.value();
  late List<int> _seed;
  late List<int> _publicKey;
  String localId = '';
  String _name = '';
  String? _avatar;
  bool _running = false;

  @override
  bool get isSupported => link.isSupported;
  @override
  bool get isDemo => link.isDemo;
  @override
  Stream<NearbyEvent> get events => _events.stream;

  String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  static Future<String> _address(List<int> key) async =>
      'mesh-${base64UrlEncode((await Sha256().hash(key)).bytes).replaceAll('=', '')}';

  @override
  Future<void> start(String displayName) async {
    if (_running) return;
    _name = displayName;
    _seed = (await Sha256().hash(
      utf8.encode(
        'trama-mesh-key-v1:${identitySecret ?? UserIdentityService.instance.deviceSecret}',
      ),
    )).bytes;
    final identity = await SecureSession.create(seed: _seed);
    _publicKey = identity.publicKeyBytes;
    localId = await _address(_publicKey);
    identity.dispose();
    _running = true;
    _subscription = link.events.listen((event) {
      _queue = _queue
          .then((_) async {
            if (_running) await _handle(event);
          })
          .catchError((Object error) {
            if (_running) _events.add(NearbyFailure('Red en malla: $error'));
          });
    });
    try {
      await link.start(displayName);
      _beacon = Timer.periodic(const Duration(seconds: 15), (_) {
        _queue = _queue
            .then((_) async {
              if (!_running) return;
              _expireRoutes();
              await _announce();
            })
            .catchError((Object error) {
              if (_running) {
                _events.add(NearbyFailure('Anuncio de malla: $error'));
              }
            });
      });
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<void> _handle(NearbyEvent event) async {
    if (event is SecureChannelReady) {
      _links.add(event.endpointId);
      await _announce();
      await _forward({
        'protocol': 'trama-mesh-1',
        'kind': 'probe',
        'id': _id(),
        'source': localId,
        'path': [localId],
      });
      return;
    }
    if (event is ConnectionChanged &&
        event.outcome != ConnectionOutcome.connected) {
      _links.remove(event.endpointId);
      for (final node in _nodes.values) {
        node.routes.remove(event.endpointId);
      }
      _expireRoutes();
    }
    if (event is MessageReceived) {
      if (!_links.contains(event.message.endpointId)) return;
      final raw = jsonDecode(event.message.text);
      if (raw is! Map<String, dynamic> || raw['protocol'] != 'trama-mesh-1') {
        return;
      }
      await _receive(raw, event.message.endpointId);
      return;
    }
    _events.add(event);
  }

  Future<void> _announce() async {
    final packet = <String, dynamic>{
      'protocol': 'trama-mesh-1',
      'kind': 'hello',
      'id': _id(),
      'source': localId,
      'name': _name,
      'key': base64Encode(_publicKey),
      if (_avatar != null) 'avatar': _avatar,
      'path': [localId],
    };
    await _forward(packet);
  }

  Future<void> _receive(Map<String, dynamic> packet, String via) async {
    final id = packet['id'];
    final source = packet['source'];
    final path = (packet['path'] as List<dynamic>).cast<String>();
    if (id is! String ||
        source is! String ||
        path.isEmpty ||
        path.length > 6 ||
        path.first != source ||
        path.contains(localId)) {
      return;
    }
    // Reserve before any async operation so simultaneous links cannot duplicate.
    if (!_seen.add(id)) return;
    if (_seen.length > 12000) _seen.remove(_seen.first);
    if (packet['kind'] == 'hello') {
      final key = base64Decode(packet['key'] as String);
      if (key.length != 32 || await _address(key) != source) return;
      var node = _nodes[source];
      if (node == null) {
        if (_nodes.length >= 256) return;
        final session = await SecureSession.create(seed: _seed);
        await session.establish(key);
        node = _MeshNode(session, key, packet['name'] as String);
        _nodes[source] = node;
      }
      final hadRoute = node.routes.isNotEmpty;
      node.name = packet['name'] as String;
      node.routes[via] = _Route(path.length, DateTime.now());
      _events.add(
        PeerFound(
          endpointId: source,
          name: node.name,
          uniqueId: source,
          avatar: packet['avatar'] as String?,
        ),
      );
      if (path.length == 1 && !_blocked.contains(source)) {
        // This direct link was already approved by its two users.
        _approved.add(source);
        _events.add(
          ConnectionChanged(
            endpointId: via,
            outcome: ConnectionOutcome.disconnected,
          ),
        );
        _events.add(PeerLost(via));
      }
      if (_approved.contains(source)) {
        _events.add(SecureChannelReady(source));
      }
      if (!hadRoute) await _announce();
    } else if (packet['kind'] == 'probe') {
      await _announce();
    } else if (packet['to'] == localId) {
      final node = _nodes[source];
      if (node == null) {
        await _announce();
        return;
      }
      final clear = await node.session.decrypt(
        base64Decode(packet['body'] as String),
      );
      final content = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      if (content['source'] != source ||
          content['to'] != localId ||
          content['id'] != id) {
        return;
      }
      await _deliver(source, content);
      return;
    }
    if (path.length < 6) {
      await _forward({
        ...packet,
        'path': [...path, localId],
      }, except: via);
    }
  }

  Future<void> _deliver(String source, Map<String, dynamic> content) async {
    final node = _nodes[source]!;
    switch (content['kind']) {
      case 'request':
        final pin = content['pin'] as String?;
        if (pin != null) {
          if (!(validatePin ?? UserIdentityService.instance.isValidPin)(pin)) {
            await _send(source, {'kind': 'reject'});
            return;
          }
          _localConsent.add(source);
          _remoteConsent.add(source);
          await _send(source, {'kind': 'accept'});
          _ready(source);
        } else {
          _events.add(
            ConnectionApprovalRequired(
              endpointId: source,
              name: node.name,
              authenticationToken: await node.session.deriveSixDigitPin(
                node.key,
              ),
              isIncoming: true,
            ),
          );
        }
      case 'accept':
        _remoteConsent.add(source);
        _ready(source);
      case 'reject':
        _blocked.add(source);
        _approved.remove(source);
        _localConsent.remove(source);
        _remoteConsent.remove(source);
        _events.add(
          ConnectionChanged(
            endpointId: source,
            outcome: ConnectionOutcome.rejected,
          ),
        );
      case 'message':
        if (!_approved.contains(source)) return;
        final message = ChatMessage.fromPayload(
          endpointId: source,
          bytes: base64Decode(content['payload'] as String),
        );
        if (_receivedMessages.add('$source:${message.id}')) {
          _events.add(MessageReceived(message));
          if (_receivedMessages.length > 12000) {
            _receivedMessages.remove(_receivedMessages.first);
          }
        }
        try {
          await _send(source, {'kind': 'ack', 'messageId': message.id});
        } on NearbySetupException {
          // A route may be rebuilding after reconnect. The sender retries with
          // the same message ID, which is acknowledged without redisplaying it.
        }
      case 'ack':
        if (!_approved.contains(source)) return;
        final pending = _pending['$source:${content['messageId']}'];
        if (pending != null && !pending.isCompleted) pending.complete();
      case 'edit':
        if (!_approved.contains(source)) return;
        final edit = ChatMessageEdit.fromJson(
          content['edit'] as Map<String, dynamic>,
        );
        _events.add(
          MessageEdited(
            endpointId: source,
            targetMessageId: edit.targetId,
            newText: edit.text,
            editedAt: edit.editedAt,
          ),
        );
      case 'read':
        if (!_approved.contains(source)) return;
        _events.add(
          MessageReadReceipt(
            endpointId: source,
            messageId: content['messageId'] as String,
          ),
        );
    }
  }

  void _ready(String source) {
    if (_localConsent.contains(source) && _remoteConsent.contains(source)) {
      _approved.add(source);
      _blocked.remove(source);
      _events.add(SecureChannelReady(source));
    }
  }

  Future<void> _send(String to, Map<String, dynamic> content) async {
    final node = _nodes[to];
    if (node == null || node.routes.isEmpty) {
      throw const NearbySetupException(
        'No hay una ruta disponible al destinatario.',
      );
    }
    final id = _id();
    final body = await node.session.encrypt(
      utf8.encode(
        jsonEncode({...content, 'id': id, 'source': localId, 'to': to}),
      ),
    );
    await _forward({
      'protocol': 'trama-mesh-1',
      'kind': 'sealed',
      'id': id,
      'source': localId,
      'to': to,
      'body': base64Encode(body),
      'path': [localId],
    });
  }

  Future<void> _forward(Map<String, dynamic> packet, {String? except}) async {
    var targets = _links.where((id) => id != except).toList();
    final routes = _nodes[packet['to']]?.routes.entries
        .where((entry) => targets.contains(entry.key))
        .toList();
    routes?.sort((a, b) => a.value.hops.compareTo(b.value.hops));
    if (routes != null && routes.isNotEmpty) {
      targets = routes.map((e) => e.key).toList();
    }
    var sent = false;
    for (final target in targets) {
      try {
        await link.sendMessage(
          ChatMessage(
            id: packet['id'] as String,
            endpointId: target,
            author: _name,
            text: jsonEncode(packet),
            sentAt: DateTime.now(),
            direction: MessageDirection.outgoing,
          ),
        );
        sent = true;
        if (packet['kind'] == 'sealed' && routes != null && routes.isNotEmpty) {
          break;
        }
      } catch (_) {
        /* Try another live route. */
      }
    }
    if (!sent && packet['kind'] == 'sealed' && except == null) {
      throw const NearbySetupException(
        'La ruta se interrumpió. Reintenta cuando vuelva un enlace.',
      );
    }
  }

  void _expireRoutes() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 50));
    for (final entry in _nodes.entries) {
      entry.value.routes.removeWhere(
        (link, route) => !_links.contains(link) || route.seen.isBefore(cutoff),
      );
      if (entry.value.routes.isEmpty) {
        _events.add(
          ConnectionChanged(
            endpointId: entry.key,
            outcome: ConnectionOutcome.disconnected,
          ),
        );
      }
    }
  }

  @override
  Future<void> requestConnection(
    String endpointId,
    String displayName, {
    String? enteredCode,
  }) async {
    if (!_nodes.containsKey(endpointId)) {
      await link.requestConnection(
        endpointId,
        displayName,
        enteredCode: enteredCode,
      );
      return;
    }
    _localConsent.remove(endpointId);
    _remoteConsent.remove(endpointId);
    if (enteredCode != null) _localConsent.add(endpointId);
    await _send(endpointId, {'kind': 'request', 'pin': ?enteredCode});
    if (enteredCode == null) {
      final node = _nodes[endpointId]!;
      _events.add(
        ConnectionApprovalRequired(
          endpointId: endpointId,
          name: node.name,
          authenticationToken: await node.session.deriveSixDigitPin(node.key),
          isIncoming: false,
        ),
      );
    }
  }

  @override
  Future<void> acceptConnection(String endpointId) async {
    if (!_nodes.containsKey(endpointId)) {
      return link.acceptConnection(endpointId);
    }
    _localConsent.add(endpointId);
    await _send(endpointId, {'kind': 'accept'});
    _ready(endpointId);
  }

  @override
  Future<void> rejectConnection(String endpointId) async {
    if (!_nodes.containsKey(endpointId)) {
      return link.rejectConnection(endpointId);
    }
    await _send(endpointId, {'kind': 'reject'});
    _approved.remove(endpointId);
    _blocked.add(endpointId);
    _localConsent.remove(endpointId);
    _remoteConsent.remove(endpointId);
    _events.add(
      ConnectionChanged(
        endpointId: endpointId,
        outcome: ConnectionOutcome.rejected,
      ),
    );
  }

  @override
  Future<void> disconnect(String endpointId) async {
    if (!_nodes.containsKey(endpointId)) return link.disconnect(endpointId);
    await rejectConnection(endpointId);
  }

  @override
  Future<void> sendMessage(ChatMessage message) async {
    if (!_approved.contains(message.endpointId)) {
      throw const NearbySetupException('Verifica primero el destinatario.');
    }
    final key = '${message.endpointId}:${message.id}';
    final ack = Completer<void>();
    if (_pending.containsKey(key)) {
      throw const NearbySetupException('El mensaje ya se está enviando.');
    }
    _pending[key] = ack;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        await _send(message.endpointId, {
          'kind': 'message',
          'payload': base64Encode(message.toPayload()),
        });
        try {
          await ack.future.timeout(const Duration(seconds: 5));
          return;
        } on TimeoutException {
          if (attempt == 2) {
            throw const NearbySetupException(
              'El destinatario no confirmó la recepción.',
            );
          }
        }
      }
    } finally {
      _pending.remove(key);
    }
  }

  @override
  Future<void> sendEdit({
    required String endpointId,
    required String targetMessageId,
    required String newText,
  }) => _send(endpointId, {
    'kind': 'edit',
    'edit': jsonDecode(
      utf8.decode(
        ChatMessageEdit(
          id: _id(),
          targetId: targetMessageId,
          text: newText,
          editedAt: DateTime.now(),
        ).toPayload(),
      ),
    ),
  });
  @override
  Future<void> sendReadReceipt(String endpointId, String messageId) async {
    if (_approved.contains(endpointId)) {
      await _send(endpointId, {'kind': 'read', 'messageId': messageId});
    }
  }

  @override
  Future<void> sendProfileUpdate({String? name, String? avatar}) async {
    if (name != null) _name = name;
    if (avatar != null) _avatar = avatar;
    if (_running) await _announce();
  }

  @override
  Future<void> stop() async {
    _running = false;
    _beacon?.cancel();
    await _subscription?.cancel();
    await _queue;
    await link.stop();
    for (final node in _nodes.values) {
      node.session.dispose();
    }
    _nodes.clear();
    _links.clear();
    _seen.clear();
    _receivedMessages.clear();
    _blocked.clear();
    _approved.clear();
    _localConsent.clear();
    _remoteConsent.clear();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await link.dispose();
    await _events.close();
  }
}

class _MeshNode {
  _MeshNode(this.session, this.key, this.name);
  final SecureSession session;
  final List<int> key;
  String name;
  final routes = <String, _Route>{};
}

class _Route {
  _Route(this.hops, this.seen);
  final int hops;
  final DateTime seen;
}
