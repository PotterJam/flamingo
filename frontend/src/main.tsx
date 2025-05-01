import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.tsx';
import './index.css';

// Clear session storage when page is about to refresh
window.addEventListener('beforeunload', () => {
    sessionStorage.clear();
    console.log('Session storage cleared on refresh');
});

ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
        <App />
    </React.StrictMode>
);
