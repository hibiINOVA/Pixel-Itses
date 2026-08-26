# Pixel Board — Especificación del Proyecto

## 1. Descripción del proyecto

**Pixel Board** es una aplicación colaborativa en tiempo real inspirada en el evento r/place de Reddit, donde múltiples usuarios pintan pixeles sobre un lienzo compartido y ven los cambios de todos los demás al instante.

**Concepto:** un grid (por ejemplo 32x32) visible para todos los usuarios conectados. Cada persona selecciona un color de una paleta fija y pinta un pixel a la vez tocándolo en pantalla. Para evitar que alguien sature el lienzo, cada usuario tiene un límite de **5 pixeles cada 2 minutos** — al agotarlos debe esperar la recarga.

**Alcance (versión simple, MVP):**
- Sin registro/login real: solo un nickname que genera un ID local
- Dos pantallas: inicio de sesión y la pizarra
- Sin historial ni "deshacer" — es un lienzo vivo y colectivo

**Cómo funciona técnicamente:**
- El **backend** (Node.js + WebSocket) mantiene el estado del canvas en memoria, valida cada intento de pintado (¿tiene pixeles disponibles?), actualiza el grid y transmite el cambio a todos los clientes conectados.
- El **frontend** (Flutter) se conecta por WebSocket, recibe el estado inicial del canvas, escucha actualizaciones en tiempo real y las dibuja con `CustomPainter`; también controla localmente el contador de pixeles restantes y el temporizador de recarga.

**Objetivo del ejercicio:** practicar comunicación bidireccional en tiempo real con WebSocket, manejo de estado compartido entre múltiples clientes, y renderizado eficiente de un grid en Flutter, con un alcance acotado para poder terminarlo sin complicarse.

---

## 2. Estructura del proyecto

```
pixel_board/
├── backend/
│   ├── server.js              # servidor WebSocket + HTTP
│   ├── canvas.js              # lógica del grid (matriz de colores)
│   ├── users.js               # cooldown y pixeles restantes por usuario
│   ├── db.js                  # persistencia simple (SQLite)
│   └── package.json
│
└── flutter_app/
    ├── lib/
    │   ├── main.dart
    │   ├── screens/
    │   │   ├── login_screen.dart      # inicio de sesión (nickname)
    │   │   └── board_screen.dart      # página principal con la pizarra
    │   ├── widgets/
    │   │   ├── pixel_canvas.dart      # CustomPainter del grid
    │   │   ├── color_palette.dart     # selector de colores fijo
    │   │   ├── pixel_swatch.dart      # un color individual de la paleta
    │   │   ├── retro_counter.dart     # texto pixel con borde (timer/contador)
    │   │   ├── retro_button.dart      # botón con estilo pixel/sombra dura
    │   │   ├── retro_text_field.dart  # input con estilo pixel
    │   │   └── pixel_battery_icon.dart # ícono de "torre de bloques"
    │   ├── services/
    │   │   └── websocket_service.dart # conexión, streams, reconexión
    │   └── models/
    │       └── pixel_state.dart       # estado del canvas + cooldown
    └── pubspec.yaml
```

### Plan de trabajo (5 fases)

1. **Backend base** — servidor WebSocket con canvas fijo en memoria (ej. 32x32). Al conectar, enviar snapshot completo. Al recibir `paint`, validar coordenadas, actualizar canvas, hacer broadcast.
2. **Flutter: pantalla de login** — campo de nickname → genera userId → guarda en local (`shared_preferences`) → navega a la pizarra.
3. **Flutter: pizarra funcional (sin cooldown)** — conectar WebSocket, pintar el canvas con `CustomPainter`, tap en un pixel envía `paint` y recibe `pixel_update`.
4. **Cooldown (5 pixeles / 2 min)** — backend lleva cuenta de pixeles restantes y timestamp de recarga por usuario; rechaza `paint` sin pixeles disponibles; Flutter muestra contador y temporizador.
5. **Persistencia** — guardar el canvas en SQLite para que sobreviva reinicios del backend.

---

## 3. Diagrama de flujo de datos

### Flujo 1: Usuario pinta un pixel (acción → persistencia → broadcast)

```
[UI - Flutter]
  Usuario toca un pixel en el grid
        │
        ▼
[UI] pixel_canvas.dart
  Convierte coordenadas de pantalla → coordenadas de grid (x, y)
        │
        ▼
[Servicio - Flutter] websocket_service.dart
  ¿pixelsRemaining > 0? (chequeo local, UX rápida)
        │
        ├── NO → muestra "sin pixeles, espera Xs" (no envía nada)
        │
        └── SÍ ▼
  Envía por WebSocket: { type: "paint", x, y, color, userId }
        │
        ▼
────────────────── red (WebSocket) ──────────────────
        │
        ▼
[Backend] server.js
  Recibe mensaje "paint"
        │
        ▼
[Backend] users.js
  Valida en servidor (fuente de verdad):
    - ¿userId tiene pixeles disponibles?
    - ¿cooldown ya expiró?
        │
        ├── NO válido → responde error al cliente, corta flujo
        │
        └── SÍ válido ▼
[Backend] canvas.js
  Actualiza canvas[x][y] = color (en memoria)
        │
        ▼
[Backend] db.js
  Escribe el pixel en SQLite (persistencia)
        │
        ▼
[Backend] users.js
  Descuenta 1 pixel al usuario / actualiza cooldownEndsAt
        │
        ▼
[Backend] server.js
  Broadcast a TODOS los clientes conectados:
    { type: "pixel_update", x, y, color }
  Y al usuario que pintó, además:
    { type: "cooldown_update", pixelsRemaining, cooldownEndsAt }
        │
        ▼
────────────────── red (WebSocket) ──────────────────
        │
        ▼
[Servicio - Flutter] websocket_service.dart (en cada cliente)
  Escucha el stream, recibe "pixel_update"
        │
        ▼
[Modelo - Flutter] pixel_state.dart
  Actualiza el estado local del canvas (notifica listeners)
        │
        ▼
[UI - Flutter] pixel_canvas.dart
  Repinta solo ese pixel vía CustomPainter (repaint)

  Si el mensaje fue "cooldown_update" (solo al usuario que pintó):
        ▼
[UI - Flutter] Actualiza contador de pixeles restantes y timer visual
```

### Flujo 2: Usuario entra a la app (carga inicial)

```
[UI] login_screen.dart
  Usuario ingresa nickname
        │
        ▼
[Servicio] Genera/recupera userId → guarda en shared_preferences
        │
        ▼
[UI] Navega a board_screen.dart
        │
        ▼
[Servicio] websocket_service.dart
  Abre conexión WebSocket con el backend, envía userId
        │
        ▼
────────────────── red (WebSocket) ──────────────────
        │
        ▼
[Backend] server.js
  Nueva conexión detectada
        │
        ▼
[Backend] db.js
  Lee el canvas completo desde SQLite
        │
        ▼
[Backend] users.js
  Busca o crea registro del usuario (pixelsRemaining, cooldownEndsAt)
        │
        ▼
[Backend] server.js
  Envía snapshot al cliente:
    { type: "canvas_snapshot", canvas, pixelsRemaining, cooldownEndsAt }
        │
        ▼
────────────────── red (WebSocket) ──────────────────
        │
        ▼
[Modelo] pixel_state.dart
  Carga el canvas completo en memoria local
        │
        ▼
[UI] pixel_canvas.dart
  Dibuja el grid completo (primer render)
        │
        ▼
[UI] Muestra contador de pixeles + cooldown inicial
```

**Puntos clave del flujo:**
- El backend es la única fuente de verdad — el frontend nunca actualiza su propio contador de pixeles sin confirmación del servidor.
- El canvas vive en memoria en el backend para velocidad; SQLite es solo respaldo para sobrevivir reinicios.
- Todo cliente conectado recibe cada `pixel_update`, no solo el que pintó — así el lienzo se ve igual para todos en tiempo real.

---

## 4. Diagrama de clases (base de datos SQLite)

```
═══════════════════════════════════════════════
                  ENTIDAD: User
═══════════════════════════════════════════════
┌─────────────────────────────────────────────┐
│                    User                      │
├─────────────────────────────────────────────┤
│ + id: TEXT (PK, uuid)                        │
│ + nickname: TEXT                             │
│ + pixelsRemaining: INTEGER (default 5)       │
│ + cooldownEndsAt: INTEGER (timestamp, null)  │
│ + createdAt: INTEGER (timestamp)             │
├─────────────────────────────────────────────┤
│ + hasPixelsAvailable(): bool                 │
│ + resetCooldown(): void                      │
│ + consumePixel(): void                       │
└─────────────────────────────────────────────┘
                     │
                     │ 1
                     │ pinta
                     │ *
                     ▼
═══════════════════════════════════════════════
                 ENTIDAD: Pixel
═══════════════════════════════════════════════
┌─────────────────────────────────────────────┐
│                   Pixel                      │
├─────────────────────────────────────────────┤
│ + x: INTEGER (PK compuesta)                  │
│ + y: INTEGER (PK compuesta)                  │
│ + color: TEXT (hex, ej. "#00FF87")           │
│ + updatedBy: TEXT (FK → User.id)             │
│ + updatedAt: INTEGER (timestamp)             │
├─────────────────────────────────────────────┤
│ + paint(color, userId): void                 │
└─────────────────────────────────────────────┘

  User (1) ─────── pinta ─────── (*) Pixel

  Un User puede pintar muchos Pixel a lo largo del tiempo
  (cada fila de Pixel solo guarda el ÚLTIMO color/autor,
  no historial).
```

### Esquema SQL

```sql
CREATE TABLE users (
  id             TEXT PRIMARY KEY,
  nickname       TEXT NOT NULL,
  pixelsRemaining INTEGER NOT NULL DEFAULT 5,
  cooldownEndsAt INTEGER,
  createdAt      INTEGER NOT NULL
);

CREATE TABLE pixels (
  x           INTEGER NOT NULL,
  y           INTEGER NOT NULL,
  color       TEXT NOT NULL DEFAULT '#FFFFFF',
  updatedBy   TEXT,
  updatedAt   INTEGER,
  PRIMARY KEY (x, y),
  FOREIGN KEY (updatedBy) REFERENCES users(id)
);
```

**Notas de diseño:**
- `pixels` usa clave primaria compuesta (x, y) — cada coordenada existe una sola vez, se hace `UPDATE` en lugar de `INSERT` cada vez que alguien pinta ahí.
- No hay tabla de historial (sin "deshacer" ni línea de tiempo).
- `cooldownEndsAt` es `null` cuando el usuario todavía tiene pixeles disponibles; solo se llena cuando llega a 0.
- Al iniciar el backend, se puede pre-poblar `pixels` con todas las coordenadas del grid en blanco (`#FFFFFF`), o generarlas on-demand la primera vez que alguien pinta ahí.

---

## 5. Diagrama de casos de uso

**Actor: Usuario**

- **UC1 — Iniciar sesión:** ingresa nickname → sistema genera/recupera userId → guarda localmente → entra a la pizarra. Sin autenticación real.
- **UC2 — Ver pizarra:** al entrar, el sistema envía el snapshot completo del canvas y lo renderiza. Incluye (`«include»`) UC3.
- **UC3 — Recibir actualizaciones en tiempo real:** (disparado automáticamente) escucha el WebSocket y repinta pixeles conforme otros usuarios pintan.
- **UC4 — Elegir color de la paleta:** selecciona un color de la paleta fija antes de pintar. Precondición de UC5.
- **UC5 — Pintar pixel:** toca una celda del grid → se envía intento de pintado. Incluye (`«include»`) UC6. Precondición: tener al menos 1 pixel disponible.
- **UC6 — Validar pixeles disponibles:** (backend, fuente de verdad) revisa `pixelsRemaining` y `cooldownEndsAt` del usuario antes de aceptar el pintado.
- **UC7 — Ver contador de pixeles y cooldown:** visualiza en la UI cuántos pixeles le quedan y el tiempo restante para la próxima recarga.

---

## 6. Especificación de UI (mockups)

### Screen 1: Login Screen (`login_screen.dart`)

**Layout general:**
- Fondo: gradiente diagonal naranja-rojo (`#FF6B35` → `#D62828` aprox), con overlay de grid tipo pixel (líneas finas semi-transparentes formando cuadrícula, estilo cuaderno cuadriculado).
- Contenido centrado verticalmente, padding lateral generoso.

**Elementos (de arriba hacia abajo):**
1. **Título "PIXEL BOARD"** — texto grande, fuente pixel/monospace tipo retro (ej. `Press Start 2P` de Google Fonts), color crema/blanco (`#FFF3D6`), con borde/sombra negra gruesa (efecto "pixel art outline").
2. **Ícono/mascota** — fantasma/blob pixelado color amarillo-naranja con degradado, estilo sprite 8-bit, centrado, tamaño mediano (~100x100).
3. **Subtítulo "COLABORATIVE CANVAS"** — texto pixel, dos líneas, centrado, mismo estilo de fuente que el título pero más pequeño, color crema.
4. **Input "Username"** — caja rectangular con fondo crema claro (`#FFF3D6`), borde negro grueso (3-4px, sin bordes redondeados), placeholder "Username".
5. **Botón "JOIN BOARD"** — rectángulo rojo/naranja (`#D62828`), borde negro grueso, texto crema en mayúsculas, sombra sólida tipo "offset" (sin blur).
6. **Footer "inspired by r/place"** — texto pequeño, centrado, parte inferior.

**Notas de estilo:**
- Todos los bordes son gruesos y negros (2-4px), sin `borderRadius` (esquinas rectas).
- Sombras sólidas tipo "offset" (`BoxShadow` sin blur, solo `offset`), no sombras difuminadas de Material estándar.
- Fuente pixel en TODO el texto (título, botones, inputs).
- Paleta: crema `#FFF3D6`, naranja `#FF6B35`/`#FF8C42`, rojo `#D62828`, negro puro para bordes.

### Screen 2: Board Screen (`board_screen.dart`)

**Layout general:**
- Fondo: negro puro con overlay sutil de grid (líneas grises muy tenues).
- Estructura en 4 secciones apiladas verticalmente: header, decoración/ambiente, canvas, paleta de colores.

**1. Header (parte superior):**
- Izquierda: avatar circular con iniciales entre corchetes `[JD]` (borde blanco, sin relleno) + nombre de usuario al lado.
- Derecha: label "NEXT RECHARGE:" + contador grande `MM:SS` (fuente pixel, grande, blanco).
- Debajo del avatar: ícono pequeño de "batería de pixeles" (torre de bloques) + texto "PIXELS: 5 / 5".
- Debajo del timer: barra de progreso horizontal estilo pixel, segmentada en bloques (no continua), mostrando cuánto falta para la recarga.
- Línea blanca horizontal separando el header del resto.

**2. Zona decorativa (opcional/estática):**
- Sprite pixelado de nave/UFO amarilla-naranja flotando sobre el canvas — decoración temática fija, no parte de la lógica del grid (se puede omitir en la v1 o dejar como imagen estática).

**3. Canvas / Grid principal:**
- Grid cuadrado de pixeles, cada celda con borde sutil (grid lines grises tenues).
- Pixel seleccionado/hover: borde blanco resaltado en la celda tocada (highlight táctil).
- Grid cuadrado y centrado, con espacio uniforme arriba/abajo.

**4. Selector de paleta de colores (parte inferior, fijo):**
- Franja horizontal con swatches de colores en fila (~40x40 cada uno), borde negro grueso.
- Colores del mockup: gris claro, gris oscuro, amarillo, naranja claro, naranja oscuro, rojo, rojo oscuro, granate.
- El color seleccionado tiene borde blanco resaltado indicando selección activa.
- Todo el contenedor de paleta tiene un borde blanco grueso rodeándolo (como una "caja de herramientas" separada del canvas).
- Scrollable horizontal si hay más colores de los que caben.

**Notas de estilo (aplican a toda la pantalla):**
- Fuente pixel (`Press Start 2P` o similar) para todos los números y labels (timer, contador de pixeles, nombre de usuario).
- Bordes gruesos negros/blancos sin `borderRadius`.
- El grid del canvas se implementa con `CustomPainter` (no widgets individuales por pixel, por performance).
- Colores de acento: blanco para texto/bordes sobre negro, paleta cálida amarillo→rojo para pixeles y elementos seleccionados.

### Componentes reutilizables derivados

- `PixelSwatch` — widget para cada color de la paleta, con estado seleccionado/no seleccionado.
- `RetroCounter` — texto pixel con borde, reutilizable para timer y contador de pixeles.
- `RetroButton` / `RetroTextField` — con el estilo de sombra dura y bordes gruesos.
- `PixelBatteryIcon` — ícono de la "torre de bloques" que indica pixeles disponibles.
