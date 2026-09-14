import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:message_blue/main.dart';
import 'package:message_blue/src/nearby/demo_nearby_transport.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('completes the encrypted emulator demo flow', (tester) async {
    final transport = DemoNearbyTransport();
    await tester.pumpWidget(BlueMeshApp(transport: transport));

    final enterButton = find.text('Entrar a la red local');
    await tester.ensureVisible(enterButton);
    await tester.tap(enterButton);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('Ana · Demo'), findsOneWidget);
    expect(find.text('Nodo Taller · Demo'), findsOneWidget);
    expect(find.textContaining('Modo emulador'), findsOneWidget);

    final connectButtons = find.text('Conectar');
    await tester.tap(connectButtons.first);
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.text('Confirma la solicitud'), findsOneWidget);
    expect(find.text('4821'), findsOneWidget);

    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle(const Duration(milliseconds: 800));

    expect(find.text('Conectado'), findsOneWidget);
    await tester.tap(find.text('Abrir chat'));
    await tester.pumpAndSettle();

    expect(find.text('Cifrado E2E · AES-256-GCM'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Hola desde el emulador');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle(const Duration(milliseconds: 900));

    expect(find.text('Hola desde el emulador'), findsOneWidget);
    expect(
      find.text('Mensaje recibido y descifrado correctamente.'),
      findsOneWidget,
    );
    expect(
      String.fromCharCodes(transport.lastWirePayload!),
      isNot(contains('Hola desde el emulador')),
    );
  });
}
