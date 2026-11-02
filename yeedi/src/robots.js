// Solea Yeedi : robots aspirateurs yeedi / Ecovacs du compte, état tenu à jour en direct.
//
// Copyright (C) 2026 FlowIT Connect
// Ce programme est un logiciel libre : GPL version 3 ou ultérieure (voir LICENSE).

/** Puissances d'aspiration Solea → niveaux de la bibliothèque (1 silencieux … 4 maximum). */
export const SUCTION_LEVELS = { quiet: 1, standard: 2, strong: 3, max: 4 };
const SUCTION_NAMES = Object.fromEntries(Object.entries(SUCTION_LEVELS).map(([k, v]) => [v, k]));

export const ACTIONS = ['start', 'pause', 'resume', 'stop', 'charge'];

const CLEANING = new Set(['auto', 'spot', 'spot_area', 'custom_area', 'edge', 'area', 'singlePoint', 'move', 'comeClean']);

/** Codes « pas d'erreur » des robots Ecovacs. */
const NO_ERROR = new Set([undefined, null, '', '0', '100', 0, 100]);

/**
 * Codes de liaison (coupure réseau, délai, « Robot not reachable ») : ce n'est pas une
 * panne du robot, et la bibliothèque les garde jusqu'à la commande réussie suivante.
 */
export const LINK_ERRORS = new Set(['-1', '500', '4200']);
const isError = (code) => !NO_ERROR.has(code) && !LINK_ERRORS.has(String(code));

/** Interrogations qui rafraîchissent tout l'état du robot. */
const REFRESH = ['GetBatteryState', 'GetCleanState', 'GetChargeState', 'GetCleanSpeed'];

/**
 * État Solea à partir des derniers messages du robot.
 * status : cleaning | paused | returning | charging | idle | error
 */
export function robotStatus({ cleanReport, chargeStatus, errorCode }) {
  if (isError(errorCode)) return 'error';
  if (cleanReport === 'returning' || chargeStatus === 'returning') return 'returning';
  if (CLEANING.has(cleanReport)) return 'cleaning';
  if (cleanReport === 'pause') return 'paused';
  if (chargeStatus === 'charging') return 'charging';
  return 'idle';
}

/** Une action est-elle visible dans l'état du robot ? (confirmation après un vrai changement) */
export function actionReached(action, status) {
  switch (action) {
    case 'start':
    case 'resume':
      return status === 'cleaning';
    case 'pause':
      return status === 'paused';
    case 'charge':
      return status === 'returning' || status === 'charging';
    case 'stop':
      return status !== 'cleaning' && status !== 'returning';
    default:
      return false;
  }
}

/**
 * @typedef {{did:string,name:string,model:string,bot:any}} Robot
 * @typedef {{login:()=>Promise<void>, robots:()=>Promise<Array<{did:string,name:string,model:string,bot:any}>>}} Cloud
 */
export class RobotHub {
  /**
   * @param {Cloud} cloud connexion au cloud yeedi (voir cloud.js), remplaçable dans les tests
   */
  constructor(cloud, { log = () => {}, refreshMs = 60_000 } = {}) {
    this.cloud = cloud;
    this.log = log;
    this.refreshMs = refreshMs;
    this.timer = null;
    /** @type {Map<string, {robot:Robot, online:boolean, raw:object, waiters:Set<Function>}>} */
    this.robots = new Map();
  }

  async start() {
    await this.cloud.login();
    for (const robot of await this.cloud.robots()) this.#attach(robot);
    this.log('yeedi.robots', { count: this.robots.size });
    // Interrogation régulière : l'état reste juste même si un message du robot s'est perdu,
    // et une erreur de liaison passagère s'efface toute seule.
    this.timer = setInterval(() => this.refresh(), this.refreshMs);
    this.timer.unref?.();
  }

  refresh() {
    for (const e of this.robots.values()) {
      if (!e.online) continue;
      for (const cmd of REFRESH) {
        try {
          e.robot.bot.run(cmd);
        } catch (err) {
          this.log('yeedi.refresh_failed', { robot: e.robot.name, error: err.message });
        }
      }
    }
  }

  async stop() {
    clearInterval(this.timer);
    for (const r of this.robots.values()) {
      try {
        await r.robot.bot.disconnectAsync?.();
      } catch {
        // déjà déconnecté
      }
    }
  }

  #attach(robot) {
    const entry = { robot, online: false, raw: {}, waiters: new Set() };
    this.robots.set(robot.did, entry);
    const bot = robot.bot;
    const update = (patch) => {
      Object.assign(entry.raw, patch);
      for (const w of entry.waiters) w();
    };
    // Une nouvelle réponse du robot prouve que la liaison est revenue.
    const fresh = (patch) => update(LINK_ERRORS.has(String(entry.raw.errorCode)) ? { ...patch, errorCode: '0', errorText: null } : patch);
    bot.on('ready', () => {
      entry.online = true;
      this.log('yeedi.ready', { robot: robot.name });
      for (const cmd of REFRESH) bot.run(cmd);
      update({});
    });
    bot.on('BatteryInfo', (v) => fresh({ battery: Math.round(Number(v)) }));
    bot.on('CleanReport', (v) => fresh({ cleanReport: v }));
    bot.on('ChargeState', (v) => fresh({ chargeStatus: v }));
    bot.on('CleanSpeed', (v) => fresh({ cleanSpeed: Number(v) }));
    bot.on('ErrorCode', (v) => update({ errorCode: String(v) }));
    bot.on('Error', (v) => update({ errorText: v }));
    bot.on('disconnect', () => {
      entry.online = false;
      update({});
    });
    bot.connect();
  }

  /** Robots tels que la passerelle Solea les lit. */
  list() {
    return [...this.robots.values()].map((e) => this.#view(e));
  }

  #view({ robot, online, raw }) {
    const status = robotStatus(raw);
    return {
      id: robot.did,
      name: robot.name,
      model: robot.model,
      online,
      state: {
        status,
        battery: Number.isFinite(raw.battery) ? raw.battery : null,
        suction: SUCTION_NAMES[raw.cleanSpeed] ?? null,
        error: status === 'error' ? raw.errorText || `Erreur ${raw.errorCode}` : null,
      },
    };
  }

  /**
   * Envoie une commande et attend que le robot la confirme dans son état.
   * @returns {Promise<{status:'confirmed'|'timeout'|'failed', error?:string, robot?:object}>}
   */
  async command(did, { action, suction }, timeoutMs = 15_000) {
    const entry = this.robots.get(did);
    if (!entry) return { status: 'failed', error: 'Robot inconnu' };
    if (!entry.online) return { status: 'failed', error: 'Robot hors ligne' };
    const bot = entry.robot.bot;
    let reached;
    if (suction !== undefined) {
      const level = SUCTION_LEVELS[suction];
      if (!level) return { status: 'failed', error: 'Puissance inconnue' };
      bot.run('SetCleanSpeed', level);
      setTimeout(() => bot.run('GetCleanSpeed'), 1_500).unref?.();
      reached = () => entry.raw.cleanSpeed === level;
    } else {
      if (!ACTIONS.includes(action)) return { status: 'failed', error: 'Action inconnue' };
      const run = { start: 'Clean', pause: 'Pause', resume: 'Resume', stop: 'Stop', charge: 'Charge' }[action];
      bot.run(run);
      setTimeout(() => {
        bot.run('GetCleanState');
        bot.run('GetChargeState');
      }, 2_000).unref?.();
      reached = () => actionReached(action, robotStatus(entry.raw));
    }
    const ok = await this.#waitFor(entry, reached, timeoutMs);
    return ok ? { status: 'confirmed', robot: this.#view(entry) } : { status: 'timeout', error: 'Le robot n\'a pas confirmé' };
  }

  #waitFor(entry, test, timeoutMs) {
    if (test()) return Promise.resolve(true);
    return new Promise((resolve) => {
      const done = (v) => {
        clearTimeout(timer);
        entry.waiters.delete(check);
        resolve(v);
      };
      const check = () => test() && done(true);
      const timer = setTimeout(() => done(false), timeoutMs);
      entry.waiters.add(check);
    });
  }
}
