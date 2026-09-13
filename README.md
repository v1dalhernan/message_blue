# BlueMesh

BlueMesh is an Android proof of concept for nearby text messaging without a backend or Internet connection. Devices advertise and discover one another locally, verify a shared connection code, and exchange messages directly.

The app uses [Google Nearby Connections](https://developers.google.com/nearby/connections/overview) through Flutter. Nearby Connections selects Bluetooth, BLE, or Wi-Fi as the underlying transport according to device availability.

> This repository demonstrates local peer-to-peer communication. It is not intended to replace a production messenger.

## Demo scope

- Continuous advertising and discovery of nearby Android devices.
- Many-to-many `P2P_CLUSTER` topology for small text payloads.
- Explicit approval on both devices using the authentication token.
- One-to-one conversations with delivery attempt state.
- Runtime permission handling for Android 6 through Android 16.
- No account, cloud service, mobile data, or shared Wi-Fi network required.

## How it works

```mermaid
flowchart LR
    A[Device A advertises and discovers] --> C[Nearby connection request]
    B[Device B advertises and discovers] --> C
    C --> D{Codes match?}
    D -->|Both accept| E[Direct local channel]
    D -->|Reject| F[Connection closed]
    E --> G[UTF-8 JSON text payloads]
```

The UI and message model depend on a small `NearbyTransport` interface. `NearbyConnectionsTransport` is the Android adapter, so another transport such as native Wi-Fi Direct can be evaluated later without coupling it to the chat screens.

## Run the proof of concept

Requirements:

- Two physical Android devices with Google Play services.
- Bluetooth, Wi-Fi, and Location services enabled.
- Flutter compatible with Dart `3.13` or newer.

```bash
flutter pub get
flutter run
```

Install and open the app on both phones:

1. Give each device a different local name.
2. Tap **Enter the local network** and grant the requested nearby-device permissions.
3. Select the other device and tap **Connect**.
4. Compare the authentication code shown on both phones, then accept on both.
5. Open the chat and exchange messages. Airplane mode can be enabled as long as Bluetooth and Wi-Fi remain available.

Nearby Connections does not work in the Android emulator, so the radio path must be verified on real hardware.

## Project structure

```text
lib/
├── main.dart
└── src/
    ├── chat_controller.dart
    ├── models/
    ├── nearby/
    │   ├── nearby_transport.dart
    │   └── nearby_connections_transport.dart
    └── screens/
```

## Current limitations

- Android only; the selected plugin does not implement iOS.
- Messages live in memory and disappear when the app closes.
- Discovery is designed for an active foreground demonstration.
- Text messages only; file and media payloads are outside this POC.
- Delivery status means the payload was handed to the Nearby API. There is no application-level read receipt.
- Physical-device interoperability still needs to be validated across Android versions and manufacturers.

## Possible next experiments

1. Add message acknowledgements and local persistence.
2. Compare Nearby Connections with a native Wi-Fi Direct transport.
3. Add store-and-forward relaying with message IDs and loop prevention.
4. Add end-to-end encryption at the application layer and key verification.
5. Add an iOS adapter based on Multipeer Connectivity.

## Validation

```bash
flutter analyze
flutter test
```

---

## Español

BlueMesh es una prueba de concepto de mensajería cercana para Android. Dos o más teléfonos pueden encontrarse y enviarse texto directamente mediante Bluetooth, BLE o Wi-Fi, sin servidor y sin acceso a Internet. Antes de conectarse, ambos usuarios comparan un código de autenticación y aceptan la solicitud.

La demostración requiere dispositivos Android físicos; el emulador no implementa el transporte de Nearby Connections.
