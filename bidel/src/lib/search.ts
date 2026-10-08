import { categoryById } from '../data/categories'
import type { Condition, Listing, ListingFilters, Seller, SellerType, SortKey } from '../types'

export const emptyFilters: ListingFilters = {
  q: '',
  make: '',
  model: '',
  generation: '',
  engine: '',
  year: '',
  category: '',
  part: '',
  oem: '',
  priceMin: '',
  priceMax: '',
  conditions: [],
  sellerType: '',
  city: '',
  shipping: false,
  sort: 'relevance',
}

const STRING_KEYS = ['q', 'make', 'model', 'generation', 'engine', 'year', 'category', 'part', 'oem', 'priceMin', 'priceMax', 'city'] as const

export function filtersFromParams(params: URLSearchParams): ListingFilters {
  const f: ListingFilters = { ...emptyFilters }
  for (const k of STRING_KEYS) f[k] = params.get(k) ?? ''
  f.conditions = (params.get('skick') ?? '').split(',').filter(Boolean) as Condition[]
  const st = params.get('saljare')
  f.sellerType = st === 'private' || st === 'professional' ? (st as SellerType) : ''
  f.shipping = params.get('frakt') === '1'
  const sort = params.get('sort') as SortKey | null
  f.sort = sort && ['relevance', 'price-asc', 'price-desc', 'newest'].includes(sort) ? sort : 'relevance'
  return f
}

export function paramsFromFilters(f: Partial<ListingFilters>): URLSearchParams {
  const p = new URLSearchParams()
  for (const k of STRING_KEYS) {
    const v = f[k]
    if (v) p.set(k, v)
  }
  if (f.conditions?.length) p.set('skick', f.conditions.join(','))
  if (f.sellerType) p.set('saljare', f.sellerType)
  if (f.shipping) p.set('frakt', '1')
  if (f.sort && f.sort !== 'relevance') p.set('sort', f.sort)
  return p
}

/** Lower-case and strip characters so "8E0 906" matches "8e0906". */
const norm = (s: string) => s.toLowerCase().normalize('NFC')
const compact = (s: string) => norm(s).replace(/[\s\-.]/g, '')

function haystack(l: Listing, seller?: Seller) {
  const cat = categoryById[l.categoryId]
  return norm(
    [
      l.title,
      l.partName,
      l.description,
      l.vehicle.make,
      l.vehicle.model,
      l.vehicle.generation,
      l.vehicle.engine,
      String(l.vehicle.year),
      l.oem,
      cat?.name,
      cat?.short,
      l.city,
      seller?.displayName,
    ]
      .filter(Boolean)
      .join(' '),
  )
}

/** Swedish part synonyms so common searches find the right listings. */
const SYNONYMS: Record<string, string[]> = {
  turbo: ['turbo', 'turboaggregat'],
  ecu: ['motorstyrenhet', 'ecu', 'styrenhet'],
  lampa: ['strålkastare', 'baklykta', 'lykta'],
  strålkastare: ['strålkastare', 'lampa', 'xenon'],
  broms: ['broms', 'bromsok', 'abs'],
  fälg: ['fälg', 'fälgar', 'hjul'],
  fälgar: ['fälg', 'fälgar', 'hjul'],
  spegel: ['spegel', 'sidospegel'],
  låda: ['växellåda', 'automatlåda'],
  vw: ['volkswagen'],
  volkswagen: ['volkswagen', 'vw'],
  merca: ['mercedes'],
  mercedes: ['mercedes'],
}

function scoreListing(l: Listing, tokens: string[], seller?: Seller): number {
  if (!tokens.length) return 1
  const hay = haystack(l, seller)
  const hayCompact = compact(hay)
  const title = norm(l.title)
  let score = 0
  for (const t of tokens) {
    const alts = SYNONYMS[t] ?? [t]
    const hit = alts.some((a) => hay.includes(a) || (a.length > 3 && hayCompact.includes(compact(a))))
    if (!hit) return 0
    score += alts.some((a) => title.includes(a)) ? 3 : 1
    if (norm(l.partName).includes(t)) score += 2
  }
  return score
}

export function applyFilters(listings: Listing[], f: ListingFilters, sellersById: Record<string, Seller>): Listing[] {
  const tokens = norm(f.q).split(/\s+/).filter(Boolean)
  const year = parseInt(f.year, 10)
  const min = parseInt(f.priceMin, 10)
  const max = parseInt(f.priceMax, 10)

  const scored = listings
    .filter((l) => l.status === 'active')
    .filter((l) => !f.make || l.vehicle.make === f.make)
    .filter((l) => !f.model || l.vehicle.model === f.model)
    .filter((l) => !f.generation || l.vehicle.generation === f.generation)
    .filter((l) => !f.engine || l.vehicle.engine === f.engine)
    .filter((l) => !year || l.vehicle.year === year)
    .filter((l) => !f.category || l.categoryId === f.category)
    .filter((l) => !f.part || norm(l.partName).includes(norm(f.part)) || norm(l.title).includes(norm(f.part)))
    .filter((l) => !f.oem || (l.oem && compact(l.oem).includes(compact(f.oem))))
    .filter((l) => isNaN(min) || l.price >= min)
    .filter((l) => isNaN(max) || l.price <= max)
    .filter((l) => !f.conditions.length || f.conditions.includes(l.condition))
    .filter((l) => !f.sellerType || sellersById[l.sellerId]?.type === f.sellerType)
    .filter((l) => !f.city || l.city === f.city)
    .filter((l) => !f.shipping || l.shipping)
    .map((l) => ({ l, s: scoreListing(l, tokens, sellersById[l.sellerId]) }))
    .filter((x) => x.s > 0)

  const byDate = (a: Listing, b: Listing) => b.createdAt.localeCompare(a.createdAt)
  switch (f.sort) {
    case 'price-asc':
      scored.sort((a, b) => a.l.price - b.l.price)
      break
    case 'price-desc':
      scored.sort((a, b) => b.l.price - a.l.price)
      break
    case 'newest':
      scored.sort((a, b) => byDate(a.l, b.l))
      break
    default:
      scored.sort((a, b) => b.s - a.s || byDate(a.l, b.l))
  }
  return scored.map((x) => x.l)
}

export function countActiveFilters(f: ListingFilters) {
  let n = 0
  for (const k of STRING_KEYS) if (k !== 'q' && f[k]) n++
  n += f.conditions.length
  if (f.sellerType) n++
  if (f.shipping) n++
  return n
}
