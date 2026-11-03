import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { test } from 'node:test';

import { actionReached, parseBoundary, RobotHub, roomFromInfo, robotStatus } from '../src/robots.js';
import { yeediServer } from '../src/server.js';
import { readForm, setEnvLines } from '../src/setup.js';

/** Cartes et pièces telles que la bibliothèque les annonce (événements Maps, MapSpotAreas, MapSpotAreaInfo). */
const MAPS = { maps: [{ mapID: '9', mapIsCurrentMap: false }, { mapID: '1', mapIsCurrentMap: true }] };
const AREAS = {
  '0': { mapSpotAreaName: 'Living room', mapSpotAreaBoundaries: '-2000,-1500;2000.4,-1500;2000,1500;-2000,1500' },
  '1': { mapSpotAreaName: 'Cuisine', mapSpotAreaBoundaries: '2000,-1500;4000,-1500;4000,1500;2000,1500' },
};

/** Robot simulé : répond aux commandes comme le cloud yeedi (messages d'état après coup). */
class FakeBot extends EventEmitter {
  vacBotCommand = { GetMapInfo_V2: class { name = 'getMapInfo_V2'; } };

  constructor() {
    super();
    this.sent = [];
    this.deaf = false;
  }
  connect() {
    setImmediate(() => this.emit('ready'));
  }
  run(cmd, ...args) {
    this.sent.push([cmd, ...args]);
    if (this.deaf) return;
    const later = (ev, v) => setTimeout(() => this.emit(ev, v), 5);
    if (cmd === 'GetBatteryState') later('BatteryInfo', 87.4);
    if (cmd === 'GetChargeState') later('ChargeState', 'charging');
    if (cmd === 'GetCleanState') later('CleanReport', 'idle');
    if (cmd === 'GetCleanSpeed') later('CleanSpeed', this.speed ?? 2);
    if (cmd === 'Clean' || cmd === 'Resume') later('CleanReport', 'auto');
    if (cmd === 'Pause') later('CleanReport', 'pause');
    if (cmd === 'Charge') later('ChargeState', 'returning');
    if (cmd === 'GetWaterLevel') later('WaterLevel', this.water ?? 2);
    if (cmd === 'SetWaterLevel') {
      this.water = args[0];
      later('WaterLevel', args[0]);
    }
    if (cmd === 'GetPosition') {
      later('DeebotPosition', '120,-340,90');
      later('ChargePosition', '0,0,0');
    }
    if (cmd === 'GetMaps' && !this.v2Only) later('Maps', MAPS);
    if (cmd === 'GetSpotAreas') later('MapSpotAreas', { mapID: args[0], mapSpotAreas: Object.keys(AREAS).map((id) => ({ mapSpotAreaID: id })) });
    // Réponses dans le désordre, comme sur le vrai robot.
    if (cmd === 'GetSpotAreaInfo') setTimeout(() => this.emit('MapSpotAreaInfo', { mapID: args[0], mapSpotAreaID: args[1], ...AREAS[args[1]] }), args[1] === '0' ? 9 : 3);
    if (cmd === 'SpotArea' || cmd === 'CustomArea') {
      later('ChargeState', 'idle');
      later('CleanReport', cmd === 'SpotArea' ? 'spot_area' : 'custom_area');
    }
    if (cmd === 'SetCleanSpeed') {
      this.speed = args[0];
      later('CleanSpeed', args[0]);
    }
  }
  /** Comme un robot yeedi : ne répond qu'à getMapInfo_V2 (pas à GetMaps). */
  sendCommand(cmd) {
    this.sent.push(['sendCommand', cmd.name]);
    if (this.v2Only && cmd.name === 'getMapInfo_V2') setTimeout(() => this.emit('Maps', MAPS), 5);
  }
  async disconnectAsync() {}
}

async function hubWith(bot) {
  const hub = new RobotHub({ login: async () => {}, robots: async () => [{ did: 'r1', name: 'Yeedi salon', model: 'yeedi 2 hybrid', bot }] });
  await hub.start();
  await new Promise((r) => setTimeout(r, 60));
  return hub;
}

test('état Solea à partir des messages du robot', () => {
  assert.equal(robotStatus({ cleanReport: 'auto', chargeStatus: 'idle' }), 'cleaning');
  assert.equal(robotStatus({ cleanReport: 'spot_area' }), 'cleaning');
  assert.equal(robotStatus({ cleanReport: 'pause' }), 'paused');
  assert.equal(robotStatus({ cleanReport: 'idle', chargeStatus: 'returning' }), 'returning');
  assert.equal(robotStatus({ cleanReport: 'idle', chargeStatus: 'charging' }), 'charging');
  assert.equal(robotStatus({ cleanReport: 'idle', chargeStatus: 'idle' }), 'idle');
  assert.equal(robotStatus({ cleanReport: 'auto', errorCode: '102' }), 'error');
  assert.equal(robotStatus({ cleanReport: 'auto', errorCode: '100' }), 'cleaning', '100 = pas d\'erreur');
  assert.ok(actionReached('charge', 'charging'));
  assert.ok(!actionReached('start', 'paused'));
});

test('liste des robots : batterie, état, puissance', async () => {
  const hub = await hubWith(new FakeBot());
  const [r] = hub.list();
  assert.equal(r.id, 'r1');
  assert.equal(r.online, true);
  assert.deepEqual(r.state, { status: 'charging', battery: 87, suction: 'standard', error: null, water: 'medium' });
  assert.deepEqual(r.map.rooms.map((x) => [x.id, x.name]), [['0', 'Living room'], ['1', 'Cuisine']], 'carte en cours seulement');
  assert.deepEqual(r.map.rooms[0].pts[1], [2000, -1500], 'coordonnées arrondies');
  assert.deepEqual(r.map.bot, [120, -340]);
  assert.deepEqual(r.map.charger, [0, 0]);
});

test('commande confirmée seulement quand le robot change d\'état', async () => {
  const bot = new FakeBot();
  const hub = await hubWith(bot);
  const res = await hub.command('r1', { action: 'start' }, 500);
  assert.equal(res.status, 'confirmed');
  assert.equal(res.robot.state.status, 'cleaning');
  assert.deepEqual(bot.sent.at(-1)[0], 'Clean');
  assert.equal((await hub.command('r1', { action: 'pause' }, 500)).status, 'confirmed');
  assert.equal((await hub.command('r1', { suction: 'max' }, 500)).robot.state.suction, 'max');
  assert.deepEqual(bot.sent.find((c) => c[0] === 'SetCleanSpeed'), ['SetCleanSpeed', 4]);
});

test('pièces, zone et débit d\'eau : confirmés par le mode de nettoyage du robot', async () => {
  const bot = new FakeBot();
  const hub = await hubWith(bot);
  const rooms = await hub.command('r1', { rooms: ['1', '0'], passes: 2 }, 500);
  assert.equal(rooms.status, 'confirmed');
  assert.deepEqual(bot.sent.find((c) => c[0] === 'SpotArea'), ['SpotArea', 'start', '1,0', 2]);
  const zone = await hub.command('r1', { zone: [-500.6, -500, 500, 800] }, 500);
  assert.equal(zone.status, 'confirmed');
  assert.deepEqual(bot.sent.find((c) => c[0] === 'CustomArea'), ['CustomArea', 'start', '-501,-500,500,800', 1]);
  assert.equal((await hub.command('r1', { water: 'max' }, 500)).robot.state.water, 'max');
  assert.equal((await hub.command('r1', { rooms: ['7'] }, 50)).error, 'Pièce inconnue sur la carte');
  assert.equal((await hub.command('r1', { rooms: [] }, 50)).status, 'failed');
  assert.equal((await hub.command('r1', { zone: [1, 2, 3] }, 50)).error, 'Zone invalide');
  assert.equal((await hub.command('r1', { water: 'déluge' }, 50)).status, 'failed');
});

test('robot yeedi qui ne répond qu\'à getMapInfo_V2 : carte quand même', async () => {
  const bot = new FakeBot();
  bot.v2Only = true;
  const hub = await hubWith(bot);
  assert.deepEqual(hub.list()[0].map.rooms.map((r) => r.id), ['0', '1']);
  assert.equal(bot.sent.filter((c) => c[0] === 'GetSpotAreas').length, 1, 'pas de doublon');
});

test('contours de pièces allégés', () => {
  const many = Array.from({ length: 500 }, (_, i) => `${i},${i * 2}`).join(';');
  assert.equal(parseBoundary(many).length, 48);
  assert.deepEqual(parseBoundary('1,2;x,3;;4.6,5'), [[1, 2], [5, 5]]);
  assert.deepEqual(parseBoundary([...Buffer.from('10,20;30,40;50,60')]), [[10, 20], [30, 40], [50, 60]], 'contour en octets');
  assert.deepEqual(parseBoundary(Buffer.from('1,1; 2,2;\n3,3')), [[1, 1], [2, 2], [3, 3]]);
  assert.equal(roomFromInfo(null), null);
  assert.equal(roomFromInfo({ mapSpotAreaID: 3, mapSpotAreaBoundaries: '0,0;1,1' }), null, 'moins de 3 points : ignorée');
  assert.deepEqual(roomFromInfo({ mapSpotAreaID: 3, mapSpotAreaName: 'B', mapSpotAreaBoundaries: '0,0;1,0;1,1' }), { id: '3', name: 'B', pts: [[0, 0], [1, 0], [1, 1]] });
});

test('robot muet : délai dépassé ; action ou robot inconnus refusés', async () => {
  const bot = new FakeBot();
  const hub = await hubWith(bot);
  bot.deaf = true;
  assert.equal((await hub.command('r1', { action: 'start' }, 50)).status, 'timeout');
  assert.equal((await hub.command('r1', { action: 'charge' }, 50)).status, 'confirmed', 'déjà en charge');
  assert.equal((await hub.command('r1', { action: 'exploser' }, 50)).status, 'failed');
  assert.equal((await hub.command('r1', { suction: 'turbo' }, 50)).status, 'failed');
  assert.equal((await hub.command('zz', { action: 'start' }, 50)).error, 'Robot inconnu');
  bot.emit('disconnect');
  assert.equal(hub.list()[0].online, false);
  assert.equal((await hub.command('r1', { action: 'start' }, 50)).error, 'Robot hors ligne');
});

test('API locale : jeton obligatoire, liste et commande', async () => {
  const hub = await hubWith(new FakeBot());
  const server = yeediServer(hub, { token: 'secret-123', commandTimeoutMs: 500 });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(`${base}/robots`)).status, 401);
    assert.equal((await fetch(`${base}/robots`, { headers: { authorization: 'Bearer faux' } })).status, 401);
    const auth = { authorization: 'Bearer secret-123', 'content-type': 'application/json' };
    const list = await (await fetch(`${base}/robots`, { headers: auth })).json();
    assert.equal(list[0].name, 'Yeedi salon');
    const res = await (await fetch(`${base}/robots/r1/command`, { method: 'POST', headers: auth, body: JSON.stringify({ action: 'charge' }) })).json();
    assert.equal(res.status, 'confirmed');
    const zone = await (await fetch(`${base}/robots/r1/command`, { method: 'POST', headers: auth, body: JSON.stringify({ zone: [0, 0, 900, 900], passes: 2 }) })).json();
    assert.equal(zone.status, 'confirmed');
    assert.equal((await fetch(`${base}/robots/r1/command`, { method: 'POST', headers: auth, body: '{pas du json' })).status, 400);
  } finally {
    server.close();
  }
});

test('formulaire et .env de la passerelle', () => {
  const f = readForm('EMAIL_YEEDI= moi@exemple.dz \r\nMOT_DE_PASSE_YEEDI=abc\r\nPAYS=fr\r\n');
  assert.deepEqual(f, { email: 'moi@exemple.dz', password: 'abc', country: 'FR', missing: [] });
  assert.deepEqual(readForm('EMAIL_YEEDI=\nPAYS=Algérie').missing, ['EMAIL_YEEDI', 'MOT_DE_PASSE_YEEDI', 'PAYS (2 lettres)']);
  const env = setEnvLines('# Solea\nADAPTER=tuya_cloud\nYEEDI_TOKEN=ancien\n', { YEEDI_URL: 'http://127.0.0.1:8790', YEEDI_TOKEN: 'nouveau' });
  assert.equal(env, '# Solea\nADAPTER=tuya_cloud\nYEEDI_TOKEN=nouveau\nYEEDI_URL=http://127.0.0.1:8790\n');
});

test('coupure passagère (« Robot not reachable ») : pas d\'erreur affichée, effacée par la réponse suivante', async () => {
  const bot = new FakeBot();
  const hub = new RobotHub(
    { login: async () => {}, robots: async () => [{ did: 'r1', name: 'Idir', model: '04z443', bot }] },
    { refreshMs: 30 },
  );
  await hub.start();
  await new Promise((r) => setTimeout(r, 30));
  bot.emit('ErrorCode', '4200');
  bot.emit('Error', 'Robot not reachable');
  assert.equal(hub.list()[0].state.status, 'charging', 'pas « En erreur » pour une coupure');
  assert.equal(hub.list()[0].state.error, null);
  const before = bot.sent.filter((c) => c[0] === 'GetBatteryState').length;
  await new Promise((r) => setTimeout(r, 80));
  assert.ok(bot.sent.filter((c) => c[0] === 'GetBatteryState').length > before, 'interrogation régulière');
  assert.equal(hub.list()[0].state.error, null);
  // Une vraie panne reste visible.
  bot.emit('ErrorCode', '102');
  bot.emit('Error', 'Roue bloquée');
  assert.equal(hub.list()[0].state.status, 'error');
  assert.equal(hub.list()[0].state.error, 'Roue bloquée');
  await hub.stop();
});
