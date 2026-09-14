import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../core/theme/whatsapp_theme.dart';
import '../../domain/entities/chat_message_entity.dart';

class WhatsAppMessageBubble extends StatelessWidget {
  const WhatsAppMessageBubble({
    super.key,
    required this.message,
    this.onEdit,
    this.onLongPress,
  });

  final ChatMessageEntity message;
  final VoidCallback? onEdit;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isOutgoing;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bubbleColor = isMe
        ? (isDark ? WhatsAppTheme.darkOutgoingBubble : WhatsAppTheme.lightOutgoingBubble)
        : (isDark ? WhatsAppTheme.darkIncomingBubble : WhatsAppTheme.lightIncomingBubble);

    final textColor = isDark ? Colors.white : Colors.black87;
    final timestampColor = isDark ? WhatsAppTheme.timestampDark : WhatsAppTheme.timestampLight;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
          minWidth: 80,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 2),
            bottomRight: Radius.circular(isMe ? 2 : 12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onLongPress: isMe ? onEdit ?? onLongPress : onLongPress,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sender name for incoming messages (especially in groups/mesh)
                  if (!isMe) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message.senderName,
                          style: const TextStyle(
                            color: WhatsAppTheme.senderAccentTeal,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                        if (message.hops > 1) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.alt_route, size: 10, color: Colors.blueGrey),
                                const SizedBox(width: 2),
                                Text(
                                  '${message.hops} saltos',
                                  style: const TextStyle(fontSize: 9.5, color: Colors.blueGrey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                  ],

                  // Content based on message type
                  _buildContent(context, textColor),

                  const SizedBox(height: 3),

                  // Timestamp, edited status, and checkmarks
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (message.isEdited) ...[
                        Text(
                          'editado ',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: timestampColor,
                          ),
                        ),
                      ],
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color: timestampColor,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          message.status == MessageDeliveryStatus.delivered ||
                                  message.status == MessageDeliveryStatus.read
                              ? Icons.done_all
                              : Icons.check,
                          size: 15,
                          color: message.status == MessageDeliveryStatus.read
                              ? WhatsAppTheme.checkBlue
                              : timestampColor,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Color textColor) {
    switch (message.type) {
      case MessageType.image:
        return _WhatsAppImageBubble(message: message);
      case MessageType.audio:
        return _WhatsAppAudioBubble(message: message);
      case MessageType.text:
      case MessageType.system:
        return Text(
          message.text,
          style: TextStyle(
            fontSize: 15,
            color: textColor,
            height: 1.25,
          ),
        );
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _WhatsAppImageBubble extends StatelessWidget {
  const _WhatsAppImageBubble({required this.message});

  final ChatMessageEntity message;

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (message.mediaPath != null && File(message.mediaPath!).existsSync()) {
      imageWidget = Image.file(
        File(message.mediaPath!),
        fit: BoxFit.cover,
      );
    } else if (message.mediaBase64 != null && message.mediaBase64!.isNotEmpty) {
      imageWidget = Image.memory(
        base64Decode(message.mediaBase64!),
        fit: BoxFit.cover,
      );
    } else {
      imageWidget = Container(
        height: 160,
        color: Colors.grey.shade300,
        child: const Center(child: Icon(Icons.broken_image, size: 40)),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(message.senderName),
              ),
              body: Center(
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: imageWidget,
                ),
              ),
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 240,
            maxWidth: 240,
          ),
          child: imageWidget,
        ),
      ),
    );
  }
}

class _WhatsAppAudioBubble extends StatefulWidget {
  const _WhatsAppAudioBubble({required this.message});

  final ChatMessageEntity message;

  @override
  State<_WhatsAppAudioBubble> createState() => _WhatsAppAudioBubbleState();
}

class _WhatsAppAudioBubbleState extends State<_WhatsAppAudioBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.message.durationSeconds ?? 0);

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });

    _player.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() => _position = pos);
      }
    });

    _player.onDurationChanged.listen((dur) {
      if (mounted && dur > Duration.zero) {
        setState(() => _duration = dur);
      }
    });

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (widget.message.mediaPath != null &&
          File(widget.message.mediaPath!).existsSync()) {
        await _player.play(DeviceFileSource(widget.message.mediaPath!));
      } else if (widget.message.mediaBase64 != null) {
        final bytes = base64Decode(widget.message.mediaBase64!);
        await _player.play(BytesSource(bytes));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.message.isOutgoing;
    final primaryColor = isMe ? WhatsAppTheme.darkTeal : WhatsAppTheme.primaryTeal;

    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            padding: EdgeInsets.zero,
            minimumSize: const Size(40, 40),
          ),
          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 24),
          onPressed: _togglePlay,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 130,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  trackHeight: 3,
                  activeTrackColor: primaryColor,
                  inactiveTrackColor: Colors.grey.withValues(alpha: 0.35),
                  thumbColor: primaryColor,
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: progress,
                  onChanged: (val) {
                    final targetMs = (val * _duration.inMilliseconds).round();
                    _player.seek(Duration(milliseconds: targetMs));
                  },
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.mic, size: 12, color: primaryColor),
                const SizedBox(width: 3),
                Text(
                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                  style: const TextStyle(fontSize: 10.5, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
