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
        <div className="app-container">
          <section className="card">
            <div className="card-label">SOMETHING WENT WRONG</div>
            <p className="detail-text">
              The Sonos Voice Remote hit an unexpected error and couldn't continue. Try reloading the page.
              If it keeps happening, sign out and back in to Sonos.
            </p>
            <p className="footnote">{String(this.state.error.message || this.state.error)}</p>
            <div className="card-actions stacked-actions">
              <button className="btn btn-orange" onClick={this.handleReload}>
                Reload
              </button>
            </div>
          </section>
        </div>
      </div>
    );
  }
}
