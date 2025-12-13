import { defineConfig } from 'vite';
import solidPlugin from 'vite-plugin-solid';
import tailwindcss from '@tailwindcss/vite';
import path from 'path';

// https://vite.dev/config/
export default defineConfig({
    plugins: [solidPlugin(), tailwindcss()],
    server: {
        port: 3000,
        proxy: {
            '/api': {
                target: 'http://localhost:8080',
                changeOrigin: true,
                secure: false,
            },
            '/create-room': {
                target: 'http://localhost:8080',
                changeOrigin: true,
                secure: false,
            },
            '/game': {
                target: 'ws://localhost:8080',
                ws: true,
                changeOrigin: true,
                secure: false,
            },
        },
    },
    build: {
        target: 'esnext',
    },
    resolve: {
        alias: {
            '@': path.resolve(__dirname, './src'),
            '~': path.resolve(__dirname, './src'),
        },
    },
});
