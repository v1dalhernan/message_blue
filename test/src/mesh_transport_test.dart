import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:message_blue/src/models/chat_message.dart';
import 'package:message_blue/src/nearby/mesh_transport.dart';
import 'package:message_blue/src/nearby/nearby_event.dart';
import 'package:message_blue/src/nearby/nearby_transport.dart';

void main() {
  test('A sends encrypted text, media, edits and receipts to C only through B', () async {
    final aLink = _Link('A');
    final bLink = _Link('B');
    final cLink = _Link('C');
    final a = MeshTransport(aLink, identitySecret: 'alpha');
    final b = MeshTransport(bLink, identitySecret: 'beta');
    final c = MeshTransport(
      cLink,
      identitySecret: 'gamma',
      validatePin: (pin) => pin == '123456',
    );
    final eventsA = <NearbyEvent>[];
    final eventsB = <NearbyEvent>[];
    final eventsC = <NearbyEvent>[];
    a.events.listen(eventsA.add);
    b.events.listen(eventsB.add);
    c.events.listen(eventsC.add);
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
      await c.dispose();
    });
    await a.start('Alice');
    await b.start('Bridge');
    await c.start('Carol');
    aLink.connect(bLink);
    bLink.connect(cLink);
    await _until(
      () =>
          eventsA.whereType<PeerFound>().any((p) => p.endpointId == c.localId),
    );
    await _until(
      () =>
          eventsC.whereType<PeerFound>().any((p) => p.endpointId == a.localId),
    );
    expect(
      eventsA.whereType<SecureChannelReady>().any(
        (e) => e.endpointId == c.localId,
      ),
      isFalse,
    );
    await a.requestConnection(c.localId, 'Alice', enteredCode: '000000');
    await _until(
      () => eventsA.whereType<ConnectionChanged>().any(
        (e) =>
            e.endpointId == c.localId &&
            e.outcome == ConnectionOutcome.rejected,
      ),
    );
    await a.requestConnection(c.localId, 'Alice', enteredCode: '123456');
    await _until(
      () => eventsA.whereType<SecureChannelReady>().any(
        (e) => e.endpointId == c.localId,
      ),
    );
    final message = ChatMessage(
      id: 'private-1',
      endpointId: c.localId,
      author: 'Alice',
      text: 'Un secreto para Carol',
      sentAt: DateTime.now(),
      direction: MessageDirection.outgoing,
    );
    await a.sendMessage(message).catchError((Object error) {
      fail(
        'Initial delivery: $error; A=${eventsA.whereType<NearbyFailure>().map((e) => e.message).toList()}; B=${eventsB.whereType<NearbyFailure>().map((e) => e.message).toList()}; C=${eventsC.whereType<NearbyFailure>().map((e) => e.message).toList()}',
      );
    });
    expect(
      eventsC.whereType<MessageReceived>().single.message.text,
      message.text,
    );
    expect(
      eventsC.whereType<MessageReceived>().single.message.endpointId,
      a.localId,
    );
    expect(eventsB.whereType<MessageReceived>(), isEmpty);
    expect(
      bLink.wire.any((m) => m.text.contains('Un secreto para Carol')),
      isFalse,
    );
    expect(aLink.neighbors.keys, ['B']);
    await c.sendReadReceipt(a.localId, message.id);
    await _until(() => eventsA.whereType<MessageReadReceipt>().isNotEmpty);
    expect(
      eventsA.whereType<MessageReadReceipt>().single.endpointId,
      c.localId,
    );
    await a.sendEdit(
      endpointId: c.localId,
      targetMessageId: message.id,
      newText: 'Corregido',
    );
    await _until(() => eventsC.whereType<MessageEdited>().isNotEmpty);
    expect(eventsC.whereType<MessageEdited>().single.newText, 'Corregido');
    await a.sendMessage(
      ChatMessage(
        id: 'photo',
        endpointId: c.localId,
        author: 'Alice',
        text: '',
        sentAt: DateTime.now(),
        direction: MessageDirection.outgoing,
        type: ChatMessageType.image,
        mediaBase64: 'AQID',
      ),
    );
    expect(
      eventsC.whereType<MessageReceived>().last.message.mediaBase64,
      'AQID',
    );
    bLink.disconnectLink(cLink);
    await _until(
      () => eventsB.whereType<ConnectionChanged>().any(
        (e) =>
            e.endpointId == c.localId &&
            e.outcome == ConnectionOutcome.disconnected,
      ),
    );
    // A's stale route must not report successful delivery when the bridge breaks.
    // Reconnect before retrying; the destination keeps its stable node address.
    bLink.connect(cLink);
    await _until(
      () =>
          eventsB
              .whereType<SecureChannelReady>()
              .where((e) => e.endpointId == c.localId)
              .length >=
          2,
    );
    await a.sendMessage(message.copyWith(text: 'Un secreto para Carol'));
    expect(
      eventsC
          .whereType<MessageReceived>()
          .where((e) => e.message.id == message.id)
          .length,
      1,
    );
    expect(eventsA.whereType<NearbyFailure>(), isEmpty);
    expect(eventsB.whereType<NearbyFailure>(), isEmpty);
    expect(eventsC.whereType<NearbyFailure>(), isEmpty);
  });

  test(
    'manual routed pairing derives the same code and needs both approvals',
    () async {
      final links = [_Link('a'), _Link('b'), _Link('c')];
      final nodes = [
        for (var i = 0; i < 3; i++)
          MeshTransport(links[i], identitySecret: 'seed-$i'),
      ];
      final logs = [<NearbyEvent>[], <NearbyEvent>[], <NearbyEvent>[]];
      for (var i = 0; i < 3; i++) {
        nodes[i].events.listen(logs[i].add);
        await nodes[i].start('node-$i');
      }
      addTearDown(() async {
        for (final node in nodes) {
          await node.dispose();
        }
      });
      links[0].connect(links[1]);
      links[1].connect(links[2]);
      await _until(
        () => logs[0].whereType<PeerFound>().any(
          (p) => p.endpointId == nodes[2].localId,
        ),
      );
      await nodes[0].requestConnection(nodes[2].localId, 'node-0');
      await _until(
        () => logs[2].whereType<ConnectionApprovalRequired>().isNotEmpty,
      );
      expect(
        logs[0]
            .whereType<ConnectionApprovalRequired>()
            .last
            .authenticationToken,
        logs[2]
            .whereType<ConnectionApprovalRequired>()
            .last
            .authenticationToken,
      );
      await nodes[2].acceptConnection(nodes[0].localId);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        logs[0].whereType<SecureChannelReady>().any(
          (e) => e.endpointId == nodes[2].localId,
        ),
        isFalse,
      );
      await nodes[0].acceptConnection(nodes[2].localId);
      await _until(
        () => logs[0].whereType<SecureChannelReady>().any(
          (e) => e.endpointId == nodes[2].localId,
        ),
      );
      await _until(
        () => logs[2].whereType<SecureChannelReady>().any(
          (e) => e.endpointId == nodes[0].localId,
        ),
      );
    },
  );
}

Future<void> _until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 4));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) fail('Mesh event timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _Link implements NearbyTransport {
  _Link(this.id);
  final String id;
  final neighbors = <String, _Link>{};
  final wire = <ChatMessage>[];
  final _events = StreamController<NearbyEvent>.broadcast();
  void connect(_Link other) {
    neighbors[other.id] = other;
    other.neighbors[id] = this;
    _events.add(SecureChannelReady(other.id));
    other._events.add(SecureChannelReady(id));
  }

  void disconnectLink(_Link other) {
    neighbors.remove(other.id);
    other.neighbors.remove(id);
    _events.add(
      ConnectionChanged(
        endpointId: other.id,
        outcome: ConnectionOutcome.disconnected,
      ),
    );
    other._events.add(
      ConnectionChanged(
        endpointId: id,
        outcome: ConnectionOutcome.disconnected,
      ),
    );
  }

  @override
  Stream<NearbyEvent> get events => _events.stream;
  @override
  bool get isSupported => true;
  @override
  bool get isDemo => false;
  @override
  Future<void> start(String name) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() => _events.close();
  @override
  Future<void> sendMessage(ChatMessage message) async {
    final target = neighbors[message.endpointId];
    if (target == null) {
      throw StateError('No physical link from $id to ${message.endpointId}');
    }
    wire.add(message);
    target._events.add(
      MessageReceived(
        ChatMessage.fromPayload(endpointId: id, bytes: message.toPayload()),
      ),
    );
  }

  @override
  Future<void> requestConnection(
    String endpointId,
    String displayName, {
    String? enteredCode,
  }) async {}
  @override
  Future<void> acceptConnection(String endpointId) async {}
  @override
  Future<void> rejectConnection(String endpointId) async {}
  @override
  Future<void> disconnect(String endpointId) async {}
  @override
  Future<void> sendEdit({
    required String endpointId,
    required String targetMessageId,
    required String newText,
  }) async {}
  @override
  Future<void> sendReadReceipt(String endpointId, String messageId) async {}
  @override
  Future<void> sendProfileUpdate({String? name, String? avatar}) async {}
}
