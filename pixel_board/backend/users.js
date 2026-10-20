import { randomBytes } from 'node:crypto';

/**
 * Gestión de usuarios: identidad por nickname únicamente.
 * No hay contraseña. El token es credencial de sesión.
 */

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

  getOrCreate(nickname) {
    let user = this.records.get(nickname);
    if (!user) {
      const token = randomBytes(16).toString('hex');
      user = {
        nickname,
        token,
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
      const lUser = this.records.get(loser);
      if (lUser) { lUser.draws++; this._persist(lUser); }
      return;
    }
    const wUser = this.records.get(winner);
    const lUser = this.records.get(loser);
    if (wUser) { wUser.wins++; this._persist(wUser); }
    if (lUser) { lUser.losses++; this._persist(lUser); }
  }
}

export { Users };
