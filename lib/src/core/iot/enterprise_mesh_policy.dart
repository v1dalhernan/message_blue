import 'package:flutter/foundation.dart';

/// Políticas de Red y Modo Corporativo/Empresarial.
/// Permite que organizaciones o fábricas configuren la red en modo quiosco o flota,
/// restringiendo la desconexión manual del usuario y manteniendo la malla siempre activa.
class EnterpriseMeshPolicy extends ChangeNotifier {
  EnterpriseMeshPolicy._();
  static final EnterpriseMeshPolicy instance = EnterpriseMeshPolicy._();

  bool _allowUserDisconnect = true;
  bool _enforceAlwaysConnected = false;
  bool _iotBridgingEnabled = true;
  String _organizationTag = 'OpenMesh Enterprise';

  bool get allowUserDisconnect => _allowUserDisconnect;
  bool get enforceAlwaysConnected => _enforceAlwaysConnected;
  bool get iotBridgingEnabled => _iotBridgingEnabled;
  String get organizationTag => _organizationTag;

  /// Configura la política corporativa para evitar que los usuarios se desconecten
  void setLockDisconnect(bool lock) {
    _allowUserDisconnect = !lock;
    _enforceAlwaysConnected = lock;
    notifyListeners();
  }

  void configureEnterprise({
    required bool lockDisconnect,
    required bool enableIot,
    String? orgTag,
  }) {
    _allowUserDisconnect = !lockDisconnect;
    _enforceAlwaysConnected = lockDisconnect;
    _iotBridgingEnabled = enableIot;
    if (orgTag != null) _organizationTag = orgTag;
    notifyListeners();
  }
}
