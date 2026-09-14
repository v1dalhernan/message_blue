import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/whatsapp_theme.dart';
import '../../domain/entities/pairing_session_entity.dart';

class IncomingConnectionModal extends StatelessWidget {
  const IncomingConnectionModal({
    super.key,
    required this.session,
    required this.onAccept,
    required this.onReject,
  });

  final PairingSessionEntity session;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.security, color: WhatsAppTheme.primaryTeal, size: 28),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Solicitud de Conexión',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${session.peerName} desea establecer un canal seguro cifrado punto a punto contigo.',
            style: const TextStyle(fontSize: 14.5, height: 1.3),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WhatsAppTheme.primaryTeal.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_outline, size: 20, color: WhatsAppTheme.primaryTeal),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Se generará un código QR y un PIN de 6 dígitos para validar la identidad.',
                    style: TextStyle(fontSize: 12, color: WhatsAppTheme.darkTeal),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onReject,
          child: const Text('Rechazar', style: TextStyle(color: Colors.red)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: WhatsAppTheme.primaryTeal,
            foregroundColor: Colors.white,
          ),
          onPressed: onAccept,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Aceptar y Verificar'),
        ),
      ],
    );
  }
}

class QrDisplaySheet extends StatelessWidget {
  const QrDisplaySheet({
    super.key,
    required this.session,
    required this.onCancel,
  });

  final PairingSessionEntity session;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final pin = session.sixDigitPin ?? '------';
    final qrData = session.qrPayload ?? pin;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'Autorizar Dispositivo',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Muestra este código QR a ${session.peerName} o dicta el PIN de 6 dígitos.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, color: Colors.black54),
          ),
          const SizedBox(height: 18),

          // Dynamic QR Code Container
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 190.0,
            ),
          ),
          const SizedBox(height: 18),

          // 6-Digit PIN Display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: WhatsAppTheme.lightOutgoingBubble,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: WhatsAppTheme.primaryTeal.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pin, color: WhatsAppTheme.darkTeal, size: 20),
                const SizedBox(width: 8),
                Text(
                  'PIN: ${pin.substring(0, 3)} ${pin.substring(3)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: WhatsAppTheme.darkTeal,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: WhatsAppTheme.darkTeal),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: pin));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('PIN copiado al portapapeles')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: WhatsAppTheme.primaryTeal),
              ),
              SizedBox(width: 8),
              Text(
                'Esperando verificación del otro dispositivo...',
                style: TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onCancel,
            child: const Text('Cancelar conexión', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class QrScannerOrPinDialog extends StatefulWidget {
  const QrScannerOrPinDialog({
    super.key,
    required this.session,
    required this.onVerifyPin,
    required this.onVerifyQr,
    required this.onCancel,
  });

  final PairingSessionEntity session;
  final Future<bool> Function(String pin) onVerifyPin;
  final Future<bool> Function(String qr) onVerifyQr;
  final VoidCallback onCancel;

  @override
  State<QrScannerOrPinDialog> createState() => _QrScannerOrPinDialogState();
}

class _QrScannerOrPinDialogState extends State<QrScannerOrPinDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submitPin() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      setState(() => _error = 'El PIN debe contener 6 dígitos.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final success = await widget.onVerifyPin(pin);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = 'PIN incorrecto. Verifica con el otro dispositivo.');
    }
  }

  Future<void> _onDetectBarcode(BarcodeCapture capture) async {
    if (_isLoading) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null) {
        setState(() => _isLoading = true);
        final ok = await widget.onVerifyQr(raw);
        if (!mounted) return;
        setState(() => _isLoading = false);
        if (ok) {
          Navigator.of(context).pop(true);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Column(
          children: [
            Container(
              decoration: const BoxDecoration(
                color: WhatsAppTheme.primaryTeal,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Row(
                      children: [
                        const Icon(Icons.qr_code_scanner, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Verificar ${widget.session.peerName}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: widget.onCancel,
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: WhatsAppTheme.accentGreen,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    tabs: const [
                      Tab(icon: Icon(Icons.camera_alt, size: 20), text: 'Escanear QR'),
                      Tab(icon: Icon(Icons.dialpad, size: 20), text: 'Digitar PIN'),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Live QR Scanner + Simulator quick-scan button
                  Column(
                    children: [
                      Expanded(
                        child: ClipRect(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              MobileScanner(onDetect: _onDetectBarcode),
                              Container(
                                width: 180,
                                height: 180,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: WhatsAppTheme.accentGreen,
                                    width: 2.5,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Column(
                          children: [
                            const Text(
                              'Apunta la cámara al código QR del otro dispositivo.',
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                              textAlign: TextAlign.center,
                            ),
                            if (widget.session.sixDigitPin != null) ...[
                              const SizedBox(height: 6),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.check_circle_outline, size: 16),
                                label: Text(
                                  'Emparejar con PIN (${widget.session.sixDigitPin})',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onPressed: () {
                                  _pinController.text = widget.session.sixDigitPin!;
                                  _submitPin();
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Tab 2: 6-Digit PIN input
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Introduce el código de 6 dígitos que muestra el otro dispositivo:',
                          style: TextStyle(fontSize: 14, height: 1.3),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _pinController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 8,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '000000',
                            filled: true,
                            fillColor: WhatsAppTheme.lightChatBg,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: WhatsAppTheme.primaryTeal),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: WhatsAppTheme.primaryTeal,
                            minimumSize: const Size.fromHeight(46),
                          ),
                          onPressed: _isLoading ? null : _submitPin,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.lock_open),
                          label: const Text('Verificar y Conectar'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
