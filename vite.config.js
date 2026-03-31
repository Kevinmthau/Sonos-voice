import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
  },
  server: {
    proxy: {
      '/api/sonos': 'http://localhost:8888',
      '/sonos/oauth': 'http://localhost:8888',
    },
  },
});
