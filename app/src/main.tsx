import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { registerSW } from 'virtual:pwa-register'
import './index.css'
import App from './App.tsx'

// Auto-update the PWA: when a new build is available, activate it and reload
// once so the user always lands on the latest version. Also re-checks for a new
// service worker every time the app is opened/refreshed and hourly while open.
const updateSW = registerSW({
  immediate: true,
  onNeedRefresh() {
    updateSW(true); // skip waiting + reload to the new version
  },
  onRegisteredSW(_swUrl, registration) {
    if (!registration) return;
    // check for updates on focus/visibility and hourly
    const check = () => registration.update().catch(() => {});
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') check();
    });
    window.addEventListener('focus', check);
    setInterval(check, 60 * 60 * 1000);
  },
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
