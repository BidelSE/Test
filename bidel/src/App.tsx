import { useEffect } from 'react'
import { Route, Routes, useLocation } from 'react-router-dom'
import { DemoBanner } from './components/DemoBanner'
import { Footer } from './components/Footer'
import { Header } from './components/Header'
import { Toasts } from './components/Toasts'
import { BrowsePage } from './pages/BrowsePage'
import { HomePage } from './pages/HomePage'
import { ListingPage } from './pages/ListingPage'
import { NotFoundPage } from './pages/NotFoundPage'

function ScrollToTop() {
  const { pathname } = useLocation()
  useEffect(() => window.scrollTo(0, 0), [pathname])
  return null
}

export function App() {
  return (
    <div className="flex min-h-screen flex-col">
      <a href="#main" className="sr-only focus:not-sr-only focus:absolute focus:left-4 focus:top-4 focus:z-50 focus:rounded focus:bg-white focus:px-3 focus:py-2 focus:shadow">
        Hoppa till innehållet
      </a>
      <ScrollToTop />
      <DemoBanner />
      <Header />
      <main id="main" className="flex-1">
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/bildelar" element={<BrowsePage />} />
          <Route path="/annons/:id" element={<ListingPage />} />
          <Route path="*" element={<NotFoundPage />} />
        </Routes>
      </main>
      <Footer />
      <Toasts />
    </div>
  )
}
