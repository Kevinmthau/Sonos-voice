import { useCallback, useEffect, useState } from 'react';
import {
  clearTokens,
  fetchHouseholds,
  fetchRooms,
  getSelectedHouseholdID,
  getStoredToken,
  setSelectedHouseholdID,
  storeTokens,
} from '../services/sonosController.js';

export function useSonosConnection({ appendLog }) {
  const [connectionStatus, setConnectionStatus] = useState('checking');
  const [households, setHouseholds] = useState([]);
  const [selectedHouseholdId, setSelectedHouseholdId] = useState('');
  const [rooms, setRooms] = useState([]);
  const [selectedRoomId, setSelectedRoomId] = useState('');
  const [statusText, setStatusText] = useState('Discovering Sonos rooms...');

  const selectedRoom = rooms.find((r) => r.id === selectedRoomId) || rooms[0] || null;
  const householdName = households.find((h) => h.id === selectedHouseholdId)?.name || 'No household selected';

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const accessToken = params.get('access_token');
    const refreshToken = params.get('refresh_token');
    const error = params.get('error');

    if (error) {
      const desc = params.get('error_description') || error;
      setStatusText(`Auth error: ${desc}`);
      setConnectionStatus('auth_required');
      window.history.replaceState({}, '', '/');
      return;
    }

    if (accessToken) {
      storeTokens(accessToken, refreshToken);
      window.history.replaceState({}, '', '/');
    }
  }, []);

  useEffect(() => {
    async function init() {
      const token = getStoredToken();
      if (!token) {
        setConnectionStatus('auth_required');
        setStatusText('Please sign in to Sonos.');
        appendLog('No Sonos token found. Sign in required.');
        return;
      }

      try {
        const hh = await fetchHouseholds();
        setHouseholds(hh);
        const savedId = getSelectedHouseholdID();
        const householdId = hh.find((h) => h.id === savedId)?.id || hh[0]?.id || '';
        setSelectedHouseholdId(householdId);
        setSelectedHouseholdID(householdId);
        setConnectionStatus('ready');
        appendLog('Connected to Sonos.');

        if (householdId) {
          const discoveredRooms = await fetchRooms(householdId);
          setRooms(discoveredRooms);
          setSelectedRoomId(discoveredRooms[0]?.id || '');
          setStatusText(`Ready. Found ${discoveredRooms.length} room${discoveredRooms.length === 1 ? '' : 's'}.`);
          appendLog(`Discovered ${discoveredRooms.length} rooms.`);
        }
      } catch (err) {
        if (err.message.includes('expired') || err.message.includes('Not authenticated')) {
          setConnectionStatus('auth_required');
          setStatusText('Session expired. Please sign in again.');
          clearTokens();
        } else {
          setConnectionStatus('unavailable');
          setStatusText(err.message);
        }
        appendLog(err.message);
      }
    }

    init();
  }, [appendLog]);

  const refreshRooms = useCallback(async () => {
    if (!selectedHouseholdId) return;
    try {
      const discoveredRooms = await fetchRooms(selectedHouseholdId);
      setRooms(discoveredRooms);
      if (!discoveredRooms.find((r) => r.id === selectedRoomId)) {
        setSelectedRoomId(discoveredRooms[0]?.id || '');
      }
      setStatusText(`Refreshed. Found ${discoveredRooms.length} room${discoveredRooms.length === 1 ? '' : 's'}.`);
      appendLog(`Refreshed rooms: ${discoveredRooms.length}`);
    } catch (err) {
      setStatusText(err.message);
      appendLog(`Refresh failed: ${err.message}`);
    }
  }, [selectedHouseholdId, selectedRoomId, appendLog]);

  const handleDisconnect = useCallback(() => {
    clearTokens();
    setConnectionStatus('auth_required');
    setHouseholds([]);
    setRooms([]);
    setSelectedRoomId('');
    setSelectedHouseholdId('');
    setStatusText('Disconnected from Sonos.');
    appendLog('Disconnected.');
  }, [appendLog]);

  const handleHouseholdChange = useCallback(
    async (id) => {
      setSelectedHouseholdId(id);
      setSelectedHouseholdID(id);
      appendLog(`Selected household: ${id}`);
      try {
        const discoveredRooms = await fetchRooms(id);
        setRooms(discoveredRooms);
        setSelectedRoomId(discoveredRooms[0]?.id || '');
        setStatusText(`Found ${discoveredRooms.length} rooms.`);
      } catch (err) {
        setStatusText(err.message);
      }
    },
    [appendLog]
  );

  const handleRoomChange = useCallback(
    (id) => {
      setSelectedRoomId(id);
      const room = rooms.find((r) => r.id === id);
      if (room) appendLog(`Selected room: ${room.name}`);
    },
    [rooms, appendLog]
  );

  return {
    connectionStatus,
    households,
    householdName,
    rooms,
    selectedHouseholdId,
    selectedRoom,
    selectedRoomId,
    statusText,
    handleDisconnect,
    handleHouseholdChange,
    handleRoomChange,
    refreshRooms,
    setStatusText,
  };
}
