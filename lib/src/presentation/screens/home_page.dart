import 'package:flutter/material.dart';

import '../../core/theme/whatsapp_theme.dart';
import '../../domain/entities/pairing_session_entity.dart';
import '../../domain/entities/peer_entity.dart';
import '../controllers/chat_controller.dart';
import '../widgets/pairing_dialogs.dart';
import 'create_group_page.dart';
import 'group_chat_page.dart';
import 'peer_chat_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final ChatController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  PairingSessionEntity? _lastHandledSession;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _tabController.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    final session = widget.controller.currentPairingSession;
    if (session == null) {
      _lastHandledSession = null;
      return;
    }

    if (session != _lastHandledSession) {
      _lastHandledSession = session;
      _handlePairingSession(session);
    }
  }

  void _handlePairingSession(PairingSessionEntity session) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);

      // 1. Solicitud entrante para Persona B: Diálogo interactivo Aceptar / Rechazar
      if (session.status == PairingStatus.incomingPrompt && !session.isInitiator) {
        showModalBottomSheet(
          context: context,
          isDismissible: false,
          enableDrag: false,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (ctx) => IncomingConnectionModal(
            session: session,
            onAccept: () {
              Navigator.pop(ctx);
              widget.controller.acceptIncomingConnection(session.peerId);
            },
            onReject: () {
              Navigator.pop(ctx);
              widget.controller.rejectIncomingConnection(session.peerId);
            },
          ),
        );
      }

      // 2. Persona B aceptó: Mostrar QR y PIN de 6 dígitos
      else if (session.status == PairingStatus.awaitingVerification && !session.isInitiator) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (ctx) => QrDisplaySheet(
            session: session,
            onCancel: () => Navigator.pop(ctx),
          ),
        );
      }

      // 3. Persona A solicitó: Mostrar diálogo para escanear QR o ingresar PIN de 6 dígitos
      else if (session.status == PairingStatus.awaitingVerification && session.isInitiator) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => QrScannerOrPinDialog(
            session: session,
            onVerifyPin: (pin) async {
              final ok = await widget.controller.verifyPairingPin(session.peerId, pin);
              if (ok) {
                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('✓ Conexión cifrada verificada con éxito'),
                    backgroundColor: WhatsAppTheme.primaryTeal,
                  ),
                );
              }
              return ok;
            },
            onVerifyQr: (rawQr) async {
              final ok = await widget.controller.verifyPairingQr(rawQr);
              if (ok) {
                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('✓ Código QR verificado con éxito'),
                    backgroundColor: WhatsAppTheme.primaryTeal,
                  ),
                );
              }
              return ok;
            },
            onCancel: () => Navigator.pop(ctx),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            backgroundColor: WhatsAppTheme.darkTeal,
            foregroundColor: Colors.white,
            elevation: 1,
            title: const Text(
              'WhatsApp Mesh',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: -0.3,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Escanear QR',
                onPressed: () => _openManualQrScanner(context),
              ),
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Buscar',
                onPressed: () {},
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (val) {
                  if (val == 'new_group') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CreateGroupPage(controller: widget.controller),
                      ),
                    );
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'new_group',
                    child: Text('Nuevo grupo'),
                  ),
                  PopupMenuItem(
                    value: 'info',
                    child: Text('ID: ${widget.controller.localEndpointId}'),
                  ),
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: WhatsAppTheme.accentGreen,
              indicatorWeight: 3.5,
              labelColor: WhatsAppTheme.accentGreen,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('CHATS'),
                      const SizedBox(width: 5),
                      _CountBadge(count: widget.controller.peers.where((p) => p.isConnected).length),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('GRUPOS'),
                      const SizedBox(width: 5),
                      _CountBadge(count: widget.controller.groups.length),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('RED MALLA'),
                      const SizedBox(width: 5),
                      _CountBadge(count: widget.controller.peers.length),
                    ],
                  ),
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _ChatsTab(controller: widget.controller),
              _GroupsTab(controller: widget.controller),
              _MeshNetworkTab(controller: widget.controller),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: WhatsAppTheme.accentGreen,
            foregroundColor: Colors.white,
            elevation: 4,
            onPressed: () {
              if (_tabController.index == 1) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateGroupPage(controller: widget.controller),
                  ),
                );
              } else {
                _tabController.animateTo(2);
              }
            },
            child: Icon(_tabController.index == 1 ? Icons.group_add : Icons.chat),
          ),
        );
      },
    );
  }

  void _openManualQrScanner(BuildContext context) {
    final connectedPeers = widget.controller.peers;
    if (connectedPeers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay dispositivos cercanos disponibles')),
      );
      return;
    }

    final target = connectedPeers.first;
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => QrScannerOrPinDialog(
        session: PairingSessionEntity(
          peerId: target.id,
          peerName: target.name,
          isInitiator: true,
          status: PairingStatus.awaitingVerification,
          sixDigitPin: target.pin,
          qrPayload: target.qrPayload,
        ),
        onVerifyPin: (pin) async {
          final ok = await widget.controller.verifyPairingPin(target.id, pin);
          if (ok) {
            if (ctx.mounted) Navigator.pop(ctx);
            messenger.showSnackBar(
              const SnackBar(
                content: Text('✓ Conexión verificada'),
                backgroundColor: WhatsAppTheme.primaryTeal,
              ),
            );
          }
          return ok;
        },
        onVerifyQr: (raw) async {
          final ok = await widget.controller.verifyPairingQr(raw);
          if (ok) {
            if (ctx.mounted) Navigator.pop(ctx);
            messenger.showSnackBar(
              const SnackBar(
                content: Text('✓ QR verificado'),
                backgroundColor: WhatsAppTheme.primaryTeal,
              ),
            );
          }
          return ok;
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(fontSize: 10, color: Colors.white),
      ),
    );
  }
}

// -------------------------------------------------------------
// TAB 1: DIRECT 1-ON-1 CHATS
// -------------------------------------------------------------
class _ChatsTab extends StatelessWidget {
  const _ChatsTab({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final connectedPeers = controller.peers.where((p) => p.isConnected).toList();

    if (connectedPeers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No tienes chats activos',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ve a la pestaña "RED MALLA" para descubrir y conectarte a dispositivos cercanos con QR o código PIN.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 13.5),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: connectedPeers.length,
      separatorBuilder: (context, index) => const Divider(indent: 72, height: 1),
      itemBuilder: (context, index) {
        final peer = connectedPeers[index];
        final messages = controller.messages
            .where((m) =>
                (m.recipientId == peer.id && m.isOutgoing) ||
                (m.senderId == peer.id && !m.isOutgoing))
            .toList();
        final lastMsg = messages.isNotEmpty ? messages.last : null;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: WhatsAppTheme.primaryTeal.withValues(alpha: 0.15),
                child: Text(
                  peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: WhatsAppTheme.primaryTeal,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              if (peer.isVerified)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.verified,
                      size: 14,
                      color: WhatsAppTheme.accentGreen,
                    ),
                  ),
                ),
            ],
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  peer.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (lastMsg != null)
                Text(
                  _formatTime(lastMsg.timestamp),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade600,
                  ),
                ),
            ],
          ),
          subtitle: Row(
            children: [
              if (lastMsg != null && lastMsg.isOutgoing) ...[
                const Icon(Icons.done_all, size: 16, color: WhatsAppTheme.checkBlue),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  lastMsg != null
                      ? (lastMsg.text.isNotEmpty ? lastMsg.text : 'Multimedia')
                      : 'Toca para iniciar una conversación cifrada',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PeerChatPage(
                  controller: controller,
                  endpointId: peer.id,
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// -------------------------------------------------------------
// TAB 2: WHATSAPP CHAT GROUPS
// -------------------------------------------------------------
class _GroupsTab extends StatelessWidget {
  const _GroupsTab({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final groups = controller.groups;

    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'Sin grupos de malla',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Crea un grupo de chat cifrado para compartir mensajes y multimedia con múltiples nodos a la vez.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 13.5),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: WhatsAppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.group_add),
                label: const Text('Crear nuevo grupo'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreateGroupPage(controller: controller),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (context, index) => const Divider(indent: 72, height: 1),
      itemBuilder: (context, index) {
        final group = groups[index];
        final messages = controller.messages
            .where((m) => m.groupId == group.id || m.recipientId == group.id)
            .toList();
        final lastMsg = messages.isNotEmpty ? messages.last : null;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            radius: 26,
            backgroundColor: WhatsAppTheme.primaryTeal.withValues(alpha: 0.15),
            child: const Icon(Icons.groups, color: WhatsAppTheme.primaryTeal, size: 28),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (lastMsg != null)
                Text(
                  _formatTime(lastMsg.timestamp),
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                ),
            ],
          ),
          subtitle: Text(
            lastMsg != null
                ? '${lastMsg.senderName}: ${lastMsg.text}'
                : '${group.memberIds.length} participantes',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GroupChatPage(
                  group: group,
                  controller: controller,
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// -------------------------------------------------------------
// TAB 3: MESH NETWORK (NODOS & EMPAREJAMIENTO QR/PIN)
// -------------------------------------------------------------
class _MeshNetworkTab extends StatelessWidget {
  const _MeshNetworkTab({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final peers = controller.peers;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // My Node Card
        Card(
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: WhatsAppTheme.primaryTeal,
                  child: const Icon(Icons.device_hub, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.localDeviceName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: ${controller.localEndpointId}',
                        style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: const [
                          Icon(Icons.circle, size: 8, color: WhatsAppTheme.accentGreen),
                          SizedBox(width: 4),
                          Text(
                            'Red activa · Reenviador de malla',
                            style: TextStyle(fontSize: 11.5, color: WhatsAppTheme.primaryTeal),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Discovered Devices Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'DISPOSITIVOS CERCANOS (${peers.length})',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
                color: WhatsAppTheme.darkTeal,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (peers.isEmpty)
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: WhatsAppTheme.primaryTeal),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Buscando dispositivos en la red...',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Asegúrate de que el otro emulador tenga la aplicación abierta.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          )
        else
          ...peers.map((peer) => _PeerNetworkCard(controller: controller, peer: peer)),
      ],
    );
  }
}

class _PeerNetworkCard extends StatelessWidget {
  const _PeerNetworkCard({required this.controller, required this.peer});

  final ChatController controller;
  final PeerEntity peer;

  @override
  Widget build(BuildContext context) {
    final isConnected = peer.isConnected;
    final isConnecting = peer.status == PeerConnectionStatus.connecting;
    final isAwaiting = peer.status == PeerConnectionStatus.awaitingVerification;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: isConnected
              ? WhatsAppTheme.accentGreen.withValues(alpha: 0.2)
              : Colors.grey.shade200,
          child: Icon(
            isConnected ? Icons.check_circle : Icons.phone_android,
            color: isConnected ? WhatsAppTheme.primaryTeal : Colors.grey.shade700,
          ),
        ),
        title: Text(
          peer.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${peer.id}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? WhatsAppTheme.lightOutgoingBubble
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isConnected
                        ? (peer.isVerified ? 'Cifrado Verificado ✓' : 'Conectado')
                        : (isConnecting
                            ? 'Conectando...'
                            : (isAwaiting ? 'Pendiente PIN/QR' : 'Descubierto')),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isConnected ? WhatsAppTheme.darkTeal : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: isConnected
            ? IconButton(
                icon: const Icon(Icons.chat, color: WhatsAppTheme.primaryTeal),
                tooltip: 'Abrir chat',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PeerChatPage(
                        controller: controller,
                        endpointId: peer.id,
                      ),
                    ),
                  );
                },
              )
            : ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: WhatsAppTheme.primaryTeal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: isConnecting
                    ? null
                    : () => controller.connectToPeer(peer.id),
                child: isConnecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Conectar'),
              ),
      ),
    );
  }
}
