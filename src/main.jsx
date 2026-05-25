import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.jsx';
import ErrorBoundary from './ErrorBoundary.jsx';
import PrivacyPage from './PrivacyPage.jsx';
import './App.css';

const root = ReactDOM.createRoot(document.getElementById('root'));
const isPrivacy = window.location.pathname === '/privacy';

root.render(
  <React.StrictMode>
    <ErrorBoundary>{isPrivacy ? <PrivacyPage /> : <App />}</ErrorBoundary>
  </React.StrictMode>
);
