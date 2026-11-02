import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { manageableHomes, renderVideoEnv } from '../src/setup_video.js';
import { parseEnv } from '../src/setup.js';

describe('Boîtier vidéo : configuration Windows', () => {
  it('écrit un .env.video lisible par la passerelle, en mode vidéo', () => {
    const env = parseEnv(renderVideoEnv({ SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k', INTEGRATION_ID: 'i1', HOME_NAME: 'Villa' }));
    assert.equal(env.ADAPTER, 'video');
    assert.equal(env.INTEGRATION_ID, 'i1');
    assert.equal(env.SUPABASE_SERVICE_ROLE_KEY, 'k');
    assert.equal(env.MEDIAMTX, 'true');
  });

  it('propose seulement les logements gérés, sans doublon', () => {
    const homes = manageableHomes(
      [{ id: 'a', name: 'Villa' }],
      [
        { role: 'owner', homes: { id: 'a', name: 'Villa' } },
        { role: 'admin', homes: { id: 'b', name: 'Appartement' } },
        { role: 'member', homes: { id: 'c', name: 'Chez un ami' } },
      ],
    );
    assert.deepEqual(homes.map((h) => h.id), ['b', 'a']);
  });
});
