import { useCallback, useState } from 'react';

function makeLogLine(msg) {
  const now = new Date();
  const ts = now.toLocaleTimeString('en-US', { hour12: false });
  return `[${ts}] ${msg}`;
}

export function useDebugLog(limit = 8) {
  const [debugLog, setDebugLog] = useState([]);

  const appendLog = useCallback(
    (msg) => {
      const line = makeLogLine(msg);
      setDebugLog((prev) => [line, ...prev].slice(0, limit));
    },
    [limit]
  );

  return { debugLog, appendLog };
}
