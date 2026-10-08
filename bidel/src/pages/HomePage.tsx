import { ArrowRight, CarFront, Recycle, Search } from 'lucide-react'
import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { CategoryIcon } from '../components/CategoryIcon'
import { ListingCard } from '../components/ListingCard'
import { RegLookup } from '../components/RegLookup'
import { VehicleSelects, type VehicleValue } from '../components/VehicleSelects'
import { categories } from '../data/categories'
import { useStore } from '../features/AppStore'
import { carLabel } from '../lib/fitment'
import { paramsFromFilters } from '../lib/search'

const popular = ['Audi A4 turbo', 'Volvo V70 strålkastare', 'Golf spegel', 'E90 bromsok', 'Saab 9-3 turbo']

export function HomePage() {
  const navigate = useNavigate()
  const { listings, myCar } = useStore()
  const [q, setQ] = useState('')
  const [vehicle, setVehicle] = useState<VehicleValue>({ make: '', model: '', year: '' })

  const search = (extra: Record<string, string> = {}) => {
    const p = paramsFromFilters({ q: q.trim(), make: vehicle.make, model: vehicle.model, year: vehicle.year, ...extra })
    navigate(`/bildelar?${p}`)
  }

  const latest = [...listings].filter((l) => l.status === 'active').sort((a, b) => b.createdAt.localeCompare(a.createdAt)).slice(0, 8)
  const counts = listings.reduce<Record<string, number>>((acc, l) => {
    if (l.status === 'active') acc[l.categoryId] = (acc[l.categoryId] ?? 0) + 1
    return acc
  }, {})

  return (
    <>
      {/* Hero + search */}
      <section className="border-b border-gray-200 bg-surface">
        <div className="container-page grid gap-8 py-10 sm:py-14 lg:grid-cols-[1fr_360px] lg:gap-12 lg:py-16">
          <div>
            <h1 className="text-[32px] font-bold leading-[1.1] tracking-tight sm:text-5xl">Hitta rätt begagnad bildel.</h1>
            <p className="mt-3 max-w-xl text-base leading-relaxed text-gray-600 sm:text-lg">Sök, jämför och hitta begagnade reservdelar för din bil – på ett och samma ställe.</p>

            <form
              role="search"
              className="mt-7 rounded-xl border border-gray-200 bg-white p-3 shadow-[0_1px_2px_rgba(0,0,0,0.04)] sm:p-4"
              onSubmit={(e) => {
                e.preventDefault()
                search()
              }}
            >
              <label htmlFor="hero-q" className="sr-only">
                Sök bildelar
              </label>
              <div className="relative">
                <Search className="pointer-events-none absolute left-3.5 top-1/2 h-5 w-5 -translate-y-1/2 text-gray-400" aria-hidden />
                <input
                  id="hero-q"
                  type="search"
                  value={q}
                  onChange={(e) => setQ(e.target.value)}
                  placeholder="Del, bil eller referensnummer – t.ex. Audi A4 turbo"
                  className="input h-12 pl-11 text-base"
                />
              </div>
              <div className="mt-3 grid gap-2 sm:grid-cols-[1fr_1fr_0.8fr_auto]">
                <VehicleSelects value={vehicle} onChange={setVehicle} labels={false} idPrefix="hero" className="contents" />
                <button type="submit" className="btn-primary h-10 sm:px-6">
                  Sök bildelar
                </button>
              </div>
            </form>
            {myCar && (
              <Link
                to={`/bildelar?${paramsFromFilters({ make: myCar.make, model: myCar.model, generation: myCar.generation ?? '' })}`}
                className="mt-4 flex items-center gap-2 rounded-lg border border-brand-200 bg-white px-4 py-3 text-sm hover:border-brand-500"
              >
                <CarFront className="h-5 w-5 shrink-0 text-brand-700" aria-hidden />
                <span className="min-w-0 flex-1">
                  Delar från samma modell som din <strong className="font-semibold">{carLabel(myCar)}</strong>
                </span>
                <ArrowRight className="h-4 w-4 shrink-0 text-brand-700" aria-hidden />
              </Link>
            )}
            <div className="mt-4 flex flex-wrap items-center gap-2 text-sm">
              <span className="text-gray-500">Populärt:</span>
              {popular.map((p) => (
                <Link key={p} to={`/bildelar?q=${encodeURIComponent(p)}`} className="rounded-full border border-gray-300 bg-white px-3 py-1 text-[13px] text-gray-700 hover:border-gray-400 hover:text-ink">
                  {p}
                </Link>
              ))}
            </div>
          </div>
          <div className="lg:pt-2">
            <RegLookup onVehicle={(v) => navigate(`/bildelar?${paramsFromFilters({ make: v.make, model: v.model, generation: v.generation, year: String(v.year) })}`)} />
          </div>
        </div>
      </section>

      {/* Categories */}
      <section className="container-page pt-12 sm:pt-16" aria-labelledby="kategorier">
        <div className="flex items-end justify-between gap-4">
          <h2 id="kategorier" className="text-xl font-semibold tracking-tight sm:text-2xl">
            Kategorier
          </h2>
          <Link to="/bildelar" className="text-sm font-medium text-brand-700 hover:underline">
            Utforska kategorier
          </Link>
        </div>
        <ul className="mt-5 grid grid-cols-2 gap-px overflow-hidden rounded-lg border border-gray-200 bg-gray-200 sm:grid-cols-3 lg:grid-cols-6">
          {categories.map((c) => (
            <li key={c.id} className="bg-white">
              <Link to={`/bildelar?category=${c.id}`} className="group flex h-full flex-col gap-3 p-4 transition-colors hover:bg-brand-50/60">
                <CategoryIcon id={c.id} className="h-6 w-6 text-brand-700" />
                <span>
                  <span className="block text-sm font-medium leading-snug text-ink">{c.name}</span>
                  <span className="mt-0.5 block text-xs text-gray-500">{counts[c.id] ?? 0} annonser</span>
                </span>
              </Link>
            </li>
          ))}
        </ul>
      </section>

      {/* Latest listings */}
      <section className="container-page pt-12 sm:pt-16" aria-labelledby="senaste">
        <div className="flex items-end justify-between gap-4">
          <div>
            <h2 id="senaste" className="text-xl font-semibold tracking-tight sm:text-2xl">
              Senaste annonserna
            </h2>
            <p className="mt-1 text-sm text-gray-500">Demonstrationsannonser – inga riktiga delar är till salu.</p>
          </div>
          <Link to="/bildelar?sort=newest" className="hidden text-sm font-medium text-brand-700 hover:underline sm:block">
            Se alla bildelar
          </Link>
        </div>
        <div className="mt-5 grid grid-cols-2 gap-3 sm:gap-4 md:grid-cols-3 lg:grid-cols-4">
          {latest.map((l) => (
            <ListingCard key={l.id} listing={l} />
          ))}
        </div>
        <Link to="/bildelar" className="btn-secondary mt-6 w-full sm:hidden">
          Se alla bildelar
        </Link>
      </section>

      {/* How it works */}
      <section className="container-page pt-16 sm:pt-20" aria-labelledby="sa-fungerar">
        <h2 id="sa-fungerar" className="text-xl font-semibold tracking-tight sm:text-2xl">
          Så fungerar Bidel
        </h2>
        <div className="mt-6 grid gap-4 md:grid-cols-2">
          <Journey
            title="För köpare"
            steps={[
              ['Sök', 'Fritext, fordon eller referensnummer.'],
              ['Jämför', 'Skick, pris, givarbil och avstånd.'],
              ['Kontakta', 'Ställ frågor direkt till säljaren.'],
              ['Köp', 'Ni kommer överens om betalning och leverans.'],
            ]}
            note="I prototypen fungerar sök, jämförelse och demochatt. Köp och betalning via Bidel finns inte ännu."
            cta={{ to: '/bildelar', label: 'Sök bildelar' }}
          />
          <Journey
            title="För säljare"
            steps={[
              ['Registrera', 'Privatperson eller företag.'],
              ['Lägg upp annons', 'Del, givarbil, skick, bilder och pris.'],
              ['Hitta köpare', 'Svara på frågor och avsluta affären.'],
            ]}
            note="Planen är att inte ta ut några säljavgifter under det första året efter lansering."
            cta={{ to: '/salj/ny', label: 'Sälj dina bildelar' }}
          />
        </div>
      </section>

      {/* Reuse */}
      <section className="container-page pt-16 sm:pt-20">
        <div className="grid gap-8 rounded-xl bg-surface p-6 sm:p-10 md:grid-cols-[auto_1fr_auto] md:items-center">
          <Recycle className="h-10 w-10 text-brand-700" strokeWidth={1.5} aria-hidden />
          <div>
            <h2 className="text-xl font-semibold tracking-tight">Bildelar får ett andra liv.</h2>
            <p className="mt-2 max-w-2xl text-sm leading-relaxed text-gray-600">
              En fungerande generator eller strålkastare från en skrotad bil kan hålla en annan bil på vägen i många år till. Att återanvända delar sparar pengar och
              material – och gör det enklare att laga i stället för att byta.
            </p>
          </div>
          <Link to="/om-bidel" className="btn-secondary justify-self-start">
            Om Bidel
            <ArrowRight className="h-4 w-4" />
          </Link>
        </div>
      </section>
    </>
  )
}

function Journey({ title, steps, note, cta }: { title: string; steps: [string, string][]; note: string; cta: { to: string; label: string } }) {
  return (
    <div className="card flex flex-col p-6">
      <h3 className="text-base font-semibold">{title}</h3>
      <ol className="mt-5 space-y-4">
        {steps.map(([s, d], i) => (
          <li key={s} className="flex gap-3.5">
            <span className="grid h-7 w-7 shrink-0 place-items-center rounded-full border border-brand-700 text-xs font-semibold text-brand-700">{i + 1}</span>
            <span>
              <span className="block text-sm font-semibold">{s}</span>
              <span className="block text-sm text-gray-600">{d}</span>
            </span>
          </li>
        ))}
      </ol>
      <p className="mt-6 border-t border-gray-100 pt-4 text-xs leading-relaxed text-gray-500">{note}</p>
      <Link to={cta.to} className="btn-secondary mt-4 self-start">
        {cta.label}
      </Link>
    </div>
  )
}
