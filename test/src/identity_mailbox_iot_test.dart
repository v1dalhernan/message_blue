import 'package:flutter_test/flutter_test.dart';
import 'package:message_blue/src/core/identity/user_identity_service.dart';
import 'package:message_blue/src/core/iot/enterprise_mesh_policy.dart';
import 'package:message_blue/src/core/iot/iot_device_node.dart';
import 'package:message_blue/src/core/profile/user_profile_service.dart';
import 'package:message_blue/src/core/storage/offline_mailbox_service.dart';
import 'package:message_blue/src/models/chat_message.dart';

void main() {
  group('UserIdentityService & Anti-Spoofing', () {
    setUp(() {
      UserIdentityService.instance.reset();
    });

    test('generates unique cryptographic id and deterministic 6-digit pin', () async {
      final id1 = await UserIdentityService.instance.getUniqueId('Alice');
      final pin1 = UserIdentityService.instance.getPersonalPin('Alice');
      expect(id1.startsWith('BM-'), isTrue);
      expect(pin1.length, 6);
      expect(int.tryParse(pin1), isNotNull);

      // Deterministic for same name
      final pinAgain = UserIdentityService.instance.getPersonalPin('Alice');
      expect(pinAgain, pin1);
    });

    test('detects spoofing when an attacker uses an already registered name with different fingerprint', () {
      final verified1 = UserIdentityService.instance.verifyOrRegisterPeer(
        endpointId: 'ep_1',
        peerName: 'Bob',
        fingerprint: 'BM-AAAA-BBBB-CCCC',
      );
      expect(verified1, isTrue);

      // Legitimate reconnect with same fingerprint
      final verified2 = UserIdentityService.instance.verifyOrRegisterPeer(
        endpointId: 'ep_2',
        peerName: 'Bob',
        fingerprint: 'BM-AAAA-BBBB-CCCC',
      );
      expect(verified2, isTrue);

      // Impersonator trying to use 'Bob' with a different fingerprint
      final spoofDetected = UserIdentityService.instance.verifyOrRegisterPeer(
        endpointId: 'ep_evil',
        peerName: 'Bob',
        fingerprint: 'BM-EVIL-6666-9999',
      );
      expect(spoofDetected, isFalse);
    });
  });

  group('UserProfileService', () {
    test('manages preset avatars and peer avatar caching', () {
      UserProfileService.instance.setPresetAvatar('🚀');
      expect(UserProfileService.instance.localAvatarBase64, 'preset:🚀');

      UserProfileService.instance.setPeerAvatar('peer_123', 'preset:🦊');
      expect(UserProfileService.instance.getPeerAvatar('peer_123'), 'preset:🦊');
    });
  });

  group('OfflineMailboxService (Store-and-Forward DTN)', () {
    setUp(() {
      OfflineMailboxService.instance.clear();
    });

    test('queues offline messages and flushes when recipient reconnects', () async {
      final msg1 = ChatMessage(
        id: 'msg-1',
        endpointId: 'peer_target',
        author: 'Sender',
        text: 'Hola offline!',
        sentAt: DateTime.now(),
        direction: MessageDirection.outgoing,
      );

      OfflineMailboxService.instance.queueMessage(msg1, 'peer_target');
      expect(OfflineMailboxService.instance.pendingCount, 1);
      expect(OfflineMailboxService.instance.getPendingFor('peer_target').length, 1);

      // Flush messages via callback
      final sentList = <String>[];
      final dispatched = await OfflineMailboxService.instance.flushPendingForPeer(
        'peer_target',
        (msg) async {
          sentList.add(msg.id);
          return true;
        },
      );

      expect(dispatched.length, 1);
      expect(sentList, contains('msg-1'));
      expect(OfflineMailboxService.instance.pendingCount, 0);
    });
  });

  group('IoT Telemetry & Enterprise Policy', () {
    test('serializes and deserializes IoT telemetry packets', () {
      final packet = IotTelemetryPacket(
        nodeId: 'iot_temp_sensor_01',
        nodeName: 'Sensor Termómetro #1',
        type: IotNodeType.sensor,
        metricName: 'Temperatura',
        metricValue: 23.5,
        unit: '°C',
        batteryPercent: 88,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final jsonMap = packet.toJson();
      expect(jsonMap['nodeId'], 'iot_temp_sensor_01');
      expect(jsonMap['type'], 'sensor');

      final reconstructed = IotTelemetryPacket.fromJson(jsonMap);
      expect(reconstructed.nodeId, packet.nodeId);
      expect(reconstructed.metricValue, 23.5);
      expect(reconstructed.unit, '°C');
    });

    test('EnterpriseMeshPolicy controls user disconnect capability', () {
      final policy = EnterpriseMeshPolicy.instance;
      expect(policy.allowUserDisconnect, isTrue);

      policy.setLockDisconnect(true);
      expect(policy.allowUserDisconnect, isFalse);
      expect(policy.enforceAlwaysConnected, isTrue);

      policy.setLockDisconnect(false);
      expect(policy.allowUserDisconnect, isTrue);
    });
  });
}
