import { Link } from 'react-router-dom'
import { Wordmark } from './Wordmark'

const cols = [
  {
    title: 'Marknadsplats',
    links: [
      { to: '/bildelar', label: 'Köpa bildelar' },
      { to: '/salj', label: 'Sälja bildelar' },
      { to: '/salj/ny', label: 'Lägg upp annons' },
      { to: '/bildelar?sort=newest', label: 'Senaste annonserna' },
    ],
  },
  {
    title: 'Bidel',
    links: [
      { to: '/om-bidel', label: 'Om Bidel' },
      { to: '/sa-fungerar-det', label: 'Så fungerar det' },
      { to: '/vanliga-fragor', label: 'Vanliga frågor' },
      { to: '/kontakt', label: 'Kontakta oss' },
    ],
  },
  {
    title: 'Villkor',
    links: [
      { to: '/integritetspolicy', label: 'Integritetspolicy' },
      { to: '/anvandarvillkor', label: 'Användarvillkor' },
      { to: '/cookies', label: 'Cookies' },
    ],
  },
]

export function Footer() {
  return (
    <footer className="mt-24 border-t border-gray-200 bg-surface">
      <div className="container-page grid gap-10 py-12 md:grid-cols-[1.4fr_repeat(3,1fr)]">
        <div className="max-w-xs">
          <Wordmark className="text-xl" />
          <p className="mt-3 text-sm leading-relaxed text-gray-600">Marknadsplatsen för begagnade bildelar. Sök, jämför och hitta reservdelar till din bil.</p>
          <p className="mt-4 text-xs leading-relaxed text-gray-500">
            Bidel är en prototyp under utveckling. Alla annonser, säljare och referensnummer på webbplatsen är påhittade demonstrationsexempel.
          </p>
        </div>
        {cols.map((c) => (
          <div key={c.title}>
            <h2 className="eyebrow">{c.title}</h2>
            <ul className="mt-3 space-y-2">
              {c.links.map((l) => (
                <li key={l.to}>
                  <Link to={l.to} className="text-sm text-gray-700 hover:text-brand-700 hover:underline">
                    {l.label}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
      <div className="border-t border-gray-200">
        <div className="container-page flex flex-col gap-2 py-5 text-xs text-gray-500 sm:flex-row sm:items-center sm:justify-between">
          <p>© {new Date().getFullYear()} Bidel. Prototyp – inte en publik tjänst.</p>
          <p>Priser anges i svenska kronor (SEK).</p>
        </div>
      </div>
    </footer>
  )
}
