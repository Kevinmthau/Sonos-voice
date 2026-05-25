import { useState, useCallback } from 'react';
import { intentSummary } from './parsing/intentParser.js';
import { useDebugLog } from './hooks/useDebugLog.js';
import { useSonosConnection } from './hooks/useSonosConnection.js';
import { useVoiceCommand } from './hooks/useVoiceCommand.js';

const CONSENT_KEY = 'voice_consent_v1';

export default function App() {
  const [consentGranted, setConsentGranted] = useState(
    typeof window !== 'undefined' && window.localStorage?.getItem(CONSENT_KEY) === 'yes'
  );
  const { debugLog, appendLog } = useDebugLog();
  const {
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
  } = useSonosConnection({ appendLog });
  const {
    executeManual,
    isExecuting,
    isRecording,
    parsedIntent,
    speechSupported,
    toggleRecording,
    transcript,
  } = useVoiceCommand({
    appendLog,
    consentGranted,
    refreshRooms,
    rooms,
    selectedRoom,
    setStatusText,
  });

  const grantConsent = useCallback(() => {
    window.localStorage?.setItem(CONSENT_KEY, 'yes');
    setConsentGranted(true);
  }, []);

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
              onChange={(e) => handleRoomChange(e.target.value)}
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
                onClick={() => handleRoomChange(room.id)}
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
              disabled={(!speechSupported || !consentGranted) && !isRecording}
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
              <div className="footnote">
                Speech recognition needs Chrome or Edge on desktop or Android. Safari and Firefox
                do not support the Web Speech API. On iPhone, use the native app instead.
              </div>
            )}
          </div>
        </Card>

        {!consentGranted && (
          <Card title="Before You Talk">
            <p className="detail-text">
              When you tap the mic, your voice is captured in your browser and sent to your
              browser's speech-to-text service (Google for Chrome, Microsoft for Edge) for
              transcription. The text is then turned into a Sonos command. We do not store
              audio recordings.
            </p>
            <div className="card-actions consent-actions">
              <button className="btn btn-orange" onClick={grantConsent}>
                I understand
              </button>
              <a href="/privacy" className="btn btn-outline">Read full privacy notice</a>
            </div>
          </Card>
        )}

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

        <footer className="footnote app-footer">
          <a href="/privacy" className="footer-link">Privacy notice</a>
        </footer>
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
