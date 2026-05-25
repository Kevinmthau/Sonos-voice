import { sonosAPI } from './sonosApiClient.js';

export async function sonosPlay(groupID) {
  await sonosAPI(`groups/${groupID}/playback/play`, 'POST');
}

export async function sonosPause(groupID) {
  await sonosAPI(`groups/${groupID}/playback/pause`, 'POST');
}

export async function sonosSkip(groupID) {
  await sonosAPI(`groups/${groupID}/playback/skipToNextTrack`, 'POST');
}

export async function sonosSetVolume(playerID, volume) {
  await sonosAPI(`players/${playerID}/playerVolume`, 'POST', {
    volume: Math.max(0, Math.min(100, volume)),
  });
}

export async function sonosVolumeRelative(playerID, delta) {
  await sonosAPI(`players/${playerID}/playerVolume/relative`, 'POST', {
    volumeDelta: delta,
  });
}

export async function sonosCreateGroup(householdID, playerIDs) {
  await sonosAPI(`households/${householdID}/groups/createGroup`, 'POST', {
    playerIds: playerIDs,
  });

  const data = await sonosAPI(`households/${householdID}/groups`);
  const requestedSet = new Set(playerIDs);
  const created = (data.groups || []).find(
    (g) => g.playerIds && g.playerIds.length === playerIDs.length && g.playerIds.every((id) => requestedSet.has(id))
  );

  if (!created) throw new Error('Group was created but could not be resolved.');
  return created.id;
}

function normalize(text) {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

async function resolveQueueContent(query, householdID) {
  const normalizedQuery = normalize(query);

  const favorites = await sonosAPI(`households/${householdID}/favorites`);
  const favItems = favorites.items || favorites.favorites || [];
  const fav = bestMatch(normalizedQuery, favItems);
  if (fav) {
    return { type: 'favorite', id: fav.favoriteId || fav.id, name: fav.name || fav.title || 'Untitled' };
  }

  const playlists = await sonosAPI(`households/${householdID}/playlists`);
  const plItems = playlists.items || playlists.playlists || [];
  const pl = bestMatch(normalizedQuery, plItems);
  if (pl) {
    return { type: 'playlist', id: pl.playlistId || pl.id, name: pl.name || pl.title || 'Untitled' };
  }

  throw new Error(
    `Could not find a favorite or playlist matching "${query}". Arbitrary search queries need a content-service integration.`
  );
}

function bestMatch(normalizedQuery, items) {
  const exact = items.find((item) => {
    const id = item.favoriteId || item.playlistId || item.id;
    return id && normalize(item.name || item.title || '') === normalizedQuery;
  });
  if (exact) return exact;

  return items.find((item) => {
    const id = item.favoriteId || item.playlistId || item.id;
    const candidate = normalize(item.name || item.title || '');
    return id && (candidate.includes(normalizedQuery) || normalizedQuery.includes(candidate));
  });
}

async function loadContent(groupID, content) {
  if (content.type === 'favorite') {
    await sonosAPI(`groups/${groupID}/favorites/loadFavorite`, 'POST', {
      favoriteId: content.id,
      queueAction: 'REPLACE',
    });
    return;
  }

  await sonosAPI(`groups/${groupID}/playlists/loadPlaylist`, 'POST', {
    playlistId: content.id,
    queueAction: 'REPLACE',
  });
}

export async function executeIntent(intent, rooms, selectedRoom) {
  const resolveRoom = (roomName) => {
    if (!roomName) return selectedRoom;
    return rooms.find((r) => r.name.toLowerCase() === roomName.toLowerCase()) || selectedRoom;
  };

  const room = resolveRoom(intent.targetRoom);

  switch (intent.action) {
    case 'play': {
      if (!room?.groupID) throw new Error('No room selected or room missing group.');
      if (intent.contentQuery) {
        const content = await resolveQueueContent(intent.contentQuery, room.householdID);
        await loadContent(room.groupID, content);
        return `Loaded ${content.name} in ${room.name}.`;
      }
      await sonosPlay(room.groupID);
      return `Resumed playback in ${room.name}.`;
    }

    case 'pause': {
      if (intent.scope === 'all_rooms') {
        const groupIDs = [...new Set(rooms.map((r) => r.groupID).filter(Boolean))];
        for (const gid of groupIDs) {
          await sonosPause(gid);
        }
        return 'Paused playback everywhere.';
      }
      if (!room?.groupID) throw new Error('No room selected.');
      await sonosPause(room.groupID);
      return `Paused ${room.name}.`;
    }

    case 'resume': {
      if (intent.scope === 'all_rooms') {
        const groupIDs = [...new Set(rooms.map((r) => r.groupID).filter(Boolean))];
        for (const gid of groupIDs) {
          await sonosPlay(gid);
        }
        return 'Resumed playback everywhere.';
      }
      if (!room?.groupID) throw new Error('No room selected.');
      await sonosPlay(room.groupID);
      return `Resumed playback in ${room.name}.`;
    }

    case 'skip': {
      if (!room?.groupID) throw new Error('No room selected.');
      await sonosSkip(room.groupID);
      return `Skipped in ${room.name}.`;
    }

    case 'volume_up': {
      if (!room?.playerID) throw new Error('No room selected.');
      await sonosVolumeRelative(room.playerID, 5);
      return `Raised volume in ${room.name}.`;
    }

    case 'volume_down': {
      if (!room?.playerID) throw new Error('No room selected.');
      await sonosVolumeRelative(room.playerID, -5);
      return `Lowered volume in ${room.name}.`;
    }

    case 'set_volume': {
      if (!room?.playerID) throw new Error('No room selected.');
      const volume = Math.max(0, Math.min(100, intent.volumeValue ?? 20));
      await sonosSetVolume(room.playerID, volume);
      return `Set ${room.name} to volume ${volume}.`;
    }

    case 'group_all': {
      const playerIDs = rooms.map((r) => r.playerID).filter(Boolean);
      if (!playerIDs.length) throw new Error('No Sonos players discovered.');
      const householdID = rooms[0]?.householdID;
      if (!householdID) throw new Error('No household found.');
      const groupID = await sonosCreateGroup(householdID, playerIDs);

      if (intent.contentQuery) {
        const content = await resolveQueueContent(intent.contentQuery, householdID);
        await loadContent(groupID, content);
        return `Grouped all rooms and loaded ${content.name}.`;
      }

      await sonosPlay(groupID);
      return 'Grouped all rooms and resumed playback.';
    }

    default:
      throw new Error(`Unknown action: ${intent.action}`);
  }
}
