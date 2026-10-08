import { CarFront, Menu, MessageSquare, Plus, User, X, Heart } from 'lucide-react'
import { useEffect, useState } from 'react'
import { Link, NavLink, useLocation } from 'react-router-dom'
import { useStore } from '../features/AppStore'
import { cx } from '../lib/format'
import { Wordmark } from './Wordmark'

const nav = [
  { to: '/bildelar', label: 'Köp bildelar' },
  { to: '/salj', label: 'Sälj bildelar' },
  { to: '/sa-fungerar-det', label: 'Så fungerar det' },
  { to: '/om-bidel', label: 'Om Bidel' },
]

export function Header() {
  const [open, setOpen] = useState(false)
  const { loggedIn, unreadCount, favorites, profile, myCar, setCarDialogOpen } = useStore()
  const location = useLocation()

  useEffect(() => setOpen(false), [location.pathname])
  useEffect(() => {
    document.body.style.overflow = open ? 'hidden' : ''
  }, [open])

  const linkClass = ({ isActive }: { isActive: boolean }) =>
    cx('relative px-3 py-2 text-sm font-medium transition-colors', isActive ? 'text-brand-700' : 'text-gray-700 hover:text-ink')

  return (
    <header className="sticky top-0 z-40 border-b border-gray-200 bg-white/95 backdrop-blur supports-[backdrop-filter]:bg-white/85">
      <div className="container-page flex h-16 items-center gap-4">
        <Wordmark className="text-[22px]" />
        <nav aria-label="Huvudmeny" className="ml-6 hidden items-center lg:flex">
          {nav.map((n) => (
            <NavLink key={n.to} to={n.to} className={linkClass}>
              {n.label}
            </NavLink>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-1.5">
          <button
            type="button"
            onClick={() => setCarDialogOpen(true)}
            className={cx('btn h-9 rounded-full border px-3 text-[13px]', myCar ? 'border-brand-200 bg-brand-50 text-brand-800 hover:border-brand-500' : 'border-gray-300 text-gray-700 hover:border-gray-400')}
            aria-label={myCar ? `Min bil: ${myCar.make} ${myCar.model} ${myCar.year}. Ändra` : 'Välj din bil'}
          >
            <CarFront className="h-4 w-4" aria-hidden />
            <span className="max-w-[9rem] truncate">{myCar ? `${myCar.make} ${myCar.model} · ${myCar.year}` : 'Min bil'}</span>
          </button>
          <Link to="/konto/sparade" className="btn-ghost hidden h-10 w-10 px-0 sm:inline-flex" aria-label={`Sparade annonser (${favorites.length})`}>
            <Heart className="h-5 w-5" />
          </Link>
          <Link to="/konto/meddelanden" className="btn-ghost relative hidden h-10 w-10 px-0 sm:inline-flex" aria-label={`Meddelanden${unreadCount ? `, ${unreadCount} olästa` : ''}`}>
            <MessageSquare className="h-5 w-5" />
            {unreadCount > 0 && <span className="absolute right-1.5 top-1.5 grid h-4 min-w-4 place-items-center rounded-full bg-brand-700 px-1 text-[10px] font-semibold text-white">{unreadCount}</span>}
          </Link>
          <Link to={loggedIn ? '/konto' : '/logga-in'} className="btn-ghost hidden md:inline-flex">
            <User className="h-4 w-4" />
            {loggedIn ? profile.displayName.split(' ')[0] : 'Logga in'}
          </Link>
          <Link to="/salj/ny" className="btn-primary hidden sm:inline-flex">
            <Plus className="h-4 w-4" />
            Lägg upp annons
          </Link>
          <button type="button" className="btn-ghost h-10 w-10 px-0 lg:hidden" aria-expanded={open} aria-controls="mobilmeny" aria-label={open ? 'Stäng meny' : 'Öppna meny'} onClick={() => setOpen((o) => !o)}>
            {open ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
          </button>
        </div>
      </div>
      {open && (
        <div id="mobilmeny" className="fixed inset-x-0 bottom-0 top-16 z-40 overflow-y-auto border-t border-gray-200 bg-white lg:hidden">
          <nav aria-label="Mobilmeny" className="container-page flex flex-col py-4">
            {nav.map((n) => (
              <NavLink key={n.to} to={n.to} className={({ isActive }) => cx('border-b border-gray-100 py-3.5 text-base font-medium', isActive ? 'text-brand-700' : 'text-ink')}>
                {n.label}
              </NavLink>
            ))}
            <NavLink to="/konto/sparade" className="border-b border-gray-100 py-3.5 text-base font-medium">
              Sparade annonser ({favorites.length})
            </NavLink>
            <NavLink to="/konto/meddelanden" className="border-b border-gray-100 py-3.5 text-base font-medium">
              Meddelanden {unreadCount > 0 && <span className="ml-1 rounded-full bg-brand-700 px-1.5 text-xs text-white">{unreadCount}</span>}
            </NavLink>
            <NavLink to={loggedIn ? '/konto' : '/logga-in'} className="border-b border-gray-100 py-3.5 text-base font-medium">
              {loggedIn ? 'Mitt konto' : 'Logga in'}
            </NavLink>
            <Link to="/salj/ny" className="btn-primary btn-lg mt-6">
              <Plus className="h-4 w-4" />
              Lägg upp annons
            </Link>
          </nav>
        </div>
      )}
    </header>
  )
}
