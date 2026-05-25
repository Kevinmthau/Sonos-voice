import { useCallback, useRef, useState } from 'react';
import { parseIntent, intentSummary } from '../parsing/intentParser.js';
import { isSpeechSupported, createSpeechRecognizer } from '../services/speechRecognizer.js';
import { executeIntent } from '../services/sonosController.js';

export function useVoiceCommand({
  appendLog,
  consentGranted,
  refreshRooms,
  rooms,
  selectedRoom,
  setStatusText,
}) {
  const [isRecording, setIsRecording] = useState(false);
  const [transcript, setTranscript] = useState('');
  const [parsedIntent, setParsedIntent] = useState(null);
  const [isExecuting, setIsExecuting] = useState(false);
  const recognizerRef = useRef(null);

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
      } finally {
        setIsExecuting(false);
      }
    },
    [rooms, selectedRoom, refreshRooms, appendLog, setStatusText]
  );

  const toggleRecording = useCallback(() => {
    if (!consentGranted) {
      setStatusText('Please review and accept the voice notice below before recording.');
      return;
    }
    if (isRecording) {
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
  }, [isRecording, transcript, rooms, selectedRoom, doExecute, appendLog, consentGranted, setStatusText]);

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

  return {
    executeManual,
    isExecuting,
    isRecording,
    parsedIntent,
    speechSupported: isSpeechSupported(),
    toggleRecording,
    transcript,
  };
}
