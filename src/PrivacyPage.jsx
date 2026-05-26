export default function PrivacyPage() {
  return (
    <div className="app-bg">
      <main className="privacy-shell">
        <header className="privacy-header glass-panel">
          <h1>Privacy</h1>
          <p>How Sonos Voice Remote handles your data.</p>
        </header>

        <div className="privacy-stack">
          <section className="privacy-panel glass-panel">
            <h2 className="section-label">WHAT WE COLLECT</h2>
            <p>
              When you tap the microphone, this app captures your voice and sends it to your
              browser's built-in speech recognition service (Google Chrome or Microsoft Edge)
              for transcription. The transcribed text is then turned into a Sonos command.
            </p>
          </section>

          <section className="privacy-panel glass-panel">
            <h2 className="section-label">WHERE IT GOES</h2>
            <p>
              Voice audio: sent to Google or Microsoft (depending on your browser) for
              transcription. We do not record or store audio on our servers.
            </p>
            <p>
              Sonos commands: sent through our server only to forward to the Sonos API, which
              controls your speakers. Your Sonos account token is stored in your browser
              (localStorage) and is used to authenticate API calls.
            </p>
            <p>
              iOS app: when transcription is set to "openai" mode, audio is sent to OpenAI for
              transcription and is not used for training under OpenAI's API data policy.
            </p>
          </section>

          <section className="privacy-panel glass-panel">
            <h2 className="section-label">RETENTION</h2>
            <p>
              We do not store audio recordings or transcripts. Logs may contain Sonos request
              metadata (timestamps, household IDs) for up to 30 days for debugging.
            </p>
          </section>

          <section className="privacy-panel glass-panel">
            <h2 className="section-label">WHO RUNS THIS</h2>
            <p>
              Sonos Voice Remote is a personal project, not an official Sonos product. For
              questions or to request data deletion, contact the operator who shared the URL
              with you.
            </p>
          </section>

          <section className="privacy-panel glass-panel">
            <h2 className="section-label">YOUR CONTROLS</h2>
            <p>
              Use the Disconnect button on the home screen to revoke Sonos access locally and
              clear your stored token. To fully revoke access, also visit your Sonos account
              settings.
            </p>
            <div className="notice-actions">
              <a href="/" className="action-pill action-primary">Back to app</a>
            </div>
          </section>
        </div>
      </main>
    </div>
  );
}
