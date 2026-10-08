import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter, HashRouter } from 'react-router-dom'
import { App } from './App'
import { AppStoreProvider } from './features/AppStore'
import './styles/index.css'

// Static single-file builds (no server rewrites) use hash routing.
const Router = import.meta.env.VITE_HASH_ROUTER ? HashRouter : BrowserRouter

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Router>
      <AppStoreProvider>
        <App />
      </AppStoreProvider>
    </Router>
  </StrictMode>,
)
