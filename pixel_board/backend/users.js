const PIXELS_PER_CYCLE = Number.parseInt(process.env.PIXELS_PER_CYCLE || '5', 10);
const COOLDOWN_MS = Number.parseInt(process.env.COOLDOWN_MS || String(2 * 60 * 1000), 10);

/**
 * Cooldown por usuario (5 pixeles / 2 min). Fuente de verdad:
 * ningún paint se acepta sin validar pixelsRemaining y cooldownEndsAt.
 *
 * Identidad: los registros se keyean por nickname (único). El token es la
 * credencial que permite al dueño volver a entrar con su mismo nombre.
 * onPersist se invoca en cada cambio para respaldar en SQLite.
 */
class Users {
  constructor({ onPersist } = {}) {
    this.records = new Map();
    this.onPersist = onPersist;
  }

  _persist(user) {
    this.onPersist?.(user);
  }

  _refreshIfExpired(user) {
    if (user.cooldownEndsAt !== null && Date.now() >= user.cooldownEndsAt) {
      user.pixelsRemaining = PIXELS_PER_CYCLE;
      user.cooldownEndsAt = null;
      this._persist(user);
    }
  }

  find(nickname) {
    return this.records.get(nickname) ?? null;
  }

  getOrCreate(nickname, token) {
    let user = this.records.get(nickname);
    if (!user) {
      user = {
        nickname,
        token,
        pixelsRemaining: PIXELS_PER_CYCLE,
        cooldownEndsAt: null,
      };
      this.records.set(nickname, user);
      this._persist(user);
    }
    return user;
  }

  getState(nickname) {
    const user = this.getOrCreate(nickname, this.find(nickname)?.token ?? '');
    this._refreshIfExpired(user);
    return {
      pixelsRemaining: user.pixelsRemaining,
      cooldownEndsAt: user.cooldownEndsAt,
    };
  }

  /**
   * Intenta consumir un pixel. Devuelve { ok, pixelsRemaining, cooldownEndsAt }.
   * ok=false cuando el usuario está en cooldown (el estado devuelto es el real).
   */
  tryConsume(nickname) {
    const user = this.records.get(nickname);
    if (!user) {
      // Sin registro previo no hay sesión válida: el hello debió crearla.
      return { ok: false, pixelsRemaining: 0, cooldownEndsAt: null };
    }
    this._refreshIfExpired(user);

    if (user.cooldownEndsAt !== null) {
      return {
        ok: false,
        pixelsRemaining: user.pixelsRemaining,
        cooldownEndsAt: user.cooldownEndsAt,
      };
    }

    if (user.pixelsRemaining <= 0) {
      user.cooldownEndsAt = Date.now() + COOLDOWN_MS;
      this._persist(user);
      return {
        ok: false,
        pixelsRemaining: 0,
        cooldownEndsAt: user.cooldownEndsAt,
      };
    }

    user.pixelsRemaining -= 1;
    if (user.pixelsRemaining === 0) {
      user.cooldownEndsAt = Date.now() + COOLDOWN_MS;
    }
    this._persist(user);
    return {
      ok: true,
      pixelsRemaining: user.pixelsRemaining,
      cooldownEndsAt: user.cooldownEndsAt,
    };
  }
}

export { Users, PIXELS_PER_CYCLE, COOLDOWN_MS };