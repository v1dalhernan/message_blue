import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:message_blue/src/nearby/payload_chunks.dart';

void main() {
  test(
    'large media stays within Nearby limits and reassembles out of order',
    () {
      final codec = PayloadChunks();
      final original = utf8.encode(jsonEncode({'media': 'x' * 200000}));
      final parts = codec.split(original).toList();
      expect(parts.every((part) => part.length < 32768), isTrue);
      List<int>? result;
      for (final part in parts.reversed) {
        result = codec.receive('peer', part) ?? result;
      }
      expect(result, original);
    },
  );
  test('oversized and malformed fragmented media is rejected', () {
    final codec = PayloadChunks();
    expect(
      () => codec.split(List.filled(PayloadChunks.maxBytes + 1, 0)).toList(),
      throwsFormatException,
    );
    expect(
      () => codec.receive(
        'peer',
        utf8.encode(jsonEncode({'type': 'chunk', 'count': 100000, 'index': 0})),
      ),
      throwsFormatException,
    );
  });
}
