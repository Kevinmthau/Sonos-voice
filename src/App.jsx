import { useState, useEffect, useRef, useCallback } from 'react';
import { parseIntent, intentSummary } from './parsing/intentParser.js';
import { isSpeechSupported, createSpeechRecognizer } from './services/speechRecognizer.js';
import {
  getStoredToken,
  storeTokens,
  clearTokens,
  fetchHouseholds,
  fetchRooms,
  executeIntent,
  getSelectedHouseholdID,
  setSelectedHouseholdID,
} from './services/sonosController.js';

function makeLogLine(msg) {
  const now = new Date();
  const ts = now.toLocaleTimeString('en-US', { hour12: false });
  return `[${ts}] ${msg}`;
}

export default function App() {
  const [connectionStatus, setConnectionStatus] = useState('checking');
  const [households, setHouseholds] = useState([]);
  const [selectedHouseholdId, setSelectedHouseholdId] = useState('');
  const [rooms, setRooms] = useState([]);
  const [selectedRoomId, setSelectedRoomId] = useState('');
  const [isRecording, setIsRecording] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [parsedIntent, setParsedIntent] = useState(null);
  const [statusText, setStatusText] = useState('Discovering Sonos rooms...');
  const [isExecuting, setIsExecuting] = useState(false);
  const [debugLog, setDebugLog] = useState([]);
  const recognizerRef = useRef(null);

  const selectedRoom = rooms.find((r) => r.id === selectedRoomId) || rooms[0] || null;

  const appendLog = useCallback((msg) => {
    const line = makeLogLine(msg);
    setDebugLog((prev) => [line, ...prev].slice(0, 8));
  }, []);

  // Handle OAuth callback params on mount
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

  // Initial load
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

  const doExecute = useCallback(
    async (intent) => {
      setIsExecuting(true);
      setStatusText(`Executing ${intent.action.replace(/_/g, ' ')}...`);
      appendLog(`Executing: ${intentSummary(intent)}`);
      try {
        const msg = await executeIntent(intent, rooms, selectedRoom);
        setStatusText(msg);
        appendLog(msg);
        await refreshRooms();
      } catch (err) {
        setStatusText(err.message);
        appendLog(`Error: ${err.message}`);
      }
      setIsExecuting(false);
    },
    [rooms, selectedRoom, refreshRooms, appendLog]
  );

  const toggleRecording = useCallback(() => {
    if (isRecording) {
      // Stop and execute
      recognizerRef.current?.stop();
      setIsRecording(false);
      appendLog('Stopped listening.');

      const finalTranscript = transcript.trim();
      if (!finalTranscript) {
        setStatusText('No speech captured.');
        return;
      }

      const intent = parseIntent(finalTranscript, rooms, selectedRoom);
      setParsedIntent(intent);
      if (intent) {
        doExecute(intent);
      } else {
        setStatusText("Couldn't interpret that command.");
        appendLog(`Parser could not understand: ${finalTranscript}`);
      }
    } else {
      // Start
      if (!isSpeechSupported()) {
        setStatusText('Speech recognition not supported. Use Chrome or Edge.');
        appendLog('Speech not supported in this browser.');
        return;
      }

      setTranscript('');
      setParsedIntent(null);
      setStatusText('Listening...');

      const rec = createSpeechRecognizer({
        onUpdate: (partial) => {
          setTranscript(partial);
          setParsedIntent(parseIntent(partial, rooms, selectedRoom));
        },
        onError: (msg) => {
          setIsRecording(false);
          setStatusText(msg);
          appendLog(`Speech error: ${msg}`);
        },
        onEnd: () => {
          setIsRecording(false);
        },
      });

      if (rec) {
        recognizerRef.current = rec;
        rec.start();
        setIsRecording(true);
        appendLog('Started listening.');
      }
    }
  }, [isRecording, transcript, rooms, selectedRoom, doExecute, appendLog]);

  const executeManual = useCallback(
    (action) => {
      const intent = {
        originalTranscript: action.replace(/_/g, ' '),
        action,
        targetRoom: selectedRoom?.name || null,
        contentQuery: null,
        volumeValue: null,
        scope: 'single_room',
      };
      setParsedIntent(intent);
      setTranscript('');
      doExecute(intent);
    },
    [selectedRoom, doExecute]
  );

  const householdName = households.find((h) => h.id === selectedHouseholdId)?.name || 'No household selected';
  const speechSupported = isSpeechSupported();

  return (
    <div className="app-bg">
      <div className="app-container">
        <header className="app-header">
          <h1>Sonos Voice Remote</h1>
          <p className="subtitle">Tap once to talk. Tap again to send the command to Sonos.</p>
        </header>

        {/* Controller Card */}
        <Card title="Sonos Controller">
          <div className="card-row">
            <div>
              <div className="card-title-text">Web Sonos Controller</div>
              <div className="status-badge">{connectionStatus.replace(/_/g, ' ')}</div>
            </div>
            <div className="card-actions">
              {connectionStatus === 'auth_required' ? (
                <a href="/sonos/oauth/start/web" className="btn btn-orange">
                  Sign In
                </a>
              ) : (
                <button className="btn btn-orange" onClick={refreshRooms}>
                  Refresh
                </button>
              )}
              <button className="btn btn-outline" onClick={handleDisconnect}>
                Disconnect
              </button>
            </div>
          </div>
          <p className="detail-text">{statusText}</p>

          {households.length > 0 && (
            <>
              <div className="label">Selected household</div>
              <div className="value-text">{householdName}</div>
              {households.length > 1 && (
                <select
                  className="select-input"
                  value={selectedHouseholdId}
                  onChange={(e) => handleHouseholdChange(e.target.value)}
                >
                  {households.map((h) => (
                    <option key={h.id} value={h.id}>
                      {h.name}
                    </option>
                  ))}
                </select>
              )}
            </>
          )}
        </Card>

        {/* Rooms Card */}
        <Card title="Rooms">
          <div className="card-row">
            <div className="label">Selected room</div>
            <button className="btn btn-orange-sm" onClick={refreshRooms}>
              Refresh
            </button>
          </div>
          <div className="value-text">{selectedRoom?.name || 'No room selected'}</div>
          {rooms.length > 1 && (
            <select
              className="select-input"
              value={selectedRoomId}
              onChange={(e) => {
                setSelectedRoomId(e.target.value);
                const room = rooms.find((r) => r.id === e.target.value);
                if (room) appendLog(`Selected room: ${room.name}`);
              }}
            >
              {rooms.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name}
                </option>
              ))}
            </select>
          )}
          <div className="room-chips">
            {rooms.map((room) => (
              <button
                key={room.id}
                className={`room-chip ${room.id === selectedRoomId ? 'selected' : ''}`}
                onClick={() => {
                  setSelectedRoomId(room.id);
                  appendLog(`Selected room: ${room.name}`);
                }}
              >
                <span className={`dot ${room.isPlaying ? 'playing' : ''}`} />
                {room.name}
              </button>
            ))}
          </div>
          <p className="footnote">{rooms.length ? rooms.map((r) => r.name).join(', ') : 'No Sonos rooms discovered yet.'}</p>
        </Card>

        {/* Microphone Card */}
        <Card title="Tap To Talk">
          <div className="mic-section">
            <button
              className={`mic-btn ${isRecording ? 'recording' : ''}`}
              onClick={toggleRecording}
              disabled={!speechSupported && !isRecording}
              aria-label={isRecording ? 'Stop recording' : 'Start recording'}
            >
              <div className="mic-ring" />
              <div className="mic-circle">
                {isRecording ? (
                  <svg viewBox="0 0 24 24" width="44" height="44" fill="white">
                    <rect x="6" y="6" width="12" height="12" rx="2" />
                  </svg>
                ) : (
                  <svg viewBox="0 0 24 24" width="44" height="44" fill="white">
                    <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3zM19 10v2a7 7 0 0 1-14 0v-2H3v2a9 9 0 0 0 8 8.94V23h2v-2.06A9 9 0 0 0 21 12v-2h-2z" />
                  </svg>
                )}
              </div>
            </button>
            <div className="mic-label">{isRecording ? 'Listening live...' : 'Ready for a command'}</div>
            {!speechSupported && (
              <div className="footnote">Speech recognition requires Chrome or Edge.</div>
            )}
          </div>
        </Card>

        {/* Transcript Card */}
        <Card title="Live Transcript">
          <p className={`transcript-text ${transcript ? '' : 'placeholder'}`}>
            {transcript || 'Your speech will appear here in real time.'}
          </p>
        </Card>

        {/* Parsed Intent Card */}
        <Card title="Parsed Intent">
          <p className="detail-text">{intentSummary(parsedIntent)}</p>
        </Card>

        {/* Execution Status Card */}
        <Card title="Execution Status">
          <div className="status-row">
            <div className={`status-capsule ${isExecuting ? 'executing' : 'idle'}`} />
            <p className="detail-text">{statusText}</p>
          </div>
        </Card>

        {/* Manual Controls Card */}
        <Card title="Manual Controls">
          <div className="controls-grid">
            <button className="ctrl-btn orange" onClick={() => executeManual('pause')}>
              <PauseIcon /> Pause
            </button>
            <button className="ctrl-btn green" onClick={() => executeManual('resume')}>
              <PlayIcon /> Resume
            </button>
            <button className="ctrl-btn blue" onClick={() => executeManual('skip')}>
              <SkipIcon /> Skip
            </button>
            <button className="ctrl-btn pink" onClick={() => executeManual('volume_up')}>
              <VolumeUpIcon /> Volume Up
            </button>
            <button className="ctrl-btn purple" onClick={() => executeManual('volume_down')}>
              <VolumeDownIcon /> Volume Down
            </button>
          </div>
        </Card>

        {/* Debug Log Card */}
        <Card title="Debug Log">
          {debugLog.length === 0 ? (
            <p className="log-empty">No activity yet.</p>
          ) : (
            debugLog.map((line, i) => (
              <p key={i} className="log-line">
                {line}
              </p>
            ))
          )}
        </Card>
      </div>
    </div>
  );
}

function Card({ title, children }) {
  return (
    <section className="card">
      <div className="card-label">{title.toUpperCase()}</div>
      {children}
    </section>
  );
}

function PauseIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
      <rect x="6" y="4" width="4" height="16" rx="1" />
      <rect x="14" y="4" width="4" height="16" rx="1" />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
      <polygon points="6,4 20,12 6,20" />
    </svg>
  );
}

function SkipIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
      <polygon points="4,4 16,12 4,20" />
      <rect x="17" y="4" width="3" height="16" rx="1" />
    </svg>
  );
}

function VolumeUpIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
      <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 8.5v7a4.5 4.5 0 0 0 2.5-3.5zM14 3.23v2.06a6.5 6.5 0 0 1 0 13.42v2.06A8.5 8.5 0 0 0 14 3.23z" />
    </svg>
  );
}

function VolumeDownIcon() {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
      <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 8.5v7a4.5 4.5 0 0 0 2.5-3.5z" />
    </svg>
  );
}
