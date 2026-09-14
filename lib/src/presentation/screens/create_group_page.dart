import 'package:flutter/material.dart';

import '../../core/theme/whatsapp_theme.dart';
import '../controllers/chat_controller.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key, required this.controller});

  final ChatController controller;

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final Set<String> _selectedPeerIds = {};
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor escribe un nombre para el grupo')),
      );
      return;
    }

    setState(() => _isCreating = true);
    try {
      await widget.controller.createGroup(
        name: name,
        description: _descController.text.trim(),
        memberIds: _selectedPeerIds.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Grupo "$name" creado con cifrado E2E')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al crear el grupo: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo Grupo'),
        backgroundColor: WhatsAppTheme.primaryTeal,
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final peers = widget.controller.peers;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Group Info Card
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: WhatsAppTheme.primaryTeal.withValues(alpha: 0.15),
                            child: const Icon(Icons.groups, color: WhatsAppTheme.primaryTeal, size: 32),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Nombre del grupo',
                                hintText: 'Ej. Equipo BlueMesh',
                                border: UnderlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _descController,
                        decoration: const InputDecoration(
                          labelText: 'Descripción (opcional)',
                          hintText: 'Propósito del grupo en la malla',
                          border: UnderlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'SELECCIONAR PARTICIPANTES',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              if (peers.isEmpty) ...[
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No hay dispositivos conectados aún.\nPodrás agregar miembros cuando se unan a la malla.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
              ] else ...[
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: peers.map((peer) {
                      final isSelected = _selectedPeerIds.contains(peer.id);
                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: WhatsAppTheme.primaryTeal,
                        title: Text(peer.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          peer.isConnected ? 'Conectado a la malla' : 'Descubierto',
                          style: TextStyle(
                            fontSize: 12,
                            color: peer.isConnected ? WhatsAppTheme.primaryTeal : Colors.black45,
                          ),
                        ),
                        secondary: CircleAvatar(
                          backgroundColor: WhatsAppTheme.primaryTeal.withValues(alpha: 0.15),
                          child: Text(
                            peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
                            style: const TextStyle(color: WhatsAppTheme.primaryTeal, fontWeight: FontWeight.bold),
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedPeerIds.add(peer.id);
                            } else {
                              _selectedPeerIds.remove(peer.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: WhatsAppTheme.accentGreen,
        onPressed: _isCreating ? null : _createGroup,
        child: _isCreating
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.check, color: Colors.white),
      ),
    );
  }
}
