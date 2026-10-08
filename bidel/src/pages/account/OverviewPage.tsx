import { ArrowRight } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useStore } from '../../features/AppStore'
import { formatTime } from '../../lib/format'

export function OverviewPage() {
  const { myListings, favorites, conversations, unreadCount, getListing } = useStore()
  const active = myListings.filter((l) => l.status === 'active').length
  const sold = myListings.length - active
  const stats = [
    { label: 'Aktiva annonser', value: active, to: '/konto/annonser' },
    { label: 'Sålda', value: sold, to: '/konto/annonser' },
    { label: 'Sparade annonser', value: favorites.length, to: '/konto/sparade' },
    { label: 'Olästa meddelanden', value: unreadCount, to: '/konto/meddelanden' },
  ]
  return (
    <div className="space-y-8">
      <h2 className="sr-only">Översikt</h2>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {stats.map((s) => (
          <Link key={s.label} to={s.to} className="card p-4 transition-colors hover:border-gray-300">
            <p className="text-2xl font-semibold tabular-nums">{s.value}</p>
            <p className="mt-0.5 text-sm text-gray-600">{s.label}</p>
          </Link>
        ))}
      </div>

      <section>
        <div className="flex items-center justify-between">
          <h3 className="font-semibold">Senaste meddelanden</h3>
          <Link to="/konto/meddelanden" className="text-sm font-medium text-brand-700 hover:underline">
            Alla meddelanden
          </Link>
        </div>
        <ul className="mt-3 divide-y divide-gray-100 rounded-lg border border-gray-200">
          {conversations.slice(0, 3).map((c) => {
            const last = c.messages[c.messages.length - 1]
            return (
              <li key={c.id}>
                <Link to={`/konto/meddelanden/${c.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-gray-50">
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">
                      {c.withName} <span className="font-normal text-gray-500">· {getListing(c.listingId)?.title}</span>
                    </p>
                    <p className="truncate text-sm text-gray-600">{last?.text ?? 'Inga meddelanden ännu'}</p>
                  </div>
                  {last && <span className="shrink-0 text-xs text-gray-500">{formatTime(last.sentAt)}</span>}
                  {c.unread > 0 && <span className="h-2 w-2 shrink-0 rounded-full bg-brand-700" aria-label="Oläst" />}
                </Link>
              </li>
            )
          })}
          {!conversations.length && <li className="px-4 py-6 text-sm text-gray-500">Inga konversationer ännu.</li>}
        </ul>
      </section>

      <section className="rounded-lg bg-surface p-5">
        <h3 className="font-semibold">Har du fler delar att sälja?</h3>
        <p className="mt-1 text-sm text-gray-600">Annonser du skapar sparas i den här webbläsaren och visas under Mina annonser.</p>
        <Link to="/salj/ny" className="btn-primary mt-4">
          Lägg upp annons <ArrowRight className="h-4 w-4" />
        </Link>
      </section>
    </div>
  )
}
