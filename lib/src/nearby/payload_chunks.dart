import 'dart:convert';
import 'dart:math';

/// Keeps Nearby BYTES frames below 32 KiB including JSON/Base64 overhead.
class PayloadChunks {
  static const chunkSize = 16 * 1024;
  static const maxBytes = 12 * 1024 * 1024;
  final _pending = <String, _Assembly>{};

  Iterable<List<int>> split(List<int> bytes) sync* {
    if (bytes.length > maxBytes) {
      throw const FormatException('El archivo supera el límite de 12 MB.');
    }
    if (bytes.length <= chunkSize) {
      yield bytes;
      return;
    }
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final count = (bytes.length / chunkSize).ceil();
    for (var index = 0; index < count; index++) {
      yield utf8.encode(
        jsonEncode({
          'type': 'chunk',
          'id': id,
          'index': index,
          'count': count,
          'data': base64Encode(
            bytes.sublist(
              index * chunkSize,
              min(bytes.length, (index + 1) * chunkSize),
            ),
          ),
        }),
      );
    }
  }

  List<int>? receive(String endpoint, List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> || decoded['type'] != 'chunk') {
      return bytes;
    }
    final now = DateTime.now();
    _pending.removeWhere(
      (_, value) => now.difference(value.created).inSeconds > 60,
    );
    final count = decoded['count'] as int;
    final index = decoded['index'] as int;
    if (count < 2 ||
        count > (maxBytes / chunkSize).ceil() ||
        index < 0 ||
        index >= count) {
      throw const FormatException('Fragmento fuera de límites.');
    }
    final key = '$endpoint:${decoded['id']}';
    if (!_pending.containsKey(key) && _pending.length >= 8) {
      throw const FormatException('Demasiados archivos simultáneos.');
    }
    final assembly = _pending.putIfAbsent(key, () => _Assembly(count, now));
    final part = base64Decode(decoded['data'] as String);
    if (assembly.parts.length != count || part.length > chunkSize) {
      _pending.remove(key);
      throw const FormatException('Fragmento inválido.');
    }
    assembly.parts[index] = part;
    if (assembly.parts.any((part) => part == null)) return null;
    _pending.remove(key);
    return [for (final part in assembly.parts) ...part!];
  }

  void clear(String endpoint) =>
      _pending.removeWhere((key, _) => key.startsWith('$endpoint:'));
}

class _Assembly {
  _Assembly(int count, this.created) : parts = List.filled(count, null);
  final List<List<int>?> parts;
  final DateTime created;
}
