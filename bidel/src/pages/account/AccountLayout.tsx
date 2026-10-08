import { Heart, LayoutGrid, List, MessageSquare, Settings, User } from 'lucide-react'
import { NavLink, Route, Routes, useNavigate } from 'react-router-dom'
import { useStore } from '../../features/AppStore'
import { cx } from '../../lib/format'
import { LoginCard } from '../LoginPage'
import { NotFoundPage } from '../NotFoundPage'
import { MessagesPage } from './MessagesPage'
import { MyListingsPage } from './MyListingsPage'
import { OverviewPage } from './OverviewPage'
import { ProfilePage } from './ProfilePage'
import { SavedPage } from './SavedPage'
import { SettingsPage } from './SettingsPage'

const tabs = [
  { to: '/konto', label: 'Översikt', icon: LayoutGrid, end: true },
  { to: '/konto/annonser', label: 'Mina annonser', icon: List },
  { to: '/konto/sparade', label: 'Sparade annonser', icon: Heart },
  { to: '/konto/meddelanden', label: 'Meddelanden', icon: MessageSquare },
  { to: '/konto/profil', label: 'Profil', icon: User },
  { to: '/konto/installningar', label: 'Inställningar', icon: Settings },
]

export function AccountLayout() {
  const { loggedIn, login, profile, unreadCount } = useStore()
  const navigate = useNavigate()

  if (!loggedIn) {
    return (
      <div className="container-page flex justify-center py-16">
        <div className="w-full max-w-sm">
          <LoginCard onLogin={login} />
        </div>
      </div>
    )
  }

  return (
    <div className="container-page pt-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <p className="eyebrow">Mitt konto</p>
          <h1 className="mt-1 text-2xl font-semibold tracking-tight">{profile.displayName}</h1>
        </div>
        <button type="button" className="btn-primary hidden sm:inline-flex" onClick={() => navigate('/salj/ny')}>
          Lägg upp annons
        </button>
      </div>
      <div className="mt-6 grid gap-6 lg:grid-cols-[220px_1fr] lg:gap-10">
        <nav aria-label="Kontomeny" className="-mx-4 overflow-x-auto border-b border-gray-200 px-4 [scrollbar-width:none] lg:mx-0 lg:border-0 lg:px-0">
          <ul className="flex gap-1 lg:flex-col">
            {tabs.map((t) => (
              <li key={t.to} className="shrink-0">
                <NavLink
                  to={t.to}
                  end={t.end}
                  className={({ isActive }) =>
                    cx(
                      'flex items-center gap-2.5 whitespace-nowrap px-3 py-2.5 text-sm font-medium transition-colors lg:rounded-md',
                      isActive ? 'border-b-2 border-brand-700 text-brand-700 lg:border-0 lg:bg-brand-50' : 'border-b-2 border-transparent text-gray-700 hover:text-ink lg:border-0 lg:hover:bg-gray-50',
                    )
                  }
                >
                  <t.icon className="hidden h-4 w-4 lg:block" aria-hidden />
                  {t.label}
                  {t.to === '/konto/meddelanden' && unreadCount > 0 && <span className="ml-auto rounded-full bg-brand-700 px-1.5 text-[11px] text-white">{unreadCount}</span>}
                </NavLink>
              </li>
            ))}
          </ul>
        </nav>
        <div className="min-w-0">
          <Routes>
            <Route index element={<OverviewPage />} />
            <Route path="annonser" element={<MyListingsPage />} />
            <Route path="sparade" element={<SavedPage />} />
            <Route path="meddelanden" element={<MessagesPage />} />
            <Route path="meddelanden/:cid" element={<MessagesPage />} />
            <Route path="profil" element={<ProfilePage />} />
            <Route path="installningar" element={<SettingsPage />} />
            <Route path="*" element={<NotFoundPage />} />
          </Routes>
        </div>
      </div>
    </div>
  )
}
