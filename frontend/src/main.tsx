import { render } from 'solid-js/web';
import App from './App';
import './index.css';

// Clear session storage when page is about to refresh
window.addEventListener('beforeunload', () => {
    sessionStorage.clear();
    console.log('Session storage cleared on refresh');
});

render(() => <App />, document.getElementById('root')!);
