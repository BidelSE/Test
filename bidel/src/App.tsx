import { useEffect } from 'react'
import { Route, Routes, useLocation } from 'react-router-dom'
import { DemoBanner } from './components/DemoBanner'
import { Footer } from './components/Footer'
import { Header } from './components/Header'
import { MyCarDialog } from './components/MyCarDialog'
import { Toasts } from './components/Toasts'
import { BrowsePage } from './pages/BrowsePage'
import { HomePage } from './pages/HomePage'
import { ListingPage } from './pages/ListingPage'
import { NotFoundPage } from './pages/NotFoundPage'
import { AboutPage } from './pages/AboutPage'
import { AccountLayout } from './pages/account/AccountLayout'
import { ContactPage } from './pages/ContactPage'
import { FaqPage } from './pages/FaqPage'
import { HowItWorksPage } from './pages/HowItWorksPage'
import { LegalPage } from './pages/LegalPage'
import { LoginPage } from './pages/LoginPage'
import { SellerPage } from './pages/SellerPage'
import { SellFormPage } from './pages/SellFormPage'
import { SellLandingPage } from './pages/SellLandingPage'

function ScrollToTop() {
  const { pathname, hash } = useLocation()
  useEffect(() => {
    if (hash) {
      requestAnimationFrame(() => document.getElementById(hash.slice(1))?.scrollIntoView())
      return
    }
    window.scrollTo(0, 0)
  }, [pathname, hash])
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
          <Route path="/salj" element={<SellLandingPage />} />
          <Route path="/salj/ny" element={<SellFormPage />} />
          <Route path="/salj/redigera/:id" element={<SellFormPage />} />
          <Route path="/saljare/:id" element={<SellerPage />} />
          <Route path="/logga-in" element={<LoginPage />} />
          <Route path="/konto/*" element={<AccountLayout />} />
          <Route path="/om-bidel" element={<AboutPage />} />
          <Route path="/sa-fungerar-det" element={<HowItWorksPage />} />
          <Route path="/vanliga-fragor" element={<FaqPage />} />
          <Route path="/kontakt" element={<ContactPage />} />
          <Route path="/integritetspolicy" element={<LegalPage page="integritet" />} />
          <Route path="/anvandarvillkor" element={<LegalPage page="villkor" />} />
          <Route path="/cookies" element={<LegalPage page="cookies" />} />
          <Route path="*" element={<NotFoundPage />} />
        </Routes>
      </main>
      <Footer />
      <MyCarDialog />
      <Toasts />
    </div>
  )
}
