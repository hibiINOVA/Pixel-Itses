import { randomBytes } from 'node:crypto';
import { WebSocketServer } from 'ws';
import { Canvas, CANVAS_SIZE } from './canvas.js';
import { Users } from './users.js';
import { Db } from './db.js';

const PORT = process.env.PORT || 3000;
const NICKNAME_MAX = 16;
const HEARTBEAT_MS = 30_000;
const NICKNAME_RE = /^[a-zA-Z0-9_\- ]+$/;
const CHAT_HISTORY_LIMIT = 50;
const CHAT_TEXT_MAX = 200;
const CHAT_MIN_INTERVAL_MS = 500;

const db = new Db();
db.seedPixels(CANVAS_SIZE);

const savedGrid = db.loadPixels(CANVAS_SIZE);
const canvas = new Canvas(CANVAS_SIZE, savedGrid);

const users = new Users({
  onPersist: (user) => {
    try {
      db.saveUser(user);
    } catch (err) {
      console.error('No se pudo persistir el usuario:', err);
    }
  },
});
for (const user of db.loadUsers()) {
  users.records.set(user.nickname, user);
}

const wss = new WebSocketServer({ port: PORT }, () => {
  console.log(`Pixel Board backend escuchando en el puerto ${PORT} (db: ${db.path})`);
});

function send(ws, message) {
  if (ws.readyState === ws.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

function broadcast(message) {
  for (const client of wss.clients) {
    send(client, message);
  }
}

function normalizeNickname(raw) {
  if (typeof raw !== 'string') return null;
  const nickname = raw.trim();
  if (!nickname || nickname.length > NICKNAME_MAX) return null;
  if (!NICKNAME_RE.test(nickname)) return null;
  return nickname;
}

wss.on('connection', (ws) => {
  ws.nickname = null;
  ws.lastChatAt = 0;
  ws.isAlive = true;
  ws.on('pong', () => {
    ws.isAlive = true;
  });

  ws.on('message', (raw) => {
    let message;
    try {
      message = JSON.parse(raw.toString());
    } catch {
      return;
    }

    if (message.type === 'hello') {
      const nickname = normalizeNickname(message.nickname);
      if (!nickname) return;

      const token =
        typeof message.token === 'string' ? message.token.slice(0, 64) : null;
      const existing = users.find(nickname);

      if (!existing) {
        // Registro nuevo: nombre libre → se crea con token secreto.
        const newToken = randomBytes(16).toString('hex');
        const state = users.getOrCreate(nickname, newToken);
        ws.nickname = nickname;
        send(ws, {
          type: 'canvas_snapshot',
          canvas: canvas.getSnapshot(),
          pixelsRemaining: state.pixelsRemaining,
          cooldownEndsAt: state.cooldownEndsAt,
          token: newToken,
        });
        send(ws, { type: 'chat_history', messages: db.loadMessages(CHAT_HISTORY_LIMIT) });
        return;
      }

      if (token && token === existing.token) {
        // El dueño vuelve a entrar: resume su cuenta silenciosamente.
        ws.nickname = nickname;
        const state = users.getState(nickname);
        send(ws, {
          type: 'canvas_snapshot',
          canvas: canvas.getSnapshot(),
          pixelsRemaining: state.pixelsRemaining,
          cooldownEndsAt: state.cooldownEndsAt,
          token,
        });
        send(ws, { type: 'chat_history', messages: db.loadMessages(CHAT_HISTORY_LIMIT) });
        return;
      }

      // Nombre registrado y sin credencial válida: rechazo.
      send(ws, { type: 'nickname_taken', nickname });
      return;
    }

    if (message.type === 'chat') {
      if (!ws.nickname) return;
      if (typeof message.text !== 'string') return;
      const text = message.text.trim();
      if (!text || text.length > CHAT_TEXT_MAX) return;

      // Anti-spam barato: mínimo entre mensajes por conexión.
      const now = Date.now();
      if (ws.lastChatAt && now - ws.lastChatAt < CHAT_MIN_INTERVAL_MS) return;
      ws.lastChatAt = now;

      try {
        db.saveMessage(ws.nickname, text, now);
      } catch (err) {
        console.error('No se pudo guardar el mensaje:', err);
      }
      broadcast({ type: 'chat_update', nickname: ws.nickname, text, createdAt: now });
      return;
    }

    if (message.type !== 'paint' || !ws.nickname) return;

    // Validación estricta: sin coerción de tipos (evita claves raras en el grid).
    const { x, y, color } = message;
    if (
      !Number.isInteger(x) ||
      !Number.isInteger(y) ||
      typeof color !== 'string' ||
      !canvas.isValid(x, y, color)
    ) {
      console.warn('paint rechazado (coordenadas o color inválidos):', { x, y, color });
      return;
    }

    const result = users.tryConsume(ws.nickname);

    if (!result.ok) {
      send(ws, {
        type: 'cooldown_update',
        pixelsRemaining: result.pixelsRemaining,
        cooldownEndsAt: result.cooldownEndsAt,
      });
      return;
    }

    canvas.paintPixel(x, y, color);
    try {
      db.savePixel(x, y, color, ws.nickname);
    } catch (err) {
      console.error('No se pudo guardar el pixel:', err);
    }

    broadcast({ type: 'pixel_update', x, y, color });

    send(ws, {
      type: 'cooldown_update',
      pixelsRemaining: result.pixelsRemaining,
      cooldownEndsAt: result.cooldownEndsAt,
    });
  });

  ws.on('close', () => {
    console.log('Cliente desconectado');
  });
});

// Heartbeat: corta conexiones muertas que no responden pong.
const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, HEARTBEAT_MS);

function shutdown() {
  clearInterval(heartbeat);
  for (const ws of wss.clients) {
    ws.terminate();
  }
  wss.close(() => {
    db.close();
    process.exit(0);
  });
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);