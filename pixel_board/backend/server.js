import { WebSocketServer } from 'ws';
import { Users } from './users.js';
import { Db } from './db.js';
import { Matcher } from './matcher.js';
import { Room, Phase, PREVIEW_SECONDS, DRAW_SECONDS } from './room.js';

const PORT = process.env.PORT || 3000;
const NICKNAME_MAX = 16;
const NICKNAME_RE = /^[a-zA-Z0-9_\- ]+$/;
const CHAT_TEXT_MAX = 200;
const CHAT_MIN_INTERVAL_MS = 500;
const HEARTBEAT_MS = 10_000;

// ── Estado global ────────────────────────────────────────────────────

const db = new Db();
const rooms = new Map();       // roomId → Room
const wsToRoom = new Map();    // ws → roomId
const wsToNickname = new Map(); // ws → nickname

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

function sendToRoom(roomId, message, exclude) {
  for (const [ws, rid] of wsToRoom) {
    if (rid === roomId && ws !== exclude) {
      send(ws, message);
    }
  }
}

function getRoomForWs(ws) {
  const roomId = wsToRoom.get(ws);
  return roomId ? rooms.get(roomId) : null;
}

function getWsByNickname(nickname) {
  for (const [ws, nick] of wsToNickname) {
    if (nick === nickname) return ws;
  }
  return null;
}

function normalizeNickname(raw) {
  if (typeof raw !== 'string') return null;
  const nickname = raw.trim();
  if (!nickname || nickname.length > NICKNAME_MAX) return null;
  if (!NICKNAME_RE.test(nickname)) return null;
  return nickname;
}

// ── Usuarios ─────────────────────────────────────────────────────────

const users = new Users({
  onPersist: (user) => {
    try { db.saveUser(user); } catch (err) {
      console.error('No se pudo persistir el usuario:', err);
    }
  },
});
for (const user of db.loadUsers()) {
  users.records.set(user.nickname, user);
}

// ── Matchmaking ──────────────────────────────────────────────────────

const matcher = new Matcher((room, p1, p2) => {
  // Verificar que ambos sockets sigan abiertos antes de crear la sala
  const ws1 = getWsByNickname(p1.nickname);
  const ws2 = getWsByNickname(p2.nickname);

  const ws1Open = ws1 && ws1.readyState === ws1.OPEN;
  const ws2Open = ws2 && ws2.readyState === ws2.OPEN;

  if (!ws1Open && !ws2Open) {
    // Ambos desconectaron, descartar sala
    console.log(`Sala ${room.id} descartada: ambos sockets cerrados`);
    return;
  }

  if (!ws1Open) {
    // p1 se desconectó: p2 gana por forfeit
    if (ws2) {
      send(ws2, {
        type: 'game_results',
        roomId: room.id,
        winner: p2.nickname,
        player1: p2.nickname,
        player2: p1.nickname,
        player1Score: 100,
        player2Score: 0,
        reference: [],
        player1Canvas: [],
        player2Canvas: [],
        forfeit: true,
      });
      const stats = users.getStats(p2.nickname);
      send(ws2, { type: 'stats_update', ...stats });
    }
    db.updateStats(p2.nickname, p1.nickname);
    users.recordGame(p2.nickname, p1.nickname);
    return;
  }

  if (!ws2Open) {
    // p2 se desconectó: p1 gana por forfeit
    send(ws1, {
      type: 'game_results',
      roomId: room.id,
      winner: p1.nickname,
      player1: p1.nickname,
      player2: p2.nickname,
      player1Score: 100,
      player2Score: 0,
      reference: [],
      player1Canvas: [],
      player2Canvas: [],
      forfeit: true,
    });
    const stats = users.getStats(p1.nickname);
    send(ws1, { type: 'stats_update', ...stats });
    db.updateStats(p1.nickname, p2.nickname);
    users.recordGame(p1.nickname, p2.nickname);
    return;
  }

  // Ambos sockets abiertos: crear sala normalmente
  rooms.set(room.id, room);
  wsToRoom.set(ws1, room.id);
  wsToRoom.set(ws2, room.id);

  // Iniciar juego: ambos ven la imagen de referencia
  const startMsg = room.startGame();
  // Enviar a p1: yo soy player1, oponente es p2
  send(ws1, { ...startMsg, opponent: p2.nickname });
  // Enviar a p2: yo soy player2, oponente es p1
  send(ws2, {
    ...startMsg,
    opponent: p1.nickname,
    player1: p2.nickname,
    player2: p1.nickname,
  });

  // Timer: después de PREVIEW_SECONDS, ambos jugadores dibujan al mismo tiempo
  room.turnTimer = setTimeout(() => {
    const msg = room.advanceFromPreview();
    if (ws1.readyState === ws1.OPEN) send(ws1, msg);
    if (ws2.readyState === ws2.OPEN) send(ws2, msg);
    startDrawTimer(room);
  }, PREVIEW_SECONDS * 1000);
});

function startDrawTimer(room) {
  if (room.turnTimer) clearTimeout(room.turnTimer);
  const durationMs = DRAW_SECONDS * 1000;
  room.turnTimer = setTimeout(() => {
    if (room.phase === Phase.DRAWING) {
      finishRoom(room);
    }
  }, durationMs);
}

// ── Limpieza periódica de colas stale ──────────────────────────────
const MATCHMAKING_CLEANUP_MS = 3_000;
setInterval(() => {
  const before = matcher.queue.length;
  matcher._purgeStale();
  if (matcher.queue.length !== before) {
    console.log(`Limpieza de cola: ${before} → ${matcher.queue.length}`);
  }
}, MATCHMAKING_CLEANUP_MS);

function finishRoom(room) {
  const results = room.finishGame();

  // Enviar resultados a ambos jugadores
  for (const nickname of room.players) {
    const ws = getWsByNickname(nickname);
    if (ws) {
      const opponentNickname = nickname === room.players[0] ? room.players[1] : room.players[0];
      send(ws, {
        ...results,
        opponent: opponentNickname,
      });
    }
  }

  // Persistir resultado
  try {
    db.saveGame({
      roomId: room.id,
      player1: room.players[0],
      player2: room.players[1],
      referenceImage: room.reference.grid,
      player1Canvas: room.player1Canvas,
      player2Canvas: room.player2Canvas,
      player1Score: room.player1Score,
      player2Score: room.player2Score,
      winner: room.winner,
    });
    db.updateStats(room.winner, room.winner === room.players[0] ? room.players[1] : room.players[0]);
    users.recordGame(room.winner, room.winner === room.players[0] ? room.players[1] : room.players[0]);
  } catch (err) {
    console.error('No se pudo guardar el resultado:', err);
  }

  // Enviar stats actualizadas
  for (const nickname of room.players) {
    const ws = getWsByNickname(nickname);
    if (ws) {
      const stats = users.getStats(nickname);
      send(ws, { type: 'stats_update', ...stats });
    }
  }

  // Limpiar sala
  cleanupRoom(room);
}

function cleanupRoom(room) {
  if (room.turnTimer) clearTimeout(room.turnTimer);
  for (const nickname of room.players) {
    const ws = getWsByNickname(nickname);
    if (ws) wsToRoom.delete(ws);
  }
  rooms.delete(room.id);
}

function handleDisconnect(ws) {
  const nickname = wsToNickname.get(ws);
  const roomId = wsToRoom.get(ws);

  if (roomId && nickname) {
    const room = rooms.get(roomId);
    if (room) {
      const result = room.removePlayer(nickname);
      if (result === 'forfeit' && room.players.length === 1) {
        // El otro jugador gana por forfeit
        const winner = room.players[0];
        const wsWinner = getWsByNickname(winner);
        if (wsWinner) {
          send(wsWinner, {
            type: 'game_results',
            roomId: room.id,
            winner,
            player1: room.players[0],
            player2: nickname,
            player1Score: 100,
            player2Score: 0,
            reference: [],
            player1Canvas: [],
            player2Canvas: [],
            forfeit: true,
          });
          const stats = users.getStats(winner);
          send(wsWinner, { type: 'stats_update', ...stats });
        }
        db.updateStats(winner, nickname);
        users.recordGame(winner, nickname);
        cleanupRoom(room);
      } else if (result === 'empty') {
        cleanupRoom(room);
      }
    }
  }

  // Verificar si hay otro socket activo para el mismo nickname
  let hasOtherSocket = false;
  if (nickname) {
    for (const [otherWs, otherNick] of wsToNickname) {
      if (otherNick === nickname && otherWs !== ws) {
        hasOtherSocket = true;
        break;
      }
    }
  }

  // Solo eliminar del matcher si NO hay otro socket activo
  // (el otro socket reconectará y reenviará start_matchmaking)
  if (!hasOtherSocket) {
    matcher.remove(nickname);
  }

  wsToRoom.delete(ws);
  wsToNickname.delete(ws);

  // Si hay otra conexión activa para el mismo nickname,
  // re-encolarla automáticamente.
  if (nickname && hasOtherSocket) {
    for (const [otherWs, otherNick] of wsToNickname) {
      if (otherNick === nickname) {
        matcher.enqueue(nickname, otherWs);
        break;
      }
    }
  }
}

// ── WebSocket Server ─────────────────────────────────────────────────

const wss = new WebSocketServer({ port: PORT }, () => {
  console.log(`Pixel Board backend escuchando en el puerto ${PORT} (db: ${db.path})`);
});

wss.on('connection', (ws) => {
  ws.lastChatAt = 0;
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  ws.on('message', (raw) => {
    let message;
    try { message = JSON.parse(raw.toString()); } catch { return; }

    // ── Autenticación ─────────────────────────────────────────────
    if (message.type === 'hello') {
      const nickname = normalizeNickname(message.nickname);
      if (!nickname) return;

      const token = typeof message.token === 'string' ? message.token.slice(0, 64) : null;
      const existing = users.find(nickname);

      if (existing) {
        // Reconexión con token válido → bienvenido de vuelta
        if (token && existing.token === token) {
          wsToNickname.set(ws, nickname);
          const stats = users.getStats(nickname);
          send(ws, { type: 'auth_ok', token, ...stats });
          return;
        }
        // Sin token o token inválido → nombre ya en uso
        send(ws, { type: 'nickname_taken', nickname });
        return;
      }

      // Nuevo usuario
      const user = users.getOrCreate(nickname);
      wsToNickname.set(ws, nickname);
      send(ws, { type: 'auth_ok', token: user.token, ...users.getStats(nickname) });
      return;
    }

    // ── Todo lo demás requiere autenticación ──────────────────────
    const nickname = wsToNickname.get(ws);
    if (!nickname) return;

    // ── Pintar pixel ──────────────────────────────────────────────
    if (message.type === 'paint') {
      const room = getRoomForWs(ws);
      if (!room) return;

      const { x, y, color } = message;
      if (
        !Number.isInteger(x) || !Number.isInteger(y) ||
        typeof color !== 'string' || color.length !== 7
      ) return;

      if (room.paintPixel(nickname, x, y, color)) {
        // Notificar al otro jugador que se pintó un pixel
        const opponentNickname = nickname === room.players[0] ? room.players[1] : room.players[0];
        const wsOpponent = getWsByNickname(opponentNickname);
        if (wsOpponent) {
          send(wsOpponent, { type: 'pixel_update', x, y, color });
        }
      }
      return;
    }

    // ── Terminar turno manualmente ─────────────────────────────────
    if (message.type === 'finish_turn') {
      const room = getRoomForWs(ws);
      if (!room || !room.isActivePlayer(nickname)) return;

      const result = room.finishPlayer(nickname);

      // Notificar al oponente que este jugador terminó
      const opponentNickname = nickname === room.players[0] ? room.players[1] : room.players[0];
      const wsOpponent = getWsByNickname(opponentNickname);
      if (wsOpponent) {
        send(wsOpponent, { type: 'player_finished', nickname });
      }

      if (result === 'both') {
        // Ambos terminaron: finalizar la partida inmediatamente
        finishRoom(room);
      }
      return;
    }

    // ── Chat (solo dentro de una sala) ────────────────────────────
    if (message.type === 'chat') {
      const room = getRoomForWs(ws);
      if (!room) return;
      if (typeof message.text !== 'string') return;
      const text = message.text.trim();
      if (!text || text.length > CHAT_TEXT_MAX) return;

      const now = Date.now();
      if (ws.lastChatAt && now - ws.lastChatAt < CHAT_MIN_INTERVAL_MS) return;
      ws.lastChatAt = now;

      try { db.saveMessage(room.id, nickname, text, now); } catch {}

      sendToRoom(room.id, {
        type: 'chat_update',
        nickname,
        text,
        createdAt: now,
      });
      return;
    }

    // ── Iniciar matchmaking ────────────────────────────────────────
    if (message.type === 'start_matchmaking') {
      const room = getRoomForWs(ws);
      if (room && room.phase !== Phase.RESULTS) return;

      const matched = matcher.enqueue(nickname, ws);
      if (!matched) {
        send(ws, { type: 'matchmaking_status', status: 'waiting' });
      }
      return;
    }

    // ── Solicitar siguiente partida ───────────────────────────────
    if (message.type === 'next_game') {
      const room = getRoomForWs(ws);
      if (room) {
        if (room.phase === Phase.RESULTS) {
          cleanupRoom(room);
        } else {
          return; // Ya está en una partida activa
        }
      }
      const matched = matcher.enqueue(nickname, ws);
      if (!matched) {
        send(ws, { type: 'matchmaking_status', status: 'waiting' });
      }
      return;
    }
  });

  ws.on('close', () => handleDisconnect(ws));
});

// ── Heartbeat ────────────────────────────────────────────────────────

const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, HEARTBEAT_MS);

function shutdown() {
  clearInterval(heartbeat);
  for (const ws of wss.clients) ws.terminate();
  wss.close(() => { db.close(); process.exit(0); });
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
