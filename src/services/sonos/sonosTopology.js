import { sonosAPI } from './sonosApiClient.js';

export async function fetchHouseholds() {
  const data = await sonosAPI('households');
  return (data.households || []).map((h) => ({
    id: h.id || h.householdId,
    name: h.name || h.id || 'Sonos Household',
    roomNames: [],
  }));
}

export async function fetchRooms(householdID) {
  const data = await sonosAPI(`households/${householdID}/groups`);
  const players = data.players || [];
  const groups = data.groups || [];

  const rooms = await Promise.all(
    players.map(async (player) => {
      const group = groups.find((g) => (g.playerIds || []).includes(player.id));
      let volume = 20;
      try {
        const volData = await sonosAPI(`players/${player.id}/playerVolume`);
        volume = Math.max(0, Math.min(100, volData.volume ?? 20));
      } catch {
        // keep the default when Sonos omits or rejects per-player volume
      }

      const playbackState = group?.playbackState || '';
      const isPlaying =
        playbackState.toUpperCase().includes('PLAYING') ||
        playbackState.toUpperCase().includes('BUFFERING');

      return {
        id: player.id,
        name: player.name || player.playerName || player.roomName || `Room ${player.id.slice(0, 6)}`,
        playerID: player.id,
        groupID: group?.id || null,
        householdID,
        volume,
        isCoordinator: group?.coordinatorId === player.id,
        groupName: group?.name || null,
        isPlaying,
        currentContent: null,
      };
    })
  );

  return rooms.sort((a, b) => a.name.localeCompare(b.name));
}
