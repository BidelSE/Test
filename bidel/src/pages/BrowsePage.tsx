import { CarFront, Search, SlidersHorizontal, X, SearchX } from 'lucide-react'
import { useEffect, useId, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { Breadcrumbs } from '../components/Breadcrumbs'
import { EmptyState } from '../components/EmptyState'
import { Select } from '../components/Field'
import { ListingCard } from '../components/ListingCard'
import { VehicleSelects } from '../components/VehicleSelects'
import { categories, categoryById, cities, conditionLabel, conditions } from '../data/categories'
import { useStore } from '../features/AppStore'
import { cx, formatPrice } from '../lib/format'
import { carLabel } from '../lib/fitment'
import { applyFilters, countActiveFilters, emptyFilters, filtersFromParams, paramsFromFilters } from '../lib/search'
import type { CategoryId, ListingFilters, SortKey } from '../types'

const sortOptions: { id: SortKey; label: string }[] = [
  { id: 'relevance', label: 'Relevans' },
  { id: 'price-asc', label: 'Lägsta pris' },
  { id: 'price-desc', label: 'Högsta pris' },
  { id: 'newest', label: 'Senaste' },
]

export function BrowsePage() {
  const [params, setParams] = useSearchParams()
  const filters = useMemo(() => filtersFromParams(params), [params])
  const { listings, sellersById, myCar, setCarDialogOpen } = useStore()
  const results = useMemo(() => applyFilters(listings, filters, sellersById, myCar), [listings, filters, sellersById, myCar])
  const carActive = !!myCar && filters.make === myCar.make && filters.model === myCar.model && (!myCar.generation || filters.generation === myCar.generation)
  const [drawer, setDrawer] = useState(false)
  const [q, setQ] = useState(filters.q)
  const [pending, setPending] = useState(false)
  const first = useRef(true)

  useEffect(() => setQ(filters.q), [filters.q])
  useEffect(() => {
    if (first.current) {
      first.current = false
      return
    }
    setPending(true)
    const t = window.setTimeout(() => setPending(false), 180)
    return () => window.clearTimeout(t)
  }, [params])
  useEffect(() => {
    document.body.style.overflow = drawer ? 'hidden' : ''
    return () => {
      document.body.style.overflow = ''
    }
  }, [drawer])

  const update = (patch: Partial<ListingFilters>, replace = true) => setParams(paramsFromFilters({ ...filters, ...patch }), { replace })
  const activeCount = countActiveFilters(filters)
  const chips = buildChips(filters)
  const cat = filters.category ? categoryById[filters.category as CategoryId] : undefined
  const heading = cat ? cat.name : filters.q ? `Sökresultat för ”${filters.q}”` : 'Alla bildelar'

  return (
    <div className="container-page pt-6">
      <Breadcrumbs items={[{ label: 'Bidel', to: '/' }, { label: 'Bildelar', to: cat ? '/bildelar' : undefined }, ...(cat ? [{ label: cat.short }] : [])]} />
      <div className="mt-3 flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">{heading}</h1>
          <p className="mt-1 text-sm text-gray-600" aria-live="polite">
            {results.length} {results.length === 1 ? 'annons' : 'annonser'}
          </p>
        </div>
        <form
          role="search"
          className="relative w-full md:max-w-md"
          onSubmit={(e) => {
            e.preventDefault()
            update({ q: q.trim() }, false)
          }}
        >
          <label htmlFor="browse-q" className="sr-only">
            Sök bildelar
          </label>
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-gray-400" aria-hidden />
          <input id="browse-q" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Sök del, bil eller referensnummer" className="input h-11 pl-9 pr-20" />
          <button type="submit" className="btn-primary btn-sm absolute right-1.5 top-1/2 -translate-y-1/2">
            Sök
          </button>
        </form>
      </div>

      {/* My car */}
      <div className="mt-5 flex flex-wrap items-center gap-x-3 gap-y-2 rounded-lg border border-gray-200 bg-surface px-4 py-3 text-sm">
        <CarFront className="h-5 w-5 shrink-0 text-brand-700" aria-hidden />
        {myCar ? (
          <>
            <span className="min-w-0 flex-1 basis-[calc(100%-2.5rem)] sm:basis-0">
              <span className="text-gray-600">Min bil: </span>
              <strong className="font-semibold">{carLabel(myCar)}</strong>
              {!carActive && <span className="block text-xs text-gray-500 sm:inline sm:pl-2">Annonser från samma modell visas först.</span>}
            </span>
            {carActive ? (
              <button type="button" className="btn-secondary btn-sm" onClick={() => update({ make: '', model: '', generation: '', engine: '', year: '' })}>
                Visa alla bilar
              </button>
            ) : (
              <button type="button" className="btn-primary btn-sm" onClick={() => update({ make: myCar.make, model: myCar.model, generation: myCar.generation ?? '', engine: '', year: '' })}>
                Visa delar till min bil
              </button>
            )}
            <button type="button" className="text-xs font-medium text-gray-600 underline underline-offset-2 hover:text-ink" onClick={() => setCarDialogOpen(true)}>
              Ändra
            </button>
          </>
        ) : (
          <>
            <span className="min-w-0 flex-1 text-gray-700">Spara din bil så ser du vilka annonser som kommer från samma modell och motor.</span>
            <button type="button" className="btn-secondary btn-sm" onClick={() => setCarDialogOpen(true)}>
              Välj din bil
            </button>
          </>
        )}
      </div>

      {/* Category quick filter */}
      <div className="-mx-4 mt-5 overflow-x-auto px-4 [scrollbar-width:none] sm:mx-0 sm:px-0">
        <div className="flex gap-2 pb-1">
          <button type="button" onClick={() => update({ category: '' })} className={cx('chip h-8 shrink-0 px-3', !filters.category && 'border-ink bg-ink text-white')}>
            Alla
          </button>
          {categories.map((c) => (
            <button
              key={c.id}
              type="button"
              aria-pressed={filters.category === c.id}
              onClick={() => update({ category: filters.category === c.id ? '' : c.id })}
              className={cx('chip h-8 shrink-0 px-3 hover:border-gray-400', filters.category === c.id && 'border-ink bg-ink text-white hover:border-ink')}
            >
              {c.short}
            </button>
          ))}
        </div>
      </div>

      <div className="mt-6 grid gap-8 lg:grid-cols-[272px_1fr]">
        <aside className="hidden lg:block" aria-label="Filter">
          <div className="sticky top-20 max-h-[calc(100vh-6rem)] overflow-y-auto pb-6 pr-1">
            <FilterPanel filters={filters} update={update} />
          </div>
        </aside>

        <div>
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" className="btn-secondary lg:hidden" onClick={() => setDrawer(true)}>
              <SlidersHorizontal className="h-4 w-4" />
              Filter
              {activeCount > 0 && <span className="grid h-5 min-w-5 place-items-center rounded-full bg-brand-700 px-1 text-[11px] text-white">{activeCount}</span>}
            </button>
            <div className="ml-auto flex items-center gap-2">
              <label htmlFor="sort" className="text-sm text-gray-600">
                Sortera
              </label>
              <Select id="sort" value={filters.sort} onChange={(e) => update({ sort: e.target.value as SortKey }, false)} className="w-auto">
                {sortOptions.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.label}
                  </option>
                ))}
              </Select>
            </div>
          </div>

          {chips.length > 0 && (
            <div className="mt-4 flex flex-wrap items-center gap-2">
              {chips.map((c) => (
                <button key={c.key} type="button" onClick={() => update(c.clear)} className="chip h-8 gap-1.5 bg-brand-50 border-brand-200 text-brand-800 hover:border-brand-500" aria-label={`Ta bort filter ${c.label}`}>
                  {c.label}
                  <X className="h-3.5 w-3.5" aria-hidden />
                </button>
              ))}
              <button type="button" onClick={() => setParams(new URLSearchParams(), { replace: false })} className="ml-1 text-sm font-medium text-gray-600 underline underline-offset-2 hover:text-ink">
                Rensa alla
              </button>
            </div>
          )}

          <div className={cx('mt-5 transition-opacity duration-150', pending && 'opacity-50')} aria-busy={pending}>
            {results.length ? (
              <div className="grid grid-cols-2 gap-3 sm:gap-4 md:grid-cols-3">
                {results.map((l) => (
                  <ListingCard key={l.id} listing={l} />
                ))}
              </div>
            ) : (
              <EmptyState
                icon={<SearchX className="h-6 w-6" />}
                title="Inga annonser matchar din sökning"
                body="Prova att ta bort något filter, söka på ett bredare ord eller bara på märke och modell. Det finns bara ett trettiotal demoannonser i prototypen."
                action={
                  <button type="button" className="btn-secondary" onClick={() => setParams(new URLSearchParams())}>
                    Rensa alla filter
                  </button>
                }
              />
            )}
          </div>
        </div>
      </div>

      {/* Mobile filter drawer */}
      {drawer && (
        <div className="fixed inset-0 z-50 lg:hidden" role="dialog" aria-modal="true" aria-label="Filter">
          <div className="absolute inset-0 bg-black/40" onClick={() => setDrawer(false)} />
          <div className="absolute inset-y-0 right-0 flex w-full max-w-sm flex-col bg-white animate-slide-in">
            <div className="flex h-14 items-center justify-between border-b border-gray-200 px-4">
              <h2 className="text-base font-semibold">Filter</h2>
              <button type="button" className="btn-ghost h-9 w-9 px-0" aria-label="Stäng filter" onClick={() => setDrawer(false)}>
                <X className="h-5 w-5" />
              </button>
            </div>
            <div className="flex-1 overflow-y-auto p-4">
              <FilterPanel filters={filters} update={update} />
            </div>
            <div className="flex gap-2 border-t border-gray-200 p-4">
              <button type="button" className="btn-secondary flex-1" onClick={() => setParams(paramsFromFilters({ ...emptyFilters, q: filters.q, sort: filters.sort }), { replace: true })}>
                Rensa
              </button>
              <button type="button" className="btn-primary flex-[2]" onClick={() => setDrawer(false)}>
                Visa {results.length} annonser
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function FilterSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <fieldset className="border-b border-gray-200 py-5 first:pt-0 last:border-0">
      <legend className="mb-3 float-left w-full text-sm font-semibold">{title}</legend>
      <div className="clear-both space-y-3">{children}</div>
    </fieldset>
  )
}

function FilterPanel({ filters, update }: { filters: ListingFilters; update: (p: Partial<ListingFilters>) => void }) {
  const [priceMin, setPriceMin] = useState(filters.priceMin)
  const [priceMax, setPriceMax] = useState(filters.priceMax)
  const [part, setPart] = useState(filters.part)
  const [oem, setOem] = useState(filters.oem)
  const radioName = useId()
  useEffect(() => {
    setPriceMin(filters.priceMin)
    setPriceMax(filters.priceMax)
    setPart(filters.part)
    setOem(filters.oem)
  }, [filters.priceMin, filters.priceMax, filters.part, filters.oem])

  // Debounce free-text style filters so the URL is not rewritten on every key press.
  useEffect(() => {
    const t = window.setTimeout(() => {
      if (priceMin !== filters.priceMin || priceMax !== filters.priceMax || part !== filters.part || oem !== filters.oem) update({ priceMin, priceMax, part, oem })
    }, 350)
    return () => window.clearTimeout(t)
  }, [priceMin, priceMax, part, oem])

  return (
    <div>
      <FilterSection title="Fordon">
        <VehicleSelects
          idPrefix="f"
          show={['make', 'model', 'generation', 'engine', 'year']}
          value={{ make: filters.make, model: filters.model, generation: filters.generation, engine: filters.engine, year: filters.year }}
          onChange={(v) => update({ make: v.make, model: v.model, generation: v.generation ?? '', engine: v.engine ?? '', year: v.year })}
          className="space-y-3"
        />
      </FilterSection>
      <FilterSection title="Del">
        <div>
          <label htmlFor="f-cat" className="label">
            Kategori
          </label>
          <Select id="f-cat" value={filters.category} onChange={(e) => update({ category: e.target.value })}>
            <option value="">Alla kategorier</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </Select>
        </div>
        <div>
          <label htmlFor="f-part" className="label">
            Delens namn
          </label>
          <input id="f-part" className="input" value={part} onChange={(e) => setPart(e.target.value)} placeholder="t.ex. generator" />
        </div>
        <div>
          <label htmlFor="f-oem" className="label">
            OEM-/referensnummer
          </label>
          <input id="f-oem" className="input font-mono" value={oem} onChange={(e) => setOem(e.target.value)} placeholder="t.ex. 8E0 906" />
        </div>
      </FilterSection>
      <FilterSection title="Pris (kr)">
        <div className="grid grid-cols-2 gap-2">
          <div>
            <label htmlFor="f-min" className="sr-only">
              Lägsta pris
            </label>
            <input id="f-min" className="input" inputMode="numeric" value={priceMin} onChange={(e) => setPriceMin(e.target.value.replace(/\D/g, ''))} placeholder="Från" />
          </div>
          <div>
            <label htmlFor="f-max" className="sr-only">
              Högsta pris
            </label>
            <input id="f-max" className="input" inputMode="numeric" value={priceMax} onChange={(e) => setPriceMax(e.target.value.replace(/\D/g, ''))} placeholder="Till" />
          </div>
        </div>
      </FilterSection>
      <FilterSection title="Skick">
        {conditions.map((c) => (
          <label key={c.id} className="flex cursor-pointer items-center gap-2.5 text-sm">
            <input
              type="checkbox"
              className="h-4 w-4 rounded border-gray-300 accent-brand-700"
              checked={filters.conditions.includes(c.id)}
              onChange={(e) => update({ conditions: e.target.checked ? [...filters.conditions, c.id] : filters.conditions.filter((x) => x !== c.id) })}
            />
            {c.label}
          </label>
        ))}
      </FilterSection>
      <FilterSection title="Säljare">
        {([
          ['', 'Alla säljare'],
          ['private', 'Privatpersoner'],
          ['professional', 'Företag och bildemonteringar'],
        ] as const).map(([v, label]) => (
          <label key={v} className="flex cursor-pointer items-center gap-2.5 text-sm">
            <input type="radio" name={`seller-${radioName}`} className="h-4 w-4 accent-brand-700" checked={filters.sellerType === v} onChange={() => update({ sellerType: v })} />
            {label}
          </label>
        ))}
      </FilterSection>
      <FilterSection title="Plats och leverans">
        <div>
          <label htmlFor="f-city" className="label">
            Ort
          </label>
          <Select id="f-city" value={filters.city} onChange={(e) => update({ city: e.target.value })}>
            <option value="">Hela Sverige</option>
            {cities.map((c) => (
              <option key={c}>{c}</option>
            ))}
          </Select>
        </div>
        <label className="flex cursor-pointer items-center gap-2.5 text-sm">
          <input type="checkbox" className="h-4 w-4 rounded accent-brand-700" checked={filters.shipping} onChange={(e) => update({ shipping: e.target.checked })} />
          Kan skickas
        </label>
      </FilterSection>
    </div>
  )
}

function buildChips(f: ListingFilters) {
  const chips: { key: string; label: string; clear: Partial<ListingFilters> }[] = []
  if (f.q) chips.push({ key: 'q', label: `”${f.q}”`, clear: { q: '' } })
  if (f.make) chips.push({ key: 'make', label: f.make, clear: { make: '', model: '', generation: '', engine: '' } })
  if (f.model) chips.push({ key: 'model', label: f.model, clear: { model: '', generation: '', engine: '' } })
  if (f.generation) chips.push({ key: 'gen', label: f.generation, clear: { generation: '' } })
  if (f.engine) chips.push({ key: 'engine', label: f.engine, clear: { engine: '' } })
  if (f.year) chips.push({ key: 'year', label: `År ${f.year}`, clear: { year: '' } })
  if (f.category) chips.push({ key: 'cat', label: categoryById[f.category as CategoryId]?.short ?? f.category, clear: { category: '' } })
  if (f.part) chips.push({ key: 'part', label: `Del: ${f.part}`, clear: { part: '' } })
  if (f.oem) chips.push({ key: 'oem', label: `Ref: ${f.oem}`, clear: { oem: '' } })
  if (f.priceMin) chips.push({ key: 'min', label: `Från ${formatPrice(+f.priceMin)}`, clear: { priceMin: '' } })
  if (f.priceMax) chips.push({ key: 'max', label: `Till ${formatPrice(+f.priceMax)}`, clear: { priceMax: '' } })
  f.conditions.forEach((c) => chips.push({ key: `c-${c}`, label: conditionLabel[c], clear: { conditions: f.conditions.filter((x) => x !== c) } }))
  if (f.sellerType) chips.push({ key: 'st', label: f.sellerType === 'private' ? 'Privatpersoner' : 'Företag', clear: { sellerType: '' } })
  if (f.city) chips.push({ key: 'city', label: f.city, clear: { city: '' } })
  if (f.shipping) chips.push({ key: 'ship', label: 'Kan skickas', clear: { shipping: false } })
  return chips
}
