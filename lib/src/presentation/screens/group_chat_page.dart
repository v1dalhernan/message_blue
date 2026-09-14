import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/theme/whatsapp_theme.dart';
import '../../domain/entities/chat_group_entity.dart';
import '../../domain/entities/chat_message_entity.dart';
import '../controllers/chat_controller.dart';
import '../widgets/whatsapp_bubble.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({
    super.key,
    required this.group,
    required this.controller,
  });

  final ChatGroupEntity group;
  final ChatController controller;

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();

  ChatMessageEntity? _editingMessage;
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _recordedPath;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (_editingMessage != null) {
      await widget.controller.editGroupMessage(
        widget.group.id,
        _editingMessage!.id,
        text,
      );
      if (mounted) {
        setState(() => _editingMessage = null);
        _textController.clear();
      }
      return;
    }

    final ok = await widget.controller.sendGroupText(widget.group.id, text);
    if (mounted && ok) {
      _textController.clear();
      _scrollToBottom();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final photo = await _picker.pickImage(
        source: source,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 75,
      );
      if (photo == null || !mounted) return;
      final file = File(photo.path);
      await widget.controller.sendGroupImage(widget.group.id, file);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al adjuntar imagen: $e')),
      );
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/grp_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
          _recordedPath = path;
        });
        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _recordSeconds++);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al grabar audio: $e')),
      );
    }
  }

  Future<void> _stopAndSendRecording() async {
    _recordTimer?.cancel();
    try {
      final path = await _recorder.stop();
      final duration = _recordSeconds;
      setState(() => _isRecording = false);

      if (path != null && duration > 0) {
        final file = File(path);
        if (await file.exists()) {
          await widget.controller.sendGroupAudio(widget.group.id, file, duration);
          _scrollToBottom();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al enviar audio: $e')),
      );
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _recorder.stop();
    setState(() => _isRecording = false);
    if (_recordedPath != null) {
      final f = File(_recordedPath!);
      if (await f.exists()) await f.delete();
    }
  }

  void _startEditing(ChatMessageEntity msg) {
    setState(() {
      _editingMessage = msg;
      _textController.text = msg.text;
    });
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: WhatsAppTheme.primaryTeal),
              title: const Text('Galería'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: WhatsAppTheme.primaryTeal),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhatsAppTheme.lightChatBg,
      appBar: AppBar(
        backgroundColor: WhatsAppTheme.primaryTeal,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              child: const Icon(Icons.groups, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.group.name,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${widget.group.memberIds.length} miembros · Cifrado E2E',
                    style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final groupMessages = widget.controller.messages
              .where((m) => m.recipientId == 'group:${widget.group.id}')
              .toList();

          return Column(
            children: [
              // Message List
              Expanded(
                child: groupMessages.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white70,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Los mensajes en este grupo están protegidos con cifrado E2E de extremo a extremo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: groupMessages.length,
                        itemBuilder: (context, index) {
                          final msg = groupMessages[index];
                          return WhatsAppMessageBubble(
                            message: msg,
                            onEdit: () => _startEditing(msg),
                          );
                        },
                      ),
              ),

              // Edit Banner
              if (_editingMessage != null) ...[
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 16, color: WhatsAppTheme.primaryTeal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Editando: "${_editingMessage!.text}"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          setState(() {
                            _editingMessage = null;
                            _textController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],

              // WhatsApp-style Bottom Composer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: const BoxDecoration(color: Colors.transparent),
                child: SafeArea(
                  child: _isRecording
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: _cancelRecording,
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Grabando: ${_recordSeconds ~/ 60}:${(_recordSeconds % 60).toString().padLeft(2, '0')}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              IconButton.filled(
                                style: IconButton.styleFrom(backgroundColor: WhatsAppTheme.primaryTeal),
                                icon: const Icon(Icons.send, color: Colors.white),
                                onPressed: _stopAndSendRecording,
                              ),
                            ],
                          ),
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 3,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.attach_file, color: Colors.black54),
                                      onPressed: _showImageOptions,
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: _textController,
                                        minLines: 1,
                                        maxLines: 4,
                                        decoration: const InputDecoration(
                                          hintText: 'Mensaje al grupo...',
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.camera_alt, color: Colors.black54),
                                      onPressed: () => _pickImage(ImageSource.camera),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            FloatingActionButton.small(
                              backgroundColor: WhatsAppTheme.primaryTeal,
                              elevation: 2,
                              onPressed: () {
                                if (_textController.text.trim().isNotEmpty) {
                                  _sendText();
                                } else {
                                  _startRecording();
                                }
                              },
                              child: Icon(
                                _textController.text.trim().isNotEmpty ? Icons.send : Icons.mic,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
