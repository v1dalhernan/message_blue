# Trama

Mensajería local para Android con enlaces Nearby (Bluetooth/BLE/Wi-Fi), chats privados cifrados y retransmisión a través de otros teléfonos.

## Ejecutar

En teléfonos Android físicos con Google Play Services:

```sh
flutter pub get
flutter run
```

La app usa Nearby por defecto. Activa Bluetooth, Wi-Fi y ubicación; concede los permisos solicitados. Internet no es necesario. Compara el código de conexión en ambos teléfonos antes de aceptar. Para un destinatario indirecto puedes introducir su PIN temporal o comparar el código criptográfico del chat.

Para emuladores y desarrollo de escritorio:

```sh
dart run bin/lan_hub.dart
flutter run -d <device-id> --dart-define=LAN_MODE=true
```

El hub es una herramienta de desarrollo de confianza. No debe exponerse a Internet ni utilizarse como servidor de producción. La demo de un solo dispositivo se activa con `--dart-define=DEMO_MODE=true`.

## Comportamiento

- Un chat de A a C puede cruzar B, con sobres cifrados para el destinatario final. B no muestra ni descifra ese chat privado.
- Direcciones de malla estables derivadas de claves públicas; anuncios de rutas, límite de saltos, deduplicación, confirmaciones del destino y reintentos.
- Texto, fotos y notas de voz; fragmentación de adjuntos para respetar el límite de paquetes de Nearby.
- PIN temporal basado en HMAC y validado por el teléfono que muestra el código. El reloj del solicitante no se utiliza para validarlo.
- Notificaciones del sistema para los chats que no estás viendo. No hay banners de mensajes dentro de la app. En segundo plano también se permite avisar del último chat abierto.
- Historial y pendientes guardados en el dispositivo. Salir de la red conserva las conversaciones.
- Sala pública de la malla. Los participantes y repetidores de esa sala pueden leer sus mensajes.
- Nombre visible e icono: Trama. El identificador Android y el nombre del paquete Dart se conservan para permitir actualizaciones.

## Código activo

La entrada es `lib/main.dart`, que utiliza `lib/src/screens/`, `lib/src/chat_controller.dart` y `lib/src/nearby/mesh_transport.dart`. La malla funciona sobre `NearbyConnectionsTransport` o `LanSocketTransport`.

También existe una arquitectura alternativa bajo `presentation/`, `domain/` y `data/` que no está conectada al punto de entrada. No debe confundirse con el recorrido activo ni considerarse una implementación terminada de grupos privados.

## Verificar

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --debug --no-pub
```

Las pruebas incluyen una topología A—B—C sin enlace A—C, recepción cifrada, PIN incorrecto, verificación bilateral, multimedia, ediciones, lectura, reconexión, deduplicación, visibilidad de notificaciones, fragmentación y restauración local.

Consulta [validación y límites](docs/VALIDATION.md) antes de usarlo como producto terminado. Falta la prueba física de tres Android. iOS/macOS usan LAN de desarrollo; no tienen malla Bluetooth de producción. El servicio Android no garantiza recepción tras una detención forzada o si el sistema termina el proceso. Esta versión no está preparada para publicarse en una tienda.
