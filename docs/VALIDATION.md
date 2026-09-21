# Trama: validación y límites

## Recorridos implementados

- Android inicia Nearby Connections por defecto. LAN requiere `--dart-define=LAN_MODE=true` y un hub de desarrollo.
- Los enlaces usan `P2P_CLUSTER`. La capa de malla anuncia direcciones derivadas de claves públicas, aprende rutas de hasta seis nodos y renueva anuncios cada 15 segundos.
- Un destinatario indirecto se verifica con su PIN temporal o comparando el mismo código criptográfico en ambas pantallas. Un nodo intermedio retransmite el sobre cifrado; no recibe el chat privado.
- Texto y adjuntos esperan confirmación del destino, con tres intentos. Los mensajes pendientes de texto se reenvían cuando vuelve una ruta verificada. El receptor deduplica los reintentos.
- Nearby fragmenta los sobres grandes en paquetes menores de 32 KiB y limita cada transferencia ensamblada a 12 MiB.
- Historial y pendientes se guardan localmente. Salir de la red conserva las conversaciones. Los mensajes que quedaron enviándose al cerrar se recuperan como pendientes.
- Los avisos de mensajes son notificaciones del sistema. Se suprimen únicamente cuando esa conversación está visible y la app está en primer plano. Al tocar el aviso se abre la conversación.
- Android mantiene un servicio de red con aviso persistente mientras el usuario está conectado. Salir de la red lo detiene.

## Prueba física pendiente

1. Instalar la misma versión en tres Android con Google Play Services. Usar la compilación normal, sin `LAN_MODE`.
2. Habilitar Bluetooth, Wi-Fi, ubicación y permisos de dispositivos cercanos/notificaciones. Internet no es necesario.
3. Enlazar A con B y B con C. Comparar los códigos en cada enlace. No enlazar A directamente con C.
4. Separar A y C hasta que no puedan descubrirse directamente; B debe mantener ambos enlaces. Verificar al destinatario C desde A y enviar texto, foto y audio.
5. Confirmar recepción en C y ausencia del chat privado en B. Enviar una respuesta, una edición y una confirmación de lectura.
6. Desconectar B, enviar texto y volver a conectarlo. Comprobar entrega del pendiente una sola vez.
7. En C, abrir el chat con A: un mensaje nuevo de A no debe generar aviso. Desde otro chat o con la pantalla bloqueada sí debe aparecer en Android. Tocar el aviso debe abrir el chat y retirarlo.
8. Cerrar y abrir la app: comprobar historial y pendientes. Probar también denegar permisos y un PIN incorrecto/caducado.

## Alcance real

Las pruebas con enlaces simulados comprueban encaminamiento, cifrado, deduplicación, verificación y reconexión; no prueban alcance de antenas ni ahorro de batería de fabricantes. Los emuladores usan TCP y no reproducen la radio Nearby.

El servicio Android mejora la continuidad con la app en segundo plano; no promete recepción después de forzar detención, reiniciar el teléfono o que Android termine el proceso. La implementación iOS/macOS usa LAN para desarrollo; no ofrece una malla Bluetooth de producción en esas plataformas.

La sala pública es visible para sus participantes, incluidos los repetidores. Los chats privados usan cifrado entre destinatarios. Las claves de identidad son persistentes: esta versión no ofrece secreto hacia adelante. La identidad y el historial residen en almacenamiento privado de la app, sin una capa adicional de cifrado del archivo. El PIN de enlace es una verificación de proximidad, no un segundo factor de una cuenta de usuario.

No es todavía un release de tienda: Android mantiene firma de depuración y falta la validación física de tres teléfonos.

Referencias: [Nearby y límite de paquetes](https://developers.google.com/nearby/connections/overview), [servicio connectedDevice](https://developer.android.com/develop/background-work/services/fgs/service-types).
