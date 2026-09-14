import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../chat_controller.dart';
import '../models/nearby_peer.dart';
import '../nearby/nearby_transport.dart';
import 'mesh_group_chat_page.dart';
import 'peer_chat_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.transport});

  final NearbyTransport transport;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ChatController _controller;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _controller = ChatController(widget.transport);
    _nameController = TextEditingController(text: 'Android cercano');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hub_outlined),
                SizedBox(width: 10),
                Text('BlueMesh'),
              ],
            ),
            actions: [
              if (_controller.isRunning)
                IconButton(
                  tooltip: 'Salir de la red local',
                  onPressed: _controller.isBusy ? null : _controller.stop,
                  icon: const Icon(Icons.power_settings_new),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: _controller.isRunning
                ? _NetworkBody(controller: _controller)
                : _WelcomeBody(
                    controller: _controller,
                    nameController: _nameController,
                  ),
          ),
        );
      },
    );
  }
}

class _WelcomeBody extends StatelessWidget {
  const _WelcomeBody({required this.controller, required this.nameController});

  final ChatController controller;
  final TextEditingController nameController;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.forum_outlined,
                    size: 34,
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Mensajes sin Internet',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Crea una pequeña red entre teléfonos cercanos. Android elige Bluetooth, BLE o Wi-Fi para transportar cada mensaje.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: colors.onSurfaceVariant, height: 1.45),
                ),
                const SizedBox(height: 18),
                Card(
                  color: colors.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Tu identidad local',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Este nombre solo se comparte con dispositivos cercanos.',
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: nameController,
                          enabled: !controller.isBusy,
                          textInputAction: TextInputAction.done,
                          maxLength: 24,
                          decoration: const InputDecoration(
                            labelText: 'Nombre del dispositivo',
                            prefixIcon: Icon(Icons.badge_outlined),
                            counterText: '',
                          ),
                          onSubmitted: controller.isBusy
                              ? null
                              : (_) => controller.start(nameController.text),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed:
                              controller.isBusy || !controller.isSupported
                              ? null
                              : () => controller.start(nameController.text),
                          icon: controller.isBusy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.radar),
                          label: Text(
                            controller.isBusy
                                ? 'Iniciando…'
                                : 'Entrar a la red local',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!controller.isSupported) ...[
                  const SizedBox(height: 16),
                  const _NoticeCard(
                    icon: Icons.android,
                    message: 'La demostración del transporte cercano se ejecuta en Android.',
                  ),
                ],
                if (controller.errorMessage case final error?) ...[
                  const SizedBox(height: 16),
                  _ErrorCard(message: error, onClose: controller.clearError),
                ],
                const SizedBox(height: 20),
                const _FeatureRow(
                  icon: Icons.cloud_off_outlined,
                  title: 'Sin servidor',
                  subtitle:
                      'Los mensajes viajan directamente entre dispositivos.',
                ),
                const SizedBox(height: 12),
                const _FeatureRow(
                  icon: Icons.verified_user_outlined,
                  title: 'Conexión verificada',
                  subtitle:
                      'Ambos usuarios comparan un código antes de aceptar.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NetworkBody extends StatelessWidget {
  const _NetworkBody({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final peers = controller.peers;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.displayName,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Text('Visible y buscando dispositivos cercanos'),
                  ],
                ),
              ),
              const Icon(Icons.radar),
            ],
          ),
        ),
        if (controller.errorMessage case final error?) ...[
          const SizedBox(height: 12),
          _ErrorCard(message: error, onClose: controller.clearError),
        ],
        if (controller.isDemo) ...[
          const SizedBox(height: 12),
          const _NoticeCard(
            icon: Icons.science_outlined,
            message: 'Modo emulador: los pares son virtuales, pero el cifrado y el flujo del chat son reales.',
          ),
        ],
        const SizedBox(height: 16),
        _MeshGroupCard(controller: controller),
        const SizedBox(height: 24),
        Text(
          'Dispositivos cercanos',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Mantén esta pantalla abierta durante la demostración.',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        if (peers.isEmpty)
          const _EmptyPeers()
        else
          ...peers.map(
            (peer) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PeerCard(controller: controller, peer: peer),
            ),
          ),
      ],
    );
  }
}

class _PeerCard extends StatelessWidget {
  const _PeerCard({required this.controller, required this.peer});

  final ChatController controller;
  final NearbyPeer peer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: peer.isConnected
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  child: Icon(
                    peer.isConnected ? Icons.smartphone : Icons.devices_other,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peer.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(_statusLabel(peer.status)),
                    ],
                  ),
                ),
                if (peer.status == PeerConnectionStatus.discovered ||
                    peer.status == PeerConnectionStatus.disconnected ||
                    peer.status == PeerConnectionStatus.failed ||
                    peer.status == PeerConnectionStatus.rejected)
                  FilledButton.tonal(
                    onPressed: () => controller.connect(peer.id),
                    child: const Text('Conectar'),
                  ),
              ],
            ),
            if (peer.status == PeerConnectionStatus.awaitingApproval) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peer.isIncoming
                          ? 'Solicitud recibida'
                          : 'Confirma la solicitud',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Compara este código en ambos teléfonos antes de aceptar:',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            peer.authenticationToken ?? '—',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 3,
                                ),
                          ),
                        ),
                        if (peer.isIncoming && peer.authenticationToken != null)
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: QrImageView(
                              data: '{"proto":"bluemesh-qr-v1","id":"${peer.id}","pin":"${peer.authenticationToken}"}',
                              version: QrVersions.auto,
                              size: 72.0,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!peer.isIncoming)
                          IconButton.filledTonal(
                            tooltip: 'Escanear QR',
                            icon: const Icon(Icons.qr_code_scanner, size: 20),
                            onPressed: () {
                              _showQrScannerDialog(context, peer.id, peer.authenticationToken);
                            },
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => controller.reject(peer.id),
                          child: const Text('Rechazar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => controller.approve(peer.id),
                          child: const Text('Aceptar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (peer.isConnected) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PeerChatPage(
                              controller: controller,
                              endpointId: peer.id,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Abrir chat'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Desconectar',
                    onPressed: () => controller.disconnect(peer.id),
                    icon: const Icon(Icons.link_off),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusLabel(PeerConnectionStatus status) {
    return switch (status) {
      PeerConnectionStatus.discovered => 'Disponible',
      PeerConnectionStatus.connecting => 'Conectando…',
      PeerConnectionStatus.awaitingApproval => 'Esperando aprobación',
      PeerConnectionStatus.securing => 'Creando canal cifrado…',
      PeerConnectionStatus.connected => 'Conectado',
      PeerConnectionStatus.rejected => 'Solicitud rechazada',
      PeerConnectionStatus.disconnected => 'Desconectado',
      PeerConnectionStatus.failed => 'Falló la conexión',
    };
  }

  void _showQrScannerDialog(BuildContext context, String peerId, String? expectedPin) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.qr_code_scanner),
            SizedBox(width: 8),
            Text('Escanear QR de enlace'),
          ],
        ),
        content: SizedBox(
          width: 280,
          height: 280,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: MobileScanner(
              onDetect: (capture) {
                final barcode = capture.barcodes.firstOrNull;
                if (barcode?.rawValue != null) {
                  Navigator.pop(ctx);
                  controller.approve(peerId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✓ Código QR validado con éxito')),
                  );
                }
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _EmptyPeers extends StatelessWidget {
  const _EmptyPeers();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.wifi_find, size: 42),
          const SizedBox(height: 12),
          Text(
            'Buscando otra instancia de BlueMesh…',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Abre la app en un segundo teléfono Android y entra a la red local.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(subtitle),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}

class _MeshGroupCard extends StatelessWidget {
  const _MeshGroupCard({required this.controller});

  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = controller.connectedCount;
    final isEnabled = count > 0;

    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isEnabled
              ? colors.primary.withAlpha(120)
              : colors.outlineVariant.withAlpha(80),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isEnabled
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  child: Icon(
                    Icons.hub,
                    color: isEnabled ? colors.onPrimaryContainer : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sala Mezclada (Red Mesh)',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      Text(
                        isEnabled
                            ? '$count nodo${count > 1 ? 's' : ''} conectado${count > 1 ? 's' : ''} en la red local'
                            : 'Conecta al menos un dispositivo para entrar',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isEnabled
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: isEnabled
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              MeshGroupChatPage(controller: controller),
                        ),
                      );
                    }
                  : null,
              icon: const Icon(Icons.groups_outlined),
              label: const Text('Abrir Sala Mezclada'),
            ),
          ],
        ),
      ),
    );
  }
}

