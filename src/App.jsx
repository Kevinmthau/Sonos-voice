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
  const [detailsOpen, setDetailsOpen] = useState(false);
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

  const isAuthRequired = connectionStatus === 'auth_required';
  const roomSummary = rooms.length
    ? rooms.map((room) => room.name).join(', ')
    : 'No Sonos rooms discovered yet.';
  const microphoneLabel = isRecording ? 'Listening live...' : 'Ready for a command';

  return (
    <div className="app-bg">
      <main className="remote-shell" aria-label="Sonos voice remote">
        <header className="top-bar glass-panel">
          <div className="brand-lockup">
            <div className="app-mark" aria-hidden="true">
              <SpeakerIcon />
            </div>
            <div>
              <h1>Sonos Voice</h1>
              <div className={`connection-line status-${statusClass(connectionStatus)}`}>
                <span className="connection-dot" />
                <span>{connectionLabel(connectionStatus)}</span>
              </div>
            </div>
          </div>

          <div className="top-actions">
            {isAuthRequired ? (
              <a href="/sonos/oauth/start/web" className="action-pill action-primary">
                <SignInIcon />
                <span>Sign In</span>
              </a>
            ) : (
              <button className="action-pill action-primary" onClick={refreshRooms}>
                <RefreshIcon />
                <span>Refresh</span>
              </button>
            )}
            {!isAuthRequired && (
              <button className="icon-button" onClick={handleDisconnect} aria-label="Disconnect" title="Disconnect">
                <PowerIcon />
              </button>
            )}
          </div>
        </header>

        <section className="room-panel glass-panel" aria-labelledby="selected-room-heading">
          <div className="room-heading">
            <div>
              <p className="section-label">Selected Room</p>
              <h2 id="selected-room-heading">{selectedRoom?.name || 'No room selected'}</h2>
            </div>
            {rooms.length > 1 && (
              <select
                className="select-input room-select"
                value={selectedRoomId}
                onChange={(e) => handleRoomChange(e.target.value)}
                aria-label="Room"
              >
                {rooms.map((room) => (
                  <option key={room.id} value={room.id}>
                    {room.name}
                  </option>
                ))}
              </select>
            )}
          </div>

          {rooms.length > 0 ? (
            <div className="room-chips" aria-label="Available rooms">
              {rooms.map((room) => (
                <button
                  key={room.id}
                  className={`room-chip ${room.id === selectedRoomId ? 'selected' : ''}`}
                  onClick={() => handleRoomChange(room.id)}
                >
                  <span className={`dot ${room.isPlaying ? 'playing' : ''}`} />
                  <span>{room.name}</span>
                </button>
              ))}
            </div>
          ) : (
            <p className="compact-note">{roomSummary}</p>
          )}
        </section>

        <section className="voice-stage glass-panel" aria-labelledby="voice-heading">
          <button
            className={`mic-button ${isRecording ? 'recording' : ''}`}
            onClick={toggleRecording}
            disabled={(!speechSupported || !consentGranted) && !isRecording}
            aria-label={isRecording ? 'Stop recording' : 'Start recording'}
          >
            <span className="mic-halo" />
            <span className="mic-core">{isRecording ? <StopIcon /> : <MicIcon />}</span>
          </button>

          <div className="voice-copy">
            <h2 id="voice-heading">{microphoneLabel}</h2>
            <p>{statusText}</p>
            {!speechSupported && (
              <p className="compact-note">
                Speech recognition needs Chrome or Edge on desktop or Android. Safari and Firefox
                do not support the Web Speech API. On iPhone, use the native app instead.
              </p>
            )}
          </div>
        </section>

        <section className="transport-panel glass-panel" aria-label="Playback controls">
          <div className="transport-primary">
            <button className="transport-button" onClick={() => executeManual('pause')}>
              <PauseIcon />
              <span>Pause</span>
            </button>
            <button className="transport-button primary" onClick={() => executeManual('resume')}>
              <PlayIcon />
              <span>Resume</span>
            </button>
            <button className="transport-button" onClick={() => executeManual('skip')}>
              <SkipIcon />
              <span>Skip</span>
            </button>
          </div>
          <div className="transport-secondary">
            <button className="volume-button" onClick={() => executeManual('volume_down')}>
              <VolumeDownIcon />
              <span>Volume Down</span>
            </button>
            <button className="volume-button" onClick={() => executeManual('volume_up')}>
              <VolumeUpIcon />
              <span>Volume Up</span>
            </button>
          </div>
        </section>

        {!consentGranted && (
          <section className="notice-panel glass-panel" aria-labelledby="voice-notice-heading">
            <h2 id="voice-notice-heading">Before You Talk</h2>
            <p>
              When you tap the mic, your voice is captured in your browser and sent to your
              browser's speech-to-text service (Google for Chrome, Microsoft for Edge) for
              transcription. The text is then turned into a Sonos command. We do not store
              audio recordings.
            </p>
            <div className="notice-actions">
              <button className="action-pill action-primary" onClick={grantConsent}>
                I understand
              </button>
              <a href="/privacy" className="action-pill action-quiet">
                Read full privacy notice
              </a>
            </div>
          </section>
        )}

        <section className="details-panel glass-panel">
          <button
            className="details-toggle"
            onClick={() => setDetailsOpen((open) => !open)}
            aria-expanded={detailsOpen}
            aria-controls="advanced-details"
          >
            <span className="details-title">
              <DetailsIcon />
              <span>Details</span>
            </span>
            <span className="details-state">{detailsOpen ? 'Hide' : 'Show'}</span>
          </button>

          {detailsOpen && (
            <div id="advanced-details" className="details-content">
              <DetailBlock title="Live Transcript">
                <p className={`transcript-text ${transcript ? '' : 'placeholder'}`}>
                  {transcript || 'Your speech will appear here in real time.'}
                </p>
              </DetailBlock>

              <DetailBlock title="Parsed Intent">
                <p>{intentSummary(parsedIntent)}</p>
              </DetailBlock>

              <DetailBlock title="Execution Status">
                <div className="status-row">
                  <span className={`status-capsule ${isExecuting ? 'executing' : 'idle'}`} />
                  <p>{statusText}</p>
                </div>
              </DetailBlock>

              <DetailBlock title="Household">
                <p className="strong-text">{householdName}</p>
                {households.length > 1 && (
                  <select
                    className="select-input"
                    value={selectedHouseholdId}
                    onChange={(e) => handleHouseholdChange(e.target.value)}
                    aria-label="Household"
                  >
                    {households.map((household) => (
                      <option key={household.id} value={household.id}>
                        {household.name}
                      </option>
                    ))}
                  </select>
                )}
                <p className="compact-note">{roomSummary}</p>
              </DetailBlock>

              <DetailBlock title="Debug Log">
                {debugLog.length === 0 ? (
                  <p className="log-empty">No activity yet.</p>
                ) : (
                  <div className="log-stack">
                    {debugLog.map((line, index) => (
                      <p key={`${line}-${index}`} className="log-line">
                        {line}
                      </p>
                    ))}
                  </div>
                )}
              </DetailBlock>
            </div>
          )}
        </section>

        <footer className="app-footer">
          <a href="/privacy">Privacy notice</a>
        </footer>
      </main>
    </div>
  );
}

function DetailBlock({ title, children }) {
  return (
    <section className="detail-block">
      <h3>{title}</h3>
      {children}
    </section>
  );
}

function connectionLabel(status) {
  switch (status) {
    case 'ready':
      return 'Connected';
    case 'auth_required':
      return 'Sign in required';
    case 'checking':
      return 'Checking';
    case 'unavailable':
      return 'Unavailable';
    default:
      return status.replace(/_/g, ' ');
  }
}

function statusClass(status) {
  return status.replace(/_/g, '-');
}

function SpeakerIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M6 3h12a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2Zm6 12.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7Zm0-1.8a1.7 1.7 0 1 1 0-3.4 1.7 1.7 0 0 1 0 3.4ZM8 6.4h8V5.1H8v1.3Z" />
    </svg>
  );
}

function SignInIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M10 5.2a6.8 6.8 0 1 0 0 13.6 6.8 6.8 0 0 0 0-13.6Zm0 2a4.8 4.8 0 1 1 0 9.6 4.8 4.8 0 0 1 0-9.6Zm7.6.8 1.4 1.4-1.8 1.8H23v2h-5.8L19 15l-1.4 1.4-4.2-4.2L17.6 8Z" />
    </svg>
  );
}

function RefreshIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M19.5 7.4A8.4 8.4 0 0 0 4 8.8h2.2a6.2 6.2 0 0 1 10.9-.5L14 11.4h7.6V3.8l-2.1 3.6ZM4.5 16.6A8.4 8.4 0 0 0 20 15.2h-2.2a6.2 6.2 0 0 1-10.9.5l3.1-3.1H2.4v7.6l2.1-3.6Z" />
    </svg>
  );
}

function PowerIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M13 3h-2v10h2V3Zm3.8 3.8-1.4 1.4a6 6 0 1 1-6.8 0L7.2 6.8a8 8 0 1 0 9.6 0Z" />
    </svg>
  );
}

function MicIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M12 2a4 4 0 0 0-4 4v5a4 4 0 0 0 8 0V6a4 4 0 0 0-4-4Zm7 8v1a7 7 0 0 1-6 6.93V21h3v2H8v-2h3v-3.07A7 7 0 0 1 5 11v-1h2v1a5 5 0 0 0 10 0v-1h2Z" />
    </svg>
  );
}

function StopIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="6" y="6" width="12" height="12" rx="2.5" />
    </svg>
  );
}

function PauseIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <rect x="6" y="4" width="4" height="16" rx="1" />
      <rect x="14" y="4" width="4" height="16" rx="1" />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M7 4.8v14.4L19 12 7 4.8Z" />
    </svg>
  );
}

function SkipIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="m4 5 10 7-10 7V5Zm12 0h3v14h-3V5Z" />
    </svg>
  );
}

function VolumeUpIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M3 9v6h4l5 5V4L7 9H3Zm13.5 3A4.5 4.5 0 0 0 14 8.5v7a4.5 4.5 0 0 0 2.5-3.5ZM14 3.2v2.1a6.5 6.5 0 0 1 0 13.4v2.1A8.5 8.5 0 0 0 14 3.2Z" />
    </svg>
  );
}

function VolumeDownIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M3 9v6h4l5 5V4L7 9H3Zm13.5 3A4.5 4.5 0 0 0 14 8.5v7a4.5 4.5 0 0 0 2.5-3.5Z" />
    </svg>
  );
}

function DetailsIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="M4 7h9a3 3 0 1 0 0-2H4v2Zm12-1a1 1 0 1 1 2 0 1 1 0 0 1-2 0ZM4 13h3a3 3 0 1 0 0-2H4v2Zm6-1a1 1 0 1 1 2 0 1 1 0 0 1-2 0Zm-6 7h9a3 3 0 1 0 0-2H4v2Zm12-1a1 1 0 1 1 2 0 1 1 0 0 1-2 0Z" />
    </svg>
  );
}
