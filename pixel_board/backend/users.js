import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';

/**
 * Gestión de usuarios: autenticación + estadísticas de juego.
 * Identidad: el nickname es la clave única. Token = credencial de sesión.
 */

function hashPassword(password) {
  const salt = randomBytes(16).toString('hex');
  const hash = scryptSync(password, salt, 64).toString('hex');
  return `${salt}:${hash}`;
}

function verifyPassword(password, stored) {
  if (!stored) return false;
  const [salt, hash] = stored.split(':');
  const testHash = scryptSync(password, salt, 64).toString('hex');
  return timingSafeEqual(Buffer.from(hash, 'hex'), Buffer.from(testHash, 'hex'));
}

function isStrongPassword(p) {
  if (typeof p !== 'string' || p.length < 8 || p.length > 64) return false;
  if (!/[A-Z]/.test(p)) return false;
  if (!/[a-z]/.test(p)) return false;
  if (!/[0-9]/.test(p)) return false;
  if (!/[!@#$%^&*()_\-]/.test(p)) return false;
  return true;
}

class Users {
  constructor({ onPersist } = {}) {
    this.records = new Map();
    this.onPersist = onPersist;
  }

  _persist(user) {
    this.onPersist?.(user);
  }

  find(nickname) {
    return this.records.get(nickname) ?? null;
  }

  register(nickname, password) {
    const existing = this.records.get(nickname);
    if (existing) return { ok: false, error: 'taken' };
    if (!password || !isStrongPassword(password)) {
      return { ok: false, error: 'weak_password' };
    }
    const token = randomBytes(16).toString('hex');
    const passwordHash = hashPassword(password);
    const user = {
      nickname,
      token,
      passwordHash,
      wins: 0,
      losses: 0,
      draws: 0,
    };
    this.records.set(nickname, user);
    this._persist(user);
    return { ok: true, token };
  }

  login(nickname, password) {
    const user = this.records.get(nickname);
    if (!user) return { ok: false, error: 'not_found' };
    if (!user.passwordHash) return { ok: false, error: 'no_password' };
    if (!verifyPassword(password, user.passwordHash)) {
      return { ok: false, error: 'wrong_password' };
    }
    return { ok: true, token: user.token };
  }

  getOrCreate(nickname, token) {
    let user = this.records.get(nickname);
    if (!user) {
      user = {
        nickname,
        token,
        passwordHash: null,
        wins: 0,
        losses: 0,
        draws: 0,
      };
      this.records.set(nickname, user);
      this._persist(user);
    }
    return user;
  }

  getStats(nickname) {
    const user = this.records.get(nickname);
    if (!user) return { wins: 0, losses: 0, draws: 0 };
    return { wins: user.wins, losses: user.losses, draws: user.draws };
  }

  recordGame(winner, loser) {
    if (winner === 'tie') {
      const wUser = this.records.get(loser);
      if (wUser) { wUser.draws++; this._persist(wUser); }
      return;
    }
    const wUser = this.records.get(winner);
    const lUser = this.records.get(loser);
    if (wUser) { wUser.wins++; this._persist(wUser); }
    if (lUser) { lUser.losses++; this._persist(lUser); }
  }
}

export { Users };
