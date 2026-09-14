import 'package:flutter/material.dart';

import '../chat_controller.dart';
import '../models/chat_message.dart';

class PeerChatPage extends StatefulWidget {
  const PeerChatPage({
    super.key,
    required this.controller,
    required this.endpointId,
  });

  final ChatController controller;
  final String endpointId;

  @override
  State<PeerChatPage> createState() => _PeerChatPageState();
}

class _PeerChatPageState extends State<PeerChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final sent = await widget.controller.send(
      widget.endpointId,
      _messageController.text,
    );
    if (!mounted || !sent) return;
    _messageController.clear();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final peer = widget.controller.peerById(widget.endpointId);
        final messages = widget.controller.messagesFor(widget.endpointId);
        final isConnected = peer?.isConnected ?? false;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(peer?.name ?? 'Dispositivo'),
                Text(
                  isConnected ? 'Cifrado E2E · AES-256-GCM' : 'Sin conexión',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? const _EmptyConversation()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            return _MessageBubble(message: messages[index]);
                          },
                        ),
                ),
                _Composer(
                  controller: _messageController,
                  enabled: isConnected,
                  onSend: _send,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final outgoing = message.direction == MessageDirection.outgoing;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
        decoration: BoxDecoration(
          color: outgoing ? colors.primaryContainer : colors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(outgoing ? 18 : 4),
            bottomRight: Radius.circular(outgoing ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!outgoing)
              Text(
                message.author,
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            Text(message.text),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _time(message.sentAt),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (outgoing) ...[
                  const SizedBox(width: 5),
                  Icon(switch (message.delivery) {
                    MessageDelivery.sending => Icons.schedule,
                    MessageDelivery.sent => Icons.check,
                    MessageDelivery.failed => Icons.error_outline,
                  }, size: 14),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: const [
          BoxShadow(
            blurRadius: 16,
            color: Color(0x14000000),
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: enabled
                    ? 'Escribe un mensaje'
                    : 'Dispositivo desconectado',
                counterText: '',
              ),
              onSubmitted: enabled ? (_) => onSend() : null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Enviar',
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 44),
            SizedBox(height: 12),
            Text(
              'La conexión está lista. Envía el primer mensaje sin usar Internet.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
