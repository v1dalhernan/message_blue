import 'dart:convert';
import 'package:flutter/foundation.dart';

enum IotNodeType {
  sensor,
  actuator,
  gatewayRelay,
  industrialTelemetry,
}

/// Paquete compacto de telemetría IoT para la red BlueMesh.
/// Permite que microcontroladores (ESP32, Raspberry Pi, sensores industriales)
/// funcionen como nodos pasivos o puentes de retransmisión.
class IotTelemetryPacket {
  const IotTelemetryPacket({
    required this.nodeId,
    required this.nodeName,
    required this.type,
    required this.metricName,
    required this.metricValue,
    required this.unit,
    required this.batteryPercent,
    required this.timestamp,
    this.isRelay = true,
  });

  final String nodeId;
  final String nodeName;
  final IotNodeType type;
  final String metricName;
  final double metricValue;
  final String unit;
  final int batteryPercent;
  final DateTime timestamp;
  final bool isRelay;

  Map<String, dynamic> toJson() => {
        'proto': 'bluemesh-iot-v1',
        'nodeId': nodeId,
        'nodeName': nodeName,
        'type': type.name,
        'metricName': metricName,
        'metricValue': metricValue,
        'unit': unit,
        'battery': batteryPercent,
        'timestamp': timestamp.toIso8601String(),
        'isRelay': isRelay,
      };

  factory IotTelemetryPacket.fromJson(Map<String, dynamic> json) {
    return IotTelemetryPacket(
      nodeId: json['nodeId'] as String? ?? 'iot-unknown',
      nodeName: json['nodeName'] as String? ?? 'Sensor IoT',
      type: IotNodeType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => IotNodeType.sensor,
      ),
      metricName: json['metricName'] as String? ?? 'Lectura',
      metricValue: (json['metricValue'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit'] as String? ?? '',
      batteryPercent: json['battery'] as int? ?? 100,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      isRelay: json['isRelay'] as bool? ?? true,
    );
  }

  String toWireString() => jsonEncode(toJson());
}

/// Puente y gestor de nodos IoT para BlueMesh.
class IotMeshBridge extends ChangeNotifier {
  IotMeshBridge._() {
    // Nodos IoT de demostración / base para empresas
    _detectedIotNodes['sensor-temp-01'] = IotTelemetryPacket(
      nodeId: 'sensor-temp-01',
      nodeName: 'Sensor Industrial Planta #1',
      type: IotNodeType.industrialTelemetry,
      metricName: 'Temperatura Caldera',
      metricValue: 24.8,
      unit: '°C',
      batteryPercent: 94,
      timestamp: DateTime.now(),
    );
  }

  static final IotMeshBridge instance = IotMeshBridge._();

  final Map<String, IotTelemetryPacket> _detectedIotNodes = {};

  List<IotTelemetryPacket> get activeIotNodes =>
      _detectedIotNodes.values.toList();

  int get iotNodeCount => _detectedIotNodes.length;

  /// Procesa un paquete IoT recibido desde la malla
  bool processIotFrame(Map<String, dynamic> frame) {
    if (frame['proto'] == 'bluemesh-iot-v1') {
      try {
        final packet = IotTelemetryPacket.fromJson(frame);
        _detectedIotNodes[packet.nodeId] = packet;
        notifyListeners();
        return true;
      } catch (e) {
        debugPrint('Error decodificando paquete IoT: $e');
      }
    }
    return false;
  }

  /// Registra un nuevo sensor IoT
  void registerSensor({
    required String nodeId,
    required String name,
    required String metric,
    required double value,
    required String unit,
    int battery = 100,
  }) {
    _detectedIotNodes[nodeId] = IotTelemetryPacket(
      nodeId: nodeId,
      nodeName: name,
      type: IotNodeType.sensor,
      metricName: metric,
      metricValue: value,
      unit: unit,
      batteryPercent: battery,
      timestamp: DateTime.now(),
    );
    notifyListeners();
  }
}
