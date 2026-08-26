# Pixel Board

Lienzo colaborativo en tiempo real inspirado en r/place: un grid 32x32 compartido donde cada usuario pinta pixeles con límite de **5 pixeles cada 2 minutos**, y un **chat en vivo** con historial persistido en la base de datos. Especificación completa en `pixel-board-spec.md`.

## Estructura

```
pixel_board/
├── backend/        # Node.js + WebSocket (canvas en memoria) + SQLite (respaldo)
└── flutter_app/    # Cliente Flutter (web/Chrome)
```

## Cómo correr

### 1. Backend

```bash
cd pixel_board/backend
npm install        # solo la primera vez
npm start          # servidor en ws://localhost:3000
npm run smoke      # test de integración autónomo (levanta su propio servidor)
```

Variables de entorno opcionales: `PORT` (3000), `DB_PATH` (`pixel_board.sqlite`), `COOLDOWN_MS` (120000), `PIXELS_PER_CYCLE` (5).

El canvas y el estado de cooldown se persisten en SQLite y sobreviven reinicios.

### 2. Frontend

```bash
cd pixel_board/flutter_app
flutter pub get    # solo la primera vez
flutter run -d chrome
```

Para apuntar a otro backend (ej. emulador Android):

```bash
flutter run --dart-define=WS_URL=ws://10.0.2.2:3000
```

## Identidad del usuario

- El **nickname** es tu identidad única en el servidor: solo puede registrarse una vez.
- Al registrarte por primera vez, el backend te entrega un **token secreto** que se guarda junto al nickname en `shared_preferences`. En cada conexión se envían ambos: si sos el dueño, entrás con tu cuenta (cooldown incluido) sin ningún trámite.
- Si otro intenta entrar con un nombre ya registrado (sin el token correcto), ve el cartel **NOMBRE YA USADO · PROBÁ OTRO**.
- No hay contraseña: el token del navegador ES tu credencial. Si lo perdés (borrar datos del navegador, otra PC), ese nombre queda bloqueado. Es un MVP sin recuperación de cuenta.

## Estado del proyecto

- ✅ Fase 1: backend WebSocket con canvas en memoria + broadcast
- ✅ Fase 2: pantalla de login con pre-cheque de nombre vía WebSocket
- ✅ Fase 3: pizarra funcional conectada por WebSocket
- ✅ Fase 4: cooldown 5 pixeles / 2 minutos (backend como fuente de verdad)
- ✅ Fase 5: persistencia SQLite (pixels + usuarios con nickname único + token + mensajes de chat)
