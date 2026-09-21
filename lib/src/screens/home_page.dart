import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../chat_controller.dart';
import '../core/profile/user_profile_service.dart';
import '../core/notifications/chat_notifications.dart';
import '../models/chat_message.dart';
import '../models/nearby_peer.dart';
import '../nearby/nearby_transport.dart';
import 'mesh_group_chat_page.dart';
import 'peer_chat_page.dart';
import 'widgets/totp_pin_widget.dart';
import 'widgets/user_avatar_widget.dart';

const bool kEnterpriseMode = bool.fromEnvironment(
  'ENTERPRISE',
  defaultValue: false,
);

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.transport,
    this.enablePlatformServices = true,
  });

  final NearbyTransport transport;
  final bool enablePlatformServices;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late final ChatController _controller;
  late final TextEditingController _nameController;
  StreamSubscription<ChatMessage>? _msgSub;
  final ChatNotifications _notifications = ChatNotifications();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ChatController(
      widget.transport,
      persistHistory: widget.enablePlatformServices,
    );
    _nameController = TextEditingController(text: 'Android cercano');
    _initProfile();

    _notifications.onOpenChat = (chat) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => chat == ChatMessage.groupEndpointId
              ? MeshGroupChatPage(controller: _controller)
              : PeerChatPage(controller: _controller, endpointId: chat),
        ),
      );
    };
    _msgSub = _controller.incomingMessageNotifications.listen((msg) {
      if (!widget.enablePlatformServices) return;
      unawaited(
        _notifications
            .show(
              msg,
              shouldShow: () =>
                  mounted &&
                  !_controller.isChatVisible(ChatNotifications.chatId(msg)),
            )
            .catchError((Object error) => debugPrint('Notificación: $error')),
      );
    });
    _controller.addListener(_clearReadNotifications);
    if (widget.enablePlatformServices) {
      unawaited(
        _notifications.initialize().catchError(
          (Object error) => debugPrint('Notificaciones: $error'),
        ),
      );
    }
  }

  void _clearReadNotifications() {
    if (!widget.enablePlatformServices) return;
    for (final chat in [
      ChatMessage.groupEndpointId,
      ..._controller.peers.map((p) => p.id),
    ]) {
      if (_controller.isChatVisible(chat)) {
        unawaited(
          _notifications
              .cancel(chat)
              .catchError((Object error) => debugPrint('Notificación: $error')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.setForeground(state == AppLifecycleState.resumed);
  }

  Future<void> _initProfile() async {
    if (!widget.enablePlatformServices) return;
    await _controller.initialize();
    if (!mounted) return;
    unawaited(
      _notifications.requestPermission().catchError(
        (Object error) => debugPrint('Permiso de notificaciones: $error'),
      ),
    );
    final savedName = UserProfileService.instance.displayName;
    if (savedName.isNotEmpty && savedName != 'Android cercano' && mounted) {
      _nameController.text = savedName;
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _notifications.onOpenChat = null;
    _controller.removeListener(_clearReadNotifications);
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
                Text('Trama'),
              ],
            ),
            actions: [
              if (_controller.isRunning) ...[
                IconButton(
                  tooltip: 'Mi Perfil',
                  onPressed: () => _showProfileSheet(context, _controller),
                  icon: UserAvatarWidget(
                    avatarBase64: _controller.localAvatar,
                    name: _controller.displayName,
                    radius: 14,
                    showBadge: false,
                  ),
                ),
                if (!kEnterpriseMode)
                  IconButton(
                    tooltip: 'Salir de la red local',
                    onPressed: _controller.isBusy ? null : _controller.stop,
                    icon: const Icon(Icons.power_settings_new),
                  ),
              ],
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
                Center(
                  child: Container(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatarWidget(
                    avatarBase64: controller.localAvatar,
                    name: controller.displayName,
                    radius: 26,
                    onTap: () => _showAvatarSelectionSheet(context, controller),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                controller.displayName,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary.withAlpha(40),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                controller.localUniqueId,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Visible y buscando dispositivos cercanos',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.radar),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colors.surface.withAlpha(200),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colors.outlineVariant.withAlpha(100),
                  ),
                ),
                child: const TotpPinWidget(compact: true),
              ),
              if (controller.offlineMailboxCount > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.mark_email_unread_outlined,
                        size: 16,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${controller.offlineMailboxCount} mensaje(s) en buzón esperando entrega',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
    final unreadCount = controller.getUnreadCount(peer.id);

    return Card(
      color: colors.surface,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: peer.isConnected
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PeerChatPage(
                      controller: controller,
                      endpointId: peer.id,
                    ),
                  ),
                );
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  UserAvatarWidget(
                    avatarBase64:
                        peer.avatarBase64 ??
                        controller.userProfileService.getPeerAvatar(peer.id),
                    name: peer.name,
                    radius: 22,
                    showBadge: false,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                peer.name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (peer.uniqueId != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  peer.uniqueId!,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            if (unreadCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF25D366),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$unreadCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: switch (peer.status) {
                                  PeerConnectionStatus.connected =>
                                    Colors.teal,
                                  PeerConnectionStatus.awaitingApproval ||
                                  PeerConnectionStatus.securing ||
                                  PeerConnectionStatus.connecting =>
                                    Colors.amber.shade700,
                                  _ => Colors.grey.shade400,
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _statusLabel(peer.status),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: peer.isConnected
                                      ? Colors.teal
                                      : colors.onSurfaceVariant,
                                  fontWeight: peer.isConnected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (peer.status == PeerConnectionStatus.discovered ||
                      peer.status == PeerConnectionStatus.disconnected ||
                      peer.status == PeerConnectionStatus.failed ||
                      peer.status == PeerConnectionStatus.rejected)
                    FilledButton.tonal(
                      onPressed: () =>
                          _showPinConnectionDialog(context, controller, peer),
                      child: const Text('Conectar'),
                    )
                  else if (peer.status == PeerConnectionStatus.connecting ||
                      peer.status == PeerConnectionStatus.securing)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ),
                ],
              ),
            if (peer.isSpoofed) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: colors.onErrorContainer,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '¡Alerta de Seguridad! Este dispositivo parece estar suplantando la identidad de "${peer.name}". La clave criptográfica no coincide con el registro previo.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.onErrorContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                              data:
                                  '{"proto":"bluemesh-qr-v1","id":"${peer.id}","pin":"${peer.authenticationToken}"}',
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
                              _showQrScannerDialog(
                                context,
                                peer.id,
                                peer.authenticationToken,
                              );
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
                      label: Text(
                        unreadCount > 0
                            ? 'Abrir chat ($unreadCount)'
                            : 'Abrir chat',
                      ),
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
    ));
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

  void _showQrScannerDialog(
    BuildContext context,
    String peerId,
    String? expectedPin,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.qr_code_scanner),
            SizedBox(width: 8),
            Flexible(child: Text('Escanear QR de enlace')),
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
                Map<String, dynamic>? payload;
                try {
                  final value = jsonDecode(barcode?.rawValue ?? '');
                  if (value is Map<String, dynamic>) payload = value;
                } catch (_) {}
                if (expectedPin != null &&
                    payload?['proto'] == 'bluemesh-qr-v1' &&
                    payload?['pin'] == expectedPin) {
                  Navigator.pop(ctx);
                  controller.approve(peerId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✓ Código QR validado con éxito'),
                    ),
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
            'Buscando otra instancia de Trama…',
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
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, color: colors.onErrorContainer),
          ),
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
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

void _showPinConnectionDialog(
  BuildContext context,
  ChatController controller,
  NearbyPeer peer,
) {
  final pinController = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.pin_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text('Conectar con ${peer.name}')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresa el PIN temporal que aparece en la pantalla de ${peer.name}:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'El código rota cada 30s. Si recién cambió, el código previo aún es válido.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                letterSpacing: 6,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: '000000',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Al escribir el código correcto, la conexión se establecerá y verificará automáticamente.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final code = pinController.text.trim();
            Navigator.pop(ctx);
            controller.connect(
              peer.id,
              enteredCode: code.isNotEmpty ? code : null,
            );
          },
          child: const Text('Conectar'),
        ),
      ],
    ),
  );
}

void _showAvatarSelectionSheet(
  BuildContext context,
  ChatController controller,
) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Foto de perfil en Trama',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Tu foto se transmitirá de forma liviana a los dispositivos cercanos en la red.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _avatarOptionButton(
                    context,
                    icon: Icons.camera_alt_outlined,
                    label: 'Cámara',
                    onTap: () async {
                      Navigator.pop(ctx);
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.camera,
                        maxWidth: 256,
                        maxHeight: 256,
                        imageQuality: 70,
                      );
                      if (picked != null) {
                        await controller.updateProfileAvatar(File(picked.path));
                      }
                    },
                  ),
                  _avatarOptionButton(
                    context,
                    icon: Icons.photo_library_outlined,
                    label: 'Galería',
                    onTap: () async {
                      Navigator.pop(ctx);
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                        maxWidth: 256,
                        maxHeight: 256,
                        imageQuality: 70,
                      );
                      if (picked != null) {
                        await controller.updateProfileAvatar(File(picked.path));
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'O selecciona un avatar rápido:',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ['🦊', '🤖', '🚀', '🐱', '⚡', '🛡️'].map((emoji) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      Navigator.pop(ctx);
                      controller.setPresetAvatar(emoji);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(emoji, style: const TextStyle(fontSize: 28)),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _avatarOptionButton(
  BuildContext context, {
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) {
  final colors = Theme.of(context).colorScheme;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: colors.primary),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    ),
  );
}

void _showProfileSheet(BuildContext context, ChatController controller) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final colors = Theme.of(context).colorScheme;
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              left: 20,
              right: 20,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Mi Perfil',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: UserAvatarWidget(
                      avatarBase64: controller.localAvatar,
                      name: controller.displayName,
                      radius: 46,
                      onTap: () {
                        _showAvatarSelectionSheet(context, controller);
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 0,
                    color: colors.surfaceContainerLow,
                    child: ListTile(
                      onTap: () => _showEditNameDialog(context, controller),
                      leading: const Icon(Icons.person_outline),
                      title: const Text(
                        'Nombre',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      subtitle: Text(
                        controller.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () {
                          _showEditNameDialog(context, controller);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 0,
                    color: colors.surfaceContainerLow,
                    child: ListTile(
                      onTap: () => _showEditStatusDialog(context, controller),
                      leading: const Icon(Icons.info_outline),
                      title: const Text(
                        'Info. actual',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      subtitle: Text(
                        controller.statusMessage,
                        style: const TextStyle(fontSize: 15),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () {
                          _showEditStatusDialog(context, controller);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 0,
                    color: colors.surfaceContainerLow,
                    child: ListTile(
                      leading: const Icon(
                        Icons.verified_user_outlined,
                        color: Colors.teal,
                      ),
                      title: const Text(
                        'Identidad Criptográfica',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.localUniqueId,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Anti-suplantación TOFU activa. Protege tus chats con cifrado ECDH E2E.',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const TotpPinWidget(compact: false),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

void _showEditNameDialog(BuildContext context, ChatController controller) {
  final nameCtrl = TextEditingController(text: controller.displayName);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Editar nombre'),
      content: SingleChildScrollView(
        child: TextField(
          controller: nameCtrl,
          maxLength: 24,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tu nombre en Trama',
            counterText: '',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final newName = nameCtrl.text.trim();
            if (newName.isNotEmpty) {
              controller.updateDisplayName(newName);
            }
            Navigator.pop(ctx);
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

void _showEditStatusDialog(BuildContext context, ChatController controller) {
  final statusCtrl = TextEditingController(text: controller.statusMessage);
  final suggestions = [
    '¡Hola! Estoy usando Trama.',
    'Disponible',
    'En una reunión',
    'En el trabajo',
    'Solo mensajes importantes',
  ];

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Editar info'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: statusCtrl,
              maxLength: 60,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Estado o bio'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sugerencias:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: suggestions.map((s) {
                return ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    statusCtrl.text = s;
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final newStatus = statusCtrl.text.trim();
            if (newStatus.isNotEmpty) {
              controller.updateStatusMessage(newStatus);
            }
            Navigator.pop(ctx);
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}
