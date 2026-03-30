function normalize(text) {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function matchesAny(transcript, phrases) {
  return phrases.includes(transcript);
}

function containsAny(transcript, phrases) {
  return phrases.some((p) => transcript.includes(p));
}

function isPauseCommand(t) {
  return matchesAny(t, ['pause', 'pause everywhere', 'pause all', 'pause all rooms', 'stop', 'stop everywhere']);
}

function isResumeCommand(t) {
  return matchesAny(t, ['resume', 'resume everywhere', 'continue', 'continue everywhere']);
}

function isSkipCommand(t) {
  return matchesAny(t, ['skip', 'next', 'next song', 'skip this']);
}

function isVolumeUpCommand(t) {
  return containsAny(t, ['turn it up', 'turn up', 'volume up', 'louder', 'increase volume']);
}

function isVolumeDownCommand(t) {
  return containsAny(t, ['turn it down', 'turn down', 'volume down', 'quieter', 'decrease volume']);
}

function referencesAllRooms(t) {
  return containsAny(t, ['everywhere', 'all rooms', 'every room']);
}

function extractFirstNumber(normalizedTranscript) {
  const match = normalizedTranscript.match(/\b(\d{1,3})\b/);
  return match ? parseInt(match[1], 10) : null;
}

function matchedRoomName(normalizedTranscript, availableRooms) {
  const sorted = [...availableRooms].sort(
    (a, b) => normalize(b.name).length - normalize(a.name).length
  );

  for (const room of sorted) {
    const normalizedRoom = normalize(room.name);
    const escaped = normalizedRoom.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const pattern = new RegExp(`(^|\\b)${escaped}(\\b|$)`);
    if (pattern.test(normalizedTranscript)) {
      return room.name;
    }
  }

  return null;
}

function cleanQuery(query) {
  const cleaned = normalize(query);
  return cleaned || null;
}

function parseSetVolume(transcript, normalizedTranscript, targetRoom) {
  const startsLikeSetVolume =
    normalizedTranscript.startsWith('set ') ||
    normalizedTranscript.includes(' volume ') ||
    normalizedTranscript.startsWith('volume ');

  if (!startsLikeSetVolume) return null;

  const value = extractFirstNumber(normalizedTranscript);
  if (value === null) return null;

  return {
    originalTranscript: transcript,
    action: 'set_volume',
    targetRoom,
    contentQuery: null,
    volumeValue: Math.max(0, Math.min(100, value)),
    scope: 'single_room',
  };
}

function extractAllRoomsPlayQuery(normalizedTranscript) {
  const noQueryPhrases = [
    'play everywhere',
    'play all',
    'play all rooms',
    'play in all rooms',
    'play in every room',
  ];

  if (noQueryPhrases.includes(normalizedTranscript)) return null;

  const suffixes = [' everywhere', ' in all rooms', ' in every room'];
  for (const suffix of suffixes) {
    if (normalizedTranscript.endsWith(suffix)) {
      const query = normalizedTranscript.slice(5, -suffix.length);
      return cleanQuery(query);
    }
  }

  return null;
}

function parsePlay(transcript, normalizedTranscript, explicitRoom, fallbackRoom) {
  if (!normalizedTranscript.startsWith('play ')) return null;

  if (referencesAllRooms(normalizedTranscript)) {
    return {
      originalTranscript: transcript,
      action: 'group_all',
      targetRoom: null,
      contentQuery: extractAllRoomsPlayQuery(normalizedTranscript),
      volumeValue: null,
      scope: 'all_rooms',
    };
  }

  let query = normalizedTranscript.slice(5).trim();

  if (explicitRoom) {
    const normalizedRoom = normalize(explicitRoom);
    const suffixes = [
      ` in the ${normalizedRoom}`,
      ` in ${normalizedRoom}`,
      ` on the ${normalizedRoom}`,
      ` on ${normalizedRoom}`,
    ];

    for (const suffix of suffixes) {
      if (query.endsWith(suffix)) {
        query = query.slice(0, -suffix.length).trim();
        break;
      }
    }

    if (query === normalizedRoom) {
      query = '';
    }
  }

  const cleanedQuery = cleanQuery(query);
  if (!cleanedQuery) {
    return {
      originalTranscript: transcript,
      action: 'resume',
      targetRoom: fallbackRoom,
      contentQuery: null,
      volumeValue: null,
      scope: 'single_room',
    };
  }

  return {
    originalTranscript: transcript,
    action: 'play',
    targetRoom: fallbackRoom,
    contentQuery: cleanedQuery,
    volumeValue: null,
    scope: 'single_room',
  };
}

export function parseIntent(transcript, availableRooms, selectedRoom) {
  const normalizedTranscript = normalize(transcript);
  if (!normalizedTranscript) return null;

  const explicitRoom = matchedRoomName(normalizedTranscript, availableRooms);
  const fallbackRoom = explicitRoom || selectedRoom?.name || null;

  if (isPauseCommand(normalizedTranscript)) {
    const allRooms = referencesAllRooms(normalizedTranscript);
    return {
      originalTranscript: transcript,
      action: 'pause',
      targetRoom: allRooms ? null : fallbackRoom,
      contentQuery: null,
      volumeValue: null,
      scope: allRooms ? 'all_rooms' : 'single_room',
    };
  }

  const setVolumeIntent = parseSetVolume(transcript, normalizedTranscript, fallbackRoom);
  if (setVolumeIntent) return setVolumeIntent;

  if (isVolumeUpCommand(normalizedTranscript)) {
    return {
      originalTranscript: transcript,
      action: 'volume_up',
      targetRoom: fallbackRoom,
      contentQuery: null,
      volumeValue: null,
      scope: 'single_room',
    };
  }

  if (isVolumeDownCommand(normalizedTranscript)) {
    return {
      originalTranscript: transcript,
      action: 'volume_down',
      targetRoom: fallbackRoom,
      contentQuery: null,
      volumeValue: null,
      scope: 'single_room',
    };
  }

  if (isSkipCommand(normalizedTranscript)) {
    return {
      originalTranscript: transcript,
      action: 'skip',
      targetRoom: fallbackRoom,
      contentQuery: null,
      volumeValue: null,
      scope: 'single_room',
    };
  }

  if (isResumeCommand(normalizedTranscript)) {
    const allRooms = referencesAllRooms(normalizedTranscript);
    return {
      originalTranscript: transcript,
      action: 'resume',
      targetRoom: allRooms ? null : fallbackRoom,
      contentQuery: null,
      volumeValue: null,
      scope: allRooms ? 'all_rooms' : 'single_room',
    };
  }

  if (normalizedTranscript === 'play') {
    return {
      originalTranscript: transcript,
      action: 'resume',
      targetRoom: fallbackRoom,
      contentQuery: null,
      volumeValue: null,
      scope: 'single_room',
    };
  }

  const playIntent = parsePlay(transcript, normalizedTranscript, explicitRoom, fallbackRoom);
  if (playIntent) return playIntent;

  return null;
}

export function intentSummary(intent) {
  if (!intent) return 'No parsed command yet.';

  const actionDisplay = intent.action.replace(/_/g, ' ');
  const scopeDisplay = intent.scope.replace(/_/g, ' ');
  const parts = [`action: ${actionDisplay}`, `scope: ${scopeDisplay}`];

  if (intent.targetRoom) parts.push(`room: ${intent.targetRoom}`);
  if (intent.contentQuery) parts.push(`query: ${intent.contentQuery}`);
  if (intent.volumeValue != null) parts.push(`volume: ${intent.volumeValue}`);

  return parts.join(' | ');
}
