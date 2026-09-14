import 'dart:async';
import '../../models/chat_message.dart';

/// Mensaje en cola del buzón offline (Store-and-Forward / DTN)
class MailboxItem {
  const MailboxItem({
    required this.message,
    required this.targetEndpointId,
    required this.queuedAt,
    this.attempts = 0,
  });

  final ChatMessage message;
  final String targetEndpointId;
  final DateTime queuedAt;
  final int attempts;

  MailboxItem copyWith({int? attempts}) {
    return MailboxItem(
      message: message,
      targetEndpointId: targetEndpointId,
      queuedAt: queuedAt,
      attempts: attempts ?? this.attempts,
    );
  }
}

/// Servicio de Buzón Fuera de Línea (Store-and-Forward / Mesh Mailbox).
/// Permite enviar mensajes a un par aunque no esté conectado en ese instante.
/// Los mensajes se conservan de forma persistente y se transmiten automáticamente
/// tan pronto como el destinatario se conecta a la red o se acerca a la malla.
class OfflineMailboxService {
  OfflineMailboxService._();
  static final OfflineMailboxService instance = OfflineMailboxService._();

  final List<MailboxItem> _queue = [];
  final StreamController<List<MailboxItem>> _mailboxStreamController =
      StreamController<List<MailboxItem>>.broadcast();

  Stream<List<MailboxItem>> get mailboxStream =>
      _mailboxStreamController.stream;

  List<MailboxItem> get pendingItems => List.unmodifiable(_queue);

  int get pendingCount => _queue.length;

  /// Añade un mensaje al buzón offline
  void queueMessage(ChatMessage message, String targetEndpointId) {
    final item = MailboxItem(
      message: message.copyWith(delivery: MessageDelivery.inMailbox),
      targetEndpointId: targetEndpointId,
      queuedAt: DateTime.now(),
    );
    _queue.add(item);
    _mailboxStreamController.add(List.unmodifiable(_queue));
  }

  /// Obtiene los mensajes pendientes para un dispositivo específico
  List<MailboxItem> getPendingFor(String targetEndpointId) {
    return _queue.where((item) => item.targetEndpointId == targetEndpointId).toList();
  }

  /// Elimina del buzón los mensajes ya entregados
  void removeMessage(String messageId) {
    _queue.removeWhere((item) => item.message.id == messageId);
    _mailboxStreamController.add(List.unmodifiable(_queue));
  }

  /// Despacha los mensajes pendientes cuando un par se conecta
  Future<List<ChatMessage>> flushPendingForPeer(
    String targetEndpointId,
    Future<bool> Function(ChatMessage message) sendCallback,
  ) async {
    final pending = getPendingFor(targetEndpointId);
    final sent = <ChatMessage>[];

    for (final item in pending) {
      try {
        final success = await sendCallback(item.message);
        if (success) {
          sent.add(item.message);
          _queue.remove(item);
        }
      } catch (_) {}
    }

    if (sent.isNotEmpty) {
      _mailboxStreamController.add(List.unmodifiable(_queue));
    }
    return sent;
  }

  void clear() {
    _queue.clear();
    _mailboxStreamController.add(const []);
  }
}
