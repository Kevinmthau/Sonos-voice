import React from 'react';

export default class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error('Sonos Voice Remote crashed:', error, info);
  }

  handleReload = () => {
    this.setState({ error: null });
    window.location.reload();
  };

  render() {
    if (!this.state.error) return this.props.children;

    return (
      <div className="app-bg">
        <main className="remote-shell">
          <section className="notice-panel glass-panel">
            <h1 className="section-label">SOMETHING WENT WRONG</h1>
            <p>
              The Sonos Voice Remote hit an unexpected error and couldn't continue. Try reloading the page.
              If it keeps happening, sign out and back in to Sonos.
            </p>
            <p className="compact-note">{String(this.state.error.message || this.state.error)}</p>
            <div className="notice-actions">
              <button className="action-pill action-primary" onClick={this.handleReload}>
                Reload
              </button>
            </div>
          </section>
        </main>
      </div>
    );
  }
}
