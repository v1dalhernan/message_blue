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
import 'widgets/chat_visibility.dart';

class MeshGroupChatPage extends StatefulWidget {
  const MeshGroupChatPage({super.key, required this.controller});

  final ChatController controller;

  @override
  State<MeshGroupChatPage> createState() => _MeshGroupChatPageState();
}

class _MeshGroupChatPageState extends State<MeshGroupChatPage>
    with ChatVisibility<MeshGroupChatPage> {
  @override
  ChatController get chatController => widget.controller;
  @override
  String get visibleChatId => ChatMessage.groupEndpointId;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  ChatMessage? _editingMessage;

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
      final success = await widget.controller.editGroupMessage(
        _editingMessage!.id,
        _messageController.text,
      );
      if (mounted && success) {
        setState(() => _editingMessage = null);
        _messageController.clear();
      }
      return;
    }

    final sent = await widget.controller.sendGroupText(_messageController.text);
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
      await widget.controller.sendGroupImage(file);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al adjuntar imagen: $e')));
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

  void _showMeshInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.hub_outlined),
            SizedBox(width: 8),
            Text('Red Mesh (Enrutamiento)'),
          ],
        ),
        content: const Text(
          'En esta sala grupal todos los dispositivos están mezclados.\n\n'
          'Cada mensaje se envía cifrado a todos tus contactos directos. '
          'Si un dispositivo recibe un mensaje nuevo, lo retransmite automáticamente '
          'a sus otros vecinos cercanos (hasta 5 saltos) para ampliar la cobertura sin requerir Internet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final messages = widget.controller.groupMessages;
        final connectedCount = widget.controller.connectedCount;
        final hasConnected = connectedCount > 0;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Sala Mezclada'),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasConnected ? Icons.lock : Icons.lock_open,
                      size: 12,
                      color: hasConnected ? Colors.teal : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasConnected
                          ? '$connectedCount nodo${connectedCount > 1 ? 's' : ''} · Cifrado Malla'
                          : 'Sin dispositivos conectados',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: hasConnected ? Colors.teal : null),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Acerca de la Red Mesh',
                onPressed: _showMeshInfo,
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? const _EmptyGroupConversation()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            return _GroupMessageBubble(
                              message: msg,
                              onEdit: () => _startEditing(msg),
                            );
                          },
                        ),
                ),
                _GroupComposer(
                  controller: _messageController,
                  enabled: hasConnected,
                  editingMessage: _editingMessage,
                  onCancelEdit: _cancelEditing,
                  onSend: _send,
                  onPickImage: _showImageSourceDialog,
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

class _GroupMessageBubble extends StatelessWidget {
  const _GroupMessageBubble({required this.message, required this.onEdit});

  final ChatMessage message;
  final VoidCallback onEdit;

  Color _authorColor(String name) {
    final hash = name.hashCode;
    const colors = [
      Colors.indigo,
      Colors.teal,
      Colors.deepOrange,
      Colors.purple,
      Colors.blueGrey,
      Colors.brown,
      Colors.cyan,
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final outgoing = message.direction == MessageDirection.outgoing;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = outgoing
        ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3))
        : (isDark ? const Color(0xFF202C33) : Colors.white);

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
              if (!outgoing) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.author,
                      style: TextStyle(
                        color: _authorColor(message.author),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (message.hopCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${message.hopCount} salto${message.hopCount > 1 ? 's' : ''}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
              ],
              _buildContent(context),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _time(message.sentAt),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  if (message.isEdited) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(editado)',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                  if (outgoing) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.done_all,
                      size: 15,
                      color: Color(0xFF53BDEB),
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
            _GroupImageWidget(message: message),
            if (message.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(message.text),
            ],
          ],
        );
      case ChatMessageType.audio:
        return _GroupAudioWidget(
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
                      const SnackBar(
                        content: Text('Texto copiado al portapapeles'),
                      ),
                    );
                  },
                ),
              if (outgoing && message.type == ChatMessageType.text)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Editar mensaje grupal'),
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

class _GroupImageWidget extends StatelessWidget {
  const _GroupImageWidget({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (message.mediaPath != null && File(message.mediaPath!).existsSync()) {
      imageWidget = Image.file(File(message.mediaPath!), fit: BoxFit.cover);
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

class _GroupAudioWidget extends StatefulWidget {
  const _GroupAudioWidget({required this.message, required this.outgoing});

  final ChatMessage message;
  final bool outgoing;

  @override
  State<_GroupAudioWidget> createState() => _GroupAudioWidgetState();
}

class _GroupAudioWidgetState extends State<_GroupAudioWidget> {
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
        final tmp = File(
          '${dir.path}/temp_group_play_${widget.message.id}.m4a',
        );
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
                value: totalSeconds > 0
                    ? (currentSeconds / totalSeconds).clamp(0.0, 1.0)
                    : 0.0,
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

class _GroupComposer extends StatefulWidget {
  const _GroupComposer({
    required this.controller,
    required this.enabled,
    required this.editingMessage,
    required this.onCancelEdit,
    required this.onSend,
    required this.onPickImage,
    required this.chatController,
    required this.onMediaSent,
  });

  final TextEditingController controller;
  final bool enabled;
  final ChatMessage? editingMessage;
  final VoidCallback onCancelEdit;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final ChatController chatController;
  final VoidCallback onMediaSent;

  @override
  State<_GroupComposer> createState() => _GroupComposerState();
}

class _GroupComposerState extends State<_GroupComposer> {
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
            '${dir.path}/group_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al iniciar grabación: $e')));
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
          await widget.chatController.sendGroupAudio(file, duration);
          widget.onMediaSent();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al detener grabación: $e')));
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
                      'Editando mensaje grupal: "${widget.editingMessage!.text}"',
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
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        onPressed: _cancelRecording,
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.fiber_manual_record,
                        color: Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Grabando: ${_recordSeconds}s',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const Spacer(),
                      IconButton.filled(
                        tooltip: 'Enviar nota de voz grupal',
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
                        onPressed: widget.enabled ? widget.onPickImage : null,
                      ),
                      IconButton(
                        tooltip: 'Grabar nota de voz',
                        icon: const Icon(Icons.mic_none_outlined),
                        onPressed: widget.enabled ? _startRecording : null,
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
                            hintText: widget.enabled
                                ? (widget.editingMessage != null
                                      ? 'Edita tu mensaje grupal...'
                                      : 'Mensaje para todos en la malla...')
                                : 'Conecta al menos un dispositivo',
                            counterText: '',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          onSubmitted: widget.enabled
                              ? (_) => widget.onSend()
                              : null,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        tooltip: widget.editingMessage != null
                            ? 'Guardar'
                            : 'Enviar a la malla',
                        onPressed: widget.enabled ? widget.onSend : null,
                        icon: Icon(
                          widget.editingMessage != null
                              ? Icons.check
                              : Icons.send,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyGroupConversation extends StatelessWidget {
  const _EmptyGroupConversation();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub_outlined, size: 44),
            SizedBox(height: 12),
            Text(
              'Sala Mezclada (Malla Local)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 6),
            Text(
              'Cualquier mensaje, foto o nota de voz enviada aquí se transmitirá a todos los dispositivos cercanos conectados.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
