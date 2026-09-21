import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/identity/user_identity_service.dart';

/// Widget dinámico estilo 2FA (TOTP) que muestra un código PIN de 6 dígitos
/// que se renueva automáticamente cada 30 segundos, con indicador visual
/// de cuenta regresiva y progreso circular.
class TotpPinWidget extends StatefulWidget {
  const TotpPinWidget({super.key, this.compact = false});

  /// Si es true, se muestra en formato compacto para la barra superior.
  final bool compact;

  @override
  State<TotpPinWidget> createState() => _TotpPinWidgetState();
}

class _TotpPinWidgetState extends State<TotpPinWidget> {
  Timer? _timer;
  late String _pin;
  late int _remainingSeconds;
  late double _progress;

  @override
  void initState() {
    super.initState();
    _updateState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(_updateState);
      }
    });
  }

  void _updateState() {
    final service = UserIdentityService.instance;
    final now = DateTime.now();
    _pin = service.getCurrentPin(now);
    _remainingSeconds = service.getSecondsRemaining(now);
    _progress = service.getProgress(now);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _copyPin() {
    Clipboard.setData(ClipboardData(text: _pin));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Código PIN $_pin copiado al portapapeles'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final formattedPin = _pin.length >= 6
        ? '${_pin.substring(0, 3)} ${_pin.substring(3)}'
        : _pin;

    final isUrgent = _remainingSeconds <= 5;
    final timerColor = isUrgent ? colors.error : colors.primary;

    if (widget.compact) {
      return Row(
        children: [
          Icon(Icons.shield_outlined, size: 20, color: colors.primary),
          const SizedBox(width: 8),
          const Text(
            'PIN: ',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          SelectableText(
            formattedPin,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: colors.primary,
            ),
          ),
          const Spacer(),
          // Contador circular animado
          Tooltip(
            message:
                'Código dinámico tipo 2FA. Cambia automáticamente en ${_remainingSeconds}s.',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 2.5,
                    backgroundColor: colors.outlineVariant.withAlpha(80),
                    color: timerColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${_remainingSeconds}s',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: timerColor,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  icon: const Icon(Icons.copy, size: 15),
                  tooltip: 'Copiar PIN',
                  onPressed: _copyPin,
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Modo tarjeta extendida (para el perfil)
    return Card(
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'PIN temporal de enlace',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: 'Copiar PIN',
                  onPressed: _copyPin,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SelectableText(
                  formattedPin,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        value: _progress,
                        strokeWidth: 3,
                        backgroundColor: colors.outlineVariant.withAlpha(80),
                        color: timerColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cambia en ${_remainingSeconds}s',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: timerColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Este código rotativo evita conexiones no deseadas y se verifica con tolerancia temporal.',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
