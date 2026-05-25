import assert from 'node:assert/strict';
import test from 'node:test';
import { executeIntent } from '../src/services/sonos/sonosCommands.js';

const originalFetch = global.fetch;
const originalLocalStorage = global.localStorage;

function makeLocalStorage(seed = {}) {
  const values = new Map(Object.entries(seed));
  return {
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: (key) => values.delete(key),
  };
}

function jsonResponse(payload, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => payload,
    text: async () => JSON.stringify(payload),
  };
}

function makeRooms() {
  return [
    {
      id: 'kitchen',
      name: 'Kitchen',
      playerID: 'player-1',
      groupID: 'group-1',
      householdID: 'household-1',
      volume: 20,
    },
    {
      id: 'bedroom',
      name: 'Bedroom',
      playerID: 'player-2',
      groupID: 'group-2',
      householdID: 'household-1',
      volume: 30,
    },
  ];
}

function installSonosFetch(responseForPath = () => ({})) {
  const calls = [];
  global.fetch = async (_url, options) => {
    const request = JSON.parse(options.body);
    calls.push(request);
    return jsonResponse(responseForPath(request));
  };
  return calls;
}

test.beforeEach(() => {
  global.localStorage = makeLocalStorage({
    sonos_access_token: 'access-token',
    sonos_selected_household: 'household-1',
  });
});

test.afterEach(() => {
  global.fetch = originalFetch;
  global.localStorage = originalLocalStorage;
});

test('executeIntent sends play to the selected room group', async () => {
  const calls = installSonosFetch();
  const rooms = makeRooms();

  const message = await executeIntent(
    { action: 'play', targetRoom: 'Kitchen', contentQuery: null, scope: 'single_room' },
    rooms,
    rooms[0]
  );

  assert.equal(message, 'Resumed playback in Kitchen.');
  assert.deepEqual(calls.map((call) => [call.path, call.method]), [
    ['groups/group-1/playback/play', 'POST'],
  ]);
});

test('executeIntent pauses each unique group for pause everywhere', async () => {
  const calls = installSonosFetch();
  const rooms = makeRooms();
  rooms.push({ ...rooms[0], id: 'kitchen-surround', playerID: 'player-3' });

  const message = await executeIntent(
    { action: 'pause', targetRoom: null, contentQuery: null, scope: 'all_rooms' },
    rooms,
    rooms[0]
  );

  assert.equal(message, 'Paused playback everywhere.');
  assert.deepEqual(calls.map((call) => call.path), [
    'groups/group-1/playback/pause',
    'groups/group-2/playback/pause',
  ]);
});

test('executeIntent groups all rooms and resumes playback', async () => {
  const calls = installSonosFetch((request) => {
    if (request.path === 'households/household-1/groups') {
      return {
        groups: [
          { id: 'new-group', playerIds: ['player-1', 'player-2'] },
        ],
      };
    }
    return {};
  });
  const rooms = makeRooms();

  const message = await executeIntent(
    { action: 'group_all', targetRoom: null, contentQuery: null, scope: 'all_rooms' },
    rooms,
    rooms[0]
  );

  assert.equal(message, 'Grouped all rooms and resumed playback.');
  assert.deepEqual(calls.map((call) => call.path), [
    'households/household-1/groups/createGroup',
    'households/household-1/groups',
    'groups/new-group/playback/play',
  ]);
});

test('executeIntent clamps set volume commands before sending to Sonos', async () => {
  const calls = installSonosFetch();
  const rooms = makeRooms();

  const message = await executeIntent(
    { action: 'set_volume', targetRoom: 'Kitchen', volumeValue: 150, scope: 'single_room' },
    rooms,
    rooms[0]
  );

  assert.equal(message, 'Set Kitchen to volume 100.');
  assert.equal(calls[0].path, 'players/player-1/playerVolume');
  assert.deepEqual(calls[0].body, { volume: 100 });
});

test('executeIntent reports missing group and player identifiers', async () => {
  installSonosFetch();
  const rooms = [{ ...makeRooms()[0], groupID: null, playerID: null }];

  await assert.rejects(
    executeIntent(
      { action: 'play', targetRoom: 'Kitchen', contentQuery: null, scope: 'single_room' },
      rooms,
      rooms[0]
    ),
    /No room selected or room missing group/
  );

  await assert.rejects(
    executeIntent(
      { action: 'volume_up', targetRoom: 'Kitchen', contentQuery: null, scope: 'single_room' },
      rooms,
      rooms[0]
    ),
    /No room selected/
  );
});
