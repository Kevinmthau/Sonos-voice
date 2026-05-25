export default function PrivacyPage() {
  return (
    <div className="app-bg">
      <div className="app-container">
        <header className="app-header">
          <h1>Privacy</h1>
          <p className="subtitle">How Sonos Voice Remote handles your data.</p>
        </header>

        <section className="card">
          <div className="card-label">WHAT WE COLLECT</div>
          <p className="detail-text">
            When you tap the microphone, this app captures your voice and sends it to your
            browser's built-in speech recognition service (Google Chrome or Microsoft Edge)
            for transcription. The transcribed text is then turned into a Sonos command.
          </p>
        </section>

        <section className="card">
          <div className="card-label">WHERE IT GOES</div>
          <p className="detail-text">
            Voice audio: sent to Google or Microsoft (depending on your browser) for
            transcription. We do not record or store audio on our servers.
          </p>
          <p className="detail-text">
            Sonos commands: sent through our server only to forward to the Sonos API, which
            controls your speakers. Your Sonos account token is stored in your browser
            (localStorage) and is used to authenticate API calls.
          </p>
          <p className="detail-text">
            iOS app: when transcription is set to "openai" mode, audio is sent to OpenAI for
            transcription and is not used for training under OpenAI's API data policy.
          </p>
        </section>

        <section className="card">
          <div className="card-label">RETENTION</div>
          <p className="detail-text">
            We do not store audio recordings or transcripts. Logs may contain Sonos request
            metadata (timestamps, household IDs) for up to 30 days for debugging.
          </p>
        </section>

        <section className="card">
          <div className="card-label">WHO RUNS THIS</div>
          <p className="detail-text">
            Sonos Voice Remote is a personal project, not an official Sonos product. For
            questions or to request data deletion, contact the operator who shared the URL
            with you.
          </p>
        </section>

        <section className="card">
          <div className="card-label">YOUR CONTROLS</div>
          <p className="detail-text">
            Use the Disconnect button on the home screen to revoke Sonos access locally and
            clear your stored token. To fully revoke access, also visit your Sonos account
            settings.
          </p>
          <div className="card-actions stacked-actions">
            <a href="/" className="btn btn-orange">Back to app</a>
          </div>
        </section>
      </div>
    </div>
  );
}
