const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

export function isSpeechSupported() {
  return !!SpeechRecognition;
}

export function createSpeechRecognizer({ onUpdate, onError, onEnd }) {
  if (!SpeechRecognition) {
    onError('Speech recognition is not supported in this browser. Use Chrome or Edge.');
    return null;
  }

  const recognition = new SpeechRecognition();
  recognition.continuous = true;
  recognition.interimResults = true;
  recognition.lang = 'en-US';

  recognition.onresult = (event) => {
    let transcript = '';
    for (let i = 0; i < event.results.length; i++) {
      transcript += event.results[i][0].transcript;
    }
    onUpdate(transcript);
  };

  recognition.onerror = (event) => {
    if (event.error === 'not-allowed') {
      onError('Microphone permission denied. Please allow microphone access.');
    } else if (event.error !== 'aborted') {
      onError(`Speech recognition error: ${event.error}`);
    }
  };

  recognition.onend = () => {
    onEnd();
  };

  return {
    start() {
      recognition.start();
    },
    stop() {
      recognition.stop();
    },
  };
}
