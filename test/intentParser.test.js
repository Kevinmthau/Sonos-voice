import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { parseIntent } from '../src/parsing/intentParser.js';

const fixture = JSON.parse(readFileSync(new URL('../shared/intent-parser-fixtures.json', import.meta.url), 'utf8'));

function makeRooms(roomNames) {
  return roomNames.map((name) => ({
    id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'),
    name,
  }));
}

function comparableIntent(intent) {
  if (!intent) return null;
  return {
    originalTranscript: intent.originalTranscript,
    action: intent.action,
    targetRoom: intent.targetRoom,
    contentQuery: intent.contentQuery,
    volumeValue: intent.volumeValue,
    scope: intent.scope,
  };
}

test('parseIntent matches the shared command contract', async (t) => {
  const rooms = makeRooms(fixture.rooms);

  for (const testCase of fixture.cases) {
    await t.test(testCase.name, () => {
      const selectedRoom = rooms.find((room) => room.name === testCase.selectedRoom) ?? null;
      const parsed = parseIntent(testCase.transcript, rooms, selectedRoom);
      const expected = testCase.expected
        ? { originalTranscript: testCase.transcript, ...testCase.expected }
        : null;

      assert.deepEqual(comparableIntent(parsed), expected);
    });
  }
});
