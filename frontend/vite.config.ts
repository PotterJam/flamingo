import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
    // Load env file based on `mode` in the current working directory.
    // Set the third parameter to '' to load all env regardless of the `VITE_` prefix.
    const env = loadEnv(mode, process.cwd(), '');

    return {
        plugins: [react(), tailwindcss()],
        server: {
            port: parseInt(env.PORT || '5173'),
            proxy: {
                '/ws': {
                    target: 'http://localhost:8080',
                    ws: true
                },
                '/create-room': {
                    target: 'http://localhost:8080'
                },
                '/api': {
                    target: 'http://localhost:8080'
                }
            }
        }
    };
});
