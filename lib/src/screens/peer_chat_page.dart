import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

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
  final ImagePicker _picker = ImagePicker();
  ChatMessage? _editingMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.markChatAsRead(widget.endpointId);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future<void>.delayed(const Duration(milliseconds: 60), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    if (_editingMessage != null) {
      final success = await widget.controller.editMessage(
        widget.endpointId,
        _editingMessage!.id,
        _messageController.text,
      );
      if (mounted && success) {
        setState(() => _editingMessage = null);
        _messageController.clear();
      }
      return;
    }

    final sent = await widget.controller.send(
      widget.endpointId,
      _messageController.text,
    );
    if (!mounted || !sent) return;
    _messageController.clear();
    _scrollToBottom();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final photo = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 70,
      );
      if (photo == null || !mounted) return;

      final file = File(photo.path);
      await widget.controller.sendImage(widget.endpointId, file);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar la imagen: $e')),
      );
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Galería de fotos'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Cámara'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _startEditing(ChatMessage message) {
    setState(() {
      _editingMessage = message;
      _messageController.text = message.text;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingMessage = null;
      _messageController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final peer = widget.controller.peerById(widget.endpointId);
        final messages = widget.controller.messagesFor(widget.endpointId);
        final isConnected = peer?.isConnected ?? false;

        if (widget.controller.getUnreadCount(widget.endpointId) > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.controller.markChatAsRead(widget.endpointId);
          });
        }

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                _PeerAvatar(
                  avatarBase64: peer?.avatarBase64 ??
                      widget.controller.userProfileService.getPeerAvatar(widget.endpointId),
                  name: peer?.name ?? 'Dispositivo',
                  radius: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              peer?.name ?? 'Dispositivo',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (peer?.uniqueId != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                peer!.uniqueId!,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        isConnected
                            ? 'Cifrado E2E · AES-256-GCM'
                            : 'Fuera de línea · Buzón activo',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isConnected ? Colors.green : Colors.amber.shade800,
                              fontWeight: isConnected ? FontWeight.normal : FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
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
                            final msg = messages[index];
                            return _MessageBubble(
                              message: msg,
                              onEdit: () => _startEditing(msg),
                            );
                          },
                        ),
                ),
                _Composer(
                  controller: _messageController,
                  enabled: true,
                  isConnected: isConnected,
                  editingMessage: _editingMessage,
                  onCancelEdit: _cancelEditing,
                  onSend: _send,
                  onPickImage: _showImageSourceDialog,
                  endpointId: widget.endpointId,
                  chatController: widget.controller,
                  onMediaSent: _scrollToBottom,
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
  const _MessageBubble({
    required this.message,
    required this.onEdit,
  });

  final ChatMessage message;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final outgoing = message.direction == MessageDirection.outgoing;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = outgoing
        ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3))
        : (isDark ? const Color(0xFF202C33) : Colors.white);
    final timeColor = isDark ? Colors.white60 : Colors.black54;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showContextMenu(context),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(outgoing ? 14 : 2),
              bottomRight: Radius.circular(outgoing ? 2 : 14),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!outgoing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.authorAvatar != null) ...[
                        _PeerAvatar(
                          avatarBase64: message.authorAvatar,
                          name: message.author,
                          radius: 8,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        message.author,
                        style: const TextStyle(
                          color: Color(0xFF075E54),
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              _buildContent(context),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _time(message.sentAt),
                    style: TextStyle(fontSize: 11, color: timeColor),
                  ),
                  if (message.isEdited) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(editado)',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: timeColor,
                      ),
                    ),
                  ],
                  if (outgoing) ...[
                    const SizedBox(width: 4),
                    Icon(
                      switch (message.delivery) {
                        MessageDelivery.sending => Icons.access_time,
                        MessageDelivery.inMailbox => Icons.schedule_send,
                        MessageDelivery.sent => Icons.done,
                        MessageDelivery.delivered => Icons.done_all,
                        MessageDelivery.read => Icons.done_all,
                        MessageDelivery.failed => Icons.error_outline,
                      },
                      size: 15,
                      color: switch (message.delivery) {
                        MessageDelivery.read => const Color(0xFF53BDEB),
                        MessageDelivery.delivered => timeColor,
                        MessageDelivery.sent => timeColor,
                        MessageDelivery.inMailbox => const Color(0xFFFFA000),
                        MessageDelivery.failed => Colors.red,
                        _ => timeColor,
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (message.type) {
      case ChatMessageType.image:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ImageBubble(message: message),
            if (message.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(message.text),
            ],
          ],
        );
      case ChatMessageType.audio:
        return _AudioBubble(
          message: message,
          outgoing: message.direction == MessageDirection.outgoing,
        );
      case ChatMessageType.text:
        return Text(message.text);
    }
  }

  void _showContextMenu(BuildContext context) {
    final outgoing = message.direction == MessageDirection.outgoing;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.text.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Copiar texto'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.text));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Texto copiado al portapapeles')),
                    );
                  },
                ),
              if (outgoing && message.type == ChatMessageType.text)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Editar mensaje'),
                  onTap: () {
                    Navigator.pop(context);
                    onEdit();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  String _time(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _ImageBubble extends StatelessWidget {
  const _ImageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (message.mediaPath != null && File(message.mediaPath!).existsSync()) {
      imageWidget = Image.file(
        File(message.mediaPath!),
        fit: BoxFit.cover,
      );
    } else if (message.mediaBase64 != null) {
      imageWidget = Image.memory(
        base64Decode(message.mediaBase64!),
        fit: BoxFit.cover,
      );
    } else {
      imageWidget = const Padding(
        padding: EdgeInsets.all(16),
        child: Icon(Icons.broken_image, size: 48),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220, maxWidth: 280),
        child: GestureDetector(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(
                    backgroundColor: Colors.black,
                    iconTheme: const IconThemeData(color: Colors.white),
                  ),
                  body: Center(child: InteractiveViewer(child: imageWidget)),
                ),
              ),
            );
          },
          child: imageWidget,
        ),
      ),
    );
  }
}

class _AudioBubble extends StatefulWidget {
  const _AudioBubble({required this.message, required this.outgoing});

  final ChatMessage message;
  final bool outgoing;

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _subState;
  StreamSubscription? _subPos;
  StreamSubscription? _subDur;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.message.durationSeconds ?? 0);

    _subState = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _subPos = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _subDur = _player.onDurationChanged.listen((d) {
      if (mounted && d > Duration.zero) setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    _subState?.cancel();
    _subPos?.cancel();
    _subDur?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else {
      if (widget.message.mediaPath != null &&
          File(widget.message.mediaPath!).existsSync()) {
        await _player.play(DeviceFileSource(widget.message.mediaPath!));
      } else if (widget.message.mediaBase64 != null) {
        final bytes = base64Decode(widget.message.mediaBase64!);
        final dir = await getTemporaryDirectory();
        final tmp = File('${dir.path}/temp_play_${widget.message.id}.m4a');
        await tmp.writeAsBytes(bytes);
        await _player.play(DeviceFileSource(tmp.path));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isPlaying = _state == PlayerState.playing;
    final currentSeconds = _position.inSeconds;
    final totalSeconds = _duration.inSeconds > 0
        ? _duration.inSeconds
        : (widget.message.durationSeconds ?? 0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: widget.outgoing
                ? colors.primary
                : colors.secondaryContainer,
            foregroundColor: widget.outgoing
                ? colors.onPrimary
                : colors.onSecondaryContainer,
          ),
          icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: _togglePlay,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: LinearProgressIndicator(
                value: totalSeconds > 0 ? (currentSeconds / totalSeconds).clamp(0.0, 1.0) : 0.0,
                backgroundColor: colors.outlineVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.isConnected,
    required this.editingMessage,
    required this.onCancelEdit,
    required this.onSend,
    required this.onPickImage,
    required this.endpointId,
    required this.chatController,
    required this.onMediaSent,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isConnected;
  final ChatMessage? editingMessage;
  final VoidCallback onCancelEdit;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final String endpointId;
  final ChatController chatController;
  final VoidCallback onMediaSent;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _recordedAudioPath;

  @override
  void dispose() {
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!widget.enabled) return;
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
          _recordedAudioPath = path;
        });
        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() => _recordSeconds++);
          }
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Se requiere permiso de micrófono')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al iniciar grabación: $e')),
      );
    }
  }

  Future<void> _stopAndSendRecording() async {
    _recordTimer?.cancel();
    try {
      final path = await _audioRecorder.stop();
      final duration = _recordSeconds;
      setState(() => _isRecording = false);

      if (path != null && duration > 0) {
        final file = File(path);
        if (await file.exists()) {
          await widget.chatController.sendAudio(
            widget.endpointId,
            file,
            duration,
          );
          widget.onMediaSent();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al detener grabación: $e')),
      );
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _audioRecorder.stop();
    setState(() => _isRecording = false);
    if (_recordedAudioPath != null) {
      final file = File(_recordedAudioPath!);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.editingMessage != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: colors.primaryContainer.withAlpha(120),
              child: Row(
                children: [
                  const Icon(Icons.edit, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Editando mensaje: "${widget.editingMessage!.text}"',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onCancelEdit,
                    tooltip: 'Cancelar edición',
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: _isRecording
                ? Row(
                    children: [
                      IconButton(
                        tooltip: 'Cancelar grabación',
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: _cancelRecording,
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Grabando: ${_recordSeconds}s',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                      const Spacer(),
                      IconButton.filled(
                        tooltip: 'Enviar nota de voz',
                        icon: const Icon(Icons.send),
                        onPressed: _stopAndSendRecording,
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Adjuntar imagen',
                        icon: const Icon(Icons.photo_camera_outlined),
                        onPressed: (widget.enabled && widget.isConnected) ? widget.onPickImage : null,
                      ),
                      IconButton(
                        tooltip: 'Grabar nota de voz',
                        icon: const Icon(Icons.mic_none_outlined),
                        onPressed: (widget.enabled && widget.isConnected) ? _startRecording : null,
                      ),
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          enabled: widget.enabled,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 1000,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: widget.editingMessage != null
                                ? 'Edita tu mensaje...'
                                : (widget.isConnected
                                    ? 'Escribe un mensaje...'
                                    : 'Escribe un mensaje (buzón offline)...'),
                            counterText: '',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          onSubmitted: widget.enabled ? (_) => widget.onSend() : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        tooltip: widget.editingMessage != null ? 'Guardar' : 'Enviar',
                        onPressed: widget.enabled ? widget.onSend : null,
                        icon: Icon(widget.editingMessage != null ? Icons.check : Icons.send),
                      ),
                    ],
                  ),
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
              'La conexión está lista. Envía texto, fotos o notas de voz sin Internet.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({
    this.avatarBase64,
    required this.name,
    this.radius = 18,
  });

  final String? avatarBase64;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (avatarBase64 != null && avatarBase64!.startsWith('preset:')) {
      final emoji = avatarBase64!.replaceFirst('preset:', '');
      return CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(emoji, style: TextStyle(fontSize: radius * 1.1)),
      );
    } else if (avatarBase64 != null && avatarBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(avatarBase64!);
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {}
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: radius * 0.9,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
