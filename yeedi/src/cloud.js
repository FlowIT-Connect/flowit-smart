// Connexion au cloud yeedi (Ecovacs) avec la bibliothèque ecovacs-deebot (GPL-3.0).
//
// Copyright (C) 2026 FlowIT Connect
// Ce programme est un logiciel libre : GPL version 3 ou ultérieure (voir LICENSE).

import { createHash } from 'node:crypto';
import { hostname } from 'node:os';
import ecovacsDeebot from 'ecovacs-deebot';

const { EcoVacsAPI } = ecovacsDeebot;

/**
 * @param {{email:string, passwordMd5:string, country:string, domain?:string}} opts
 *   domain = 'yeedi.com' pour un compte yeedi, '' pour un compte Ecovacs.
 */
export function yeediCloud({ email, passwordMd5, country, domain = 'yeedi.com' }) {
  // Identifiant stable de cette machine auprès du cloud (sinon une nouvelle « session » à chaque démarrage).
  const machine = createHash('md5').update(`solea-yeedi:${hostname()}`).digest('hex');
  const api = new EcoVacsAPI(EcoVacsAPI.getDeviceId(machine, 0), country.toUpperCase(), '', domain);
  return {
    async login() {
      await api.connect(email, passwordMd5);
    },
    async robots() {
      const devices = await api.devices();
      return Object.values(devices ?? {}).map((d) => ({
        did: String(d.did),
        name: d.nick || d.deviceName || d.name || 'Robot yeedi',
        model: d.deviceName || d.class || 'yeedi',
        bot: api.getVacBot(api.uid, EcoVacsAPI.REALM, api.resource, api.user_access_token, d),
      }));
    },
  };
}

export const md5 = (text) => createHash('md5').update(text).digest('hex');
