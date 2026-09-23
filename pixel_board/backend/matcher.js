/**
 * Cola de matchmaking: empareja jugadores de dos en dos.
 * Cuando hay ≥2 jugadores en la cola, crea una sala y notifica a ambos.
 * Valida que ambos sockets estén abiertos y activos antes de emparejar.
 */

import { Room } from './room.js';

let roomCounter = 0;
const STALE_TIMEOUT_MS = 30_000;

class Matcher {
  constructor(onMatch) {
    this.queue = [];
    this.onMatch = onMatch;
  }

  enqueue(nickname, ws) {
    // Si ya está en la cola, limpiar la entrada anterior si es stale
    const existingIdx = this.queue.findIndex((e) => e.nickname === nickname);
    if (existingIdx !== -1) {
      const existing = this.queue[existingIdx];
      if (this._isStale(existing)) {
        this.queue.splice(existingIdx, 1);
      } else {
        // Actualizar socket y timestamp
        this.queue[existingIdx].ws = ws;
        this.queue[existingIdx].enqueuedAt = Date.now();
        return null;
      }
    }

    // Limpiar entradas stale antes de agregar
    this._purgeStale();

    this.queue.push({ nickname, ws, enqueuedAt: Date.now() });

    if (this.queue.length >= 2) {
      const p1 = this.queue.shift();
      const p2 = this.queue.shift();

      // Verificar que ambos sockets estén abiertos y no stale
      if (this._isStale(p1)) {
        this.queue.unshift(p2);
        return null;
      }
      if (this._isStale(p2)) {
        this.queue.unshift(p1);
        return null;
      }

      const roomId = `room_${++roomCounter}`;
      const room = new Room(roomId, p1.nickname, p2.nickname);
      this.onMatch(room, p1, p2);
      return room;
    }

    return null;
  }

  remove(nickname) {
    this.queue = this.queue.filter((e) => e.nickname !== nickname);
  }

  has(nickname) {
    return this.queue.some((e) => e.nickname === nickname);
  }

  size() {
    return this.queue.length;
  }

  /** Verifica si una entrada es stale: socket cerrado o en la cola demasiado tiempo. */
  _isStale(entry) {
    if (!entry.ws || entry.ws.readyState !== 1) return true;
    if (entry.ws.isAlive === false) return true;
    if (Date.now() - entry.enqueuedAt > STALE_TIMEOUT_MS) return true;
    return false;
  }

  /** Elimina todas las entradas stale de la cola. */
  _purgeStale() {
    this.queue = this.queue.filter((e) => !this._isStale(e));
  }
}

export { Matcher };
