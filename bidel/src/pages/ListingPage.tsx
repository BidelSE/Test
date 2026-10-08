import { AlertTriangle, ArrowLeft, Check, ChevronLeft, ChevronRight, Flag, MapPin, MessageSquare, Package, Share2, Store, Truck, X } from 'lucide-react'
import { useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { Breadcrumbs } from '../components/Breadcrumbs'
import { ConditionBadge } from '../components/ConditionBadge'
import { Dialog } from '../components/Dialog'
import { FavoriteButton } from '../components/FavoriteButton'
import { ListingCard } from '../components/ListingCard'
import { PartImage } from '../components/PartImage'
import { SellerTypeBadge } from '../components/SellerTypeBadge'
import { categoryById, conditions } from '../data/categories'
import { useStore } from '../features/AppStore'
import { cx, formatDate, formatMileage, formatPrice, vehicleLabel } from '../lib/format'
import { NotFoundPage } from './NotFoundPage'

export function ListingPage() {
  const { id } = useParams()
  const { getListing, sellersById, listings, startConversation, toast } = useStore()
  const navigate = useNavigate()
  const location = useLocation()
  const listing = id ? getListing(id) : undefined
  const [img, setImg] = useState(0)
  const [reportOpen, setReportOpen] = useState(false)

  if (!listing) return <NotFoundPage title="Annonsen finns inte" body="Annonsen kan ha tagits bort eller så är länken felaktig." />

  const seller = sellersById[listing.sellerId]
  const cat = categoryById[listing.categoryId]
  const from = (location.state as { from?: string } | null)?.from
  const imageCount = listing.photos?.length || listing.placeholderViews || 1
  const condDesc = conditions.find((c) => c.id === listing.condition)?.description
  const isMine = listing.sellerId === 'me'
  const similar = listings
    .filter((l) => l.id !== listing.id && l.status === 'active' && (l.categoryId === listing.categoryId || (l.vehicle.make === listing.vehicle.make && l.vehicle.model === listing.vehicle.model)))
    .slice(0, 4)

  const contact = () => {
    const cid = startConversation(listing.id)
    navigate(`/konto/meddelanden/${cid}`)
  }

  const share = async () => {
    const url = window.location.href
    try {
      if (navigator.share) {
        await navigator.share({ title: listing.title, url })
        return
      }
      await navigator.clipboard.writeText(url)
      toast('Länken kopierades', 'success')
    } catch {
      /* user cancelled */
    }
  }

  const specs: [string, React.ReactNode][] = [
    ['Märke', listing.vehicle.make],
    ['Modell', `${listing.vehicle.model}${listing.vehicle.generation ? ` (${listing.vehicle.generation})` : ''}`],
    ['Årsmodell', listing.vehicle.year],
    ['Motor', listing.vehicle.engine ?? '–'],
    ['Kategori', cat.name],
    ['Del', listing.partName],
    [
      'OEM-/referensnummer',
      listing.oem ? (
        <span>
          <span className="font-mono">{listing.oem}</span>
          {listing.oemIsDemo && <span className="ml-2 rounded bg-amber-50 px-1.5 py-0.5 text-[11px] font-medium text-amber-800 ring-1 ring-amber-200">Påhittat demonummer</span>}
        </span>
      ) : (
        'Ej angivet'
      ),
    ],
    ['Givarbilens miltal', formatMileage(listing.donorMileageKm)],
    ['Antal', `${listing.quantity} st`],
    ['Upplagd', formatDate(listing.createdAt)],
  ]

  return (
    <div className="container-page pt-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <Breadcrumbs items={[{ label: 'Bildelar', to: '/bildelar' }, { label: cat.short, to: `/bildelar?category=${cat.id}` }, { label: listing.partName }]} />
        <Link to={from ?? '/bildelar'} className="inline-flex items-center gap-1 text-sm font-medium text-gray-700 hover:text-ink">
          <ArrowLeft className="h-4 w-4" /> {from ? 'Tillbaka till sökresultaten' : 'Alla bildelar'}
        </Link>
      </div>

      {listing.status === 'sold' && (
        <div className="mt-4 rounded-md border border-gray-300 bg-surface px-4 py-3 text-sm font-medium">Den här delen är markerad som såld.</div>
      )}

      <div className="mt-5 grid gap-8 lg:grid-cols-[1fr_380px] lg:gap-10">
        {/* Gallery + details */}
        <div className="min-w-0">
          <div className="relative aspect-[4/3] overflow-hidden rounded-lg border border-gray-200">
            <PartImage listing={listing} index={img} size="lg" />
            {imageCount > 1 && (
              <>
                <button type="button" aria-label="Föregående bild" onClick={() => setImg((i) => (i - 1 + imageCount) % imageCount)} className="absolute left-3 top-1/2 grid h-10 w-10 -translate-y-1/2 place-items-center rounded-full bg-white/95 shadow ring-1 ring-black/5 hover:bg-white">
                  <ChevronLeft className="h-5 w-5" />
                </button>
                <button type="button" aria-label="Nästa bild" onClick={() => setImg((i) => (i + 1) % imageCount)} className="absolute right-3 top-1/2 grid h-10 w-10 -translate-y-1/2 place-items-center rounded-full bg-white/95 shadow ring-1 ring-black/5 hover:bg-white">
                  <ChevronRight className="h-5 w-5" />
                </button>
                <span className="absolute bottom-3 right-3 rounded bg-black/60 px-2 py-0.5 text-xs font-medium text-white">
                  {img + 1} / {imageCount}
                </span>
              </>
            )}
          </div>
          {imageCount > 1 && (
            <div className="mt-3 flex gap-2 overflow-x-auto" role="tablist" aria-label="Bilder">
              {Array.from({ length: imageCount }, (_, i) => (
                <button
                  key={i}
                  type="button"
                  role="tab"
                  aria-selected={img === i}
                  aria-label={`Visa bild ${i + 1}`}
                  onClick={() => setImg(i)}
                  className={cx('h-16 w-20 shrink-0 overflow-hidden rounded-md border-2 sm:h-20 sm:w-24', img === i ? 'border-brand-700' : 'border-transparent opacity-80 hover:opacity-100')}
                >
                  <PartImage listing={listing} index={i} size="sm" />
                </button>
              ))}
            </div>
          )}
          {!listing.photos?.length && <p className="mt-2 text-xs text-gray-500">Demoannonsen saknar riktiga foton. Vi visar en neutral platshållare i stället för en bild på fel del.</p>}

          {/* Mobile summary (shown above details on small screens) */}
          <div className="mt-6 lg:hidden">
            {renderSummary()}
          </div>

          <section className="mt-10" aria-labelledby="beskrivning">
            <h2 id="beskrivning" className="text-lg font-semibold">
              Beskrivning
            </h2>
            <p className="mt-3 whitespace-pre-line text-[15px] leading-relaxed text-gray-800">{listing.description}</p>
          </section>

          <section className="mt-10" aria-labelledby="passform">
            <h2 id="passform" className="text-lg font-semibold">
              Fordon och passform
            </h2>
            <div className="mt-3 rounded-lg border border-gray-200">
              <div className="border-b border-gray-200 p-4">
                <p className="eyebrow">Demonterad från</p>
                <p className="mt-1 text-base font-semibold">
                  {vehicleLabel(listing.vehicle)}, {listing.vehicle.year}
                </p>
                {listing.donorMileageKm && <p className="mt-0.5 text-sm text-gray-600">Givarbilen hade gått {formatMileage(listing.donorMileageKm)}</p>}
              </div>
              <div className="p-4">
                <p className="eyebrow">Säljarens kommentar om passform</p>
                <p className="mt-1 text-sm leading-relaxed text-gray-800">{listing.fitmentNotes ?? 'Säljaren har inte angett några uppgifter om passform utöver givarbilen.'}</p>
              </div>
              <div className="flex gap-3 rounded-b-lg border-t border-amber-200 bg-amber-50 p-4 text-sm text-amber-900">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
                <p>
                  Bidel har inte kontrollerat att delen passar. Att den kommer från samma märke eller modell betyder inte att den passar din bil. Jämför referensnummer,
                  motorkod och utrustning – och fråga säljaren – innan du köper.
                </p>
              </div>
            </div>
          </section>

          <section className="mt-10" aria-labelledby="tekniskt">
            <h2 id="tekniskt" className="text-lg font-semibold">
              Tekniska uppgifter
            </h2>
            <dl className="mt-3 divide-y divide-gray-100 rounded-lg border border-gray-200 text-sm">
              {specs.map(([k, v]) => (
                <div key={k} className="grid grid-cols-[minmax(0,10rem)_1fr] gap-4 px-4 py-2.5 sm:grid-cols-[14rem_1fr]">
                  <dt className="text-gray-500">{k}</dt>
                  <dd className="min-w-0 break-words font-medium text-ink">{v}</dd>
                </div>
              ))}
              <div className="grid grid-cols-[minmax(0,10rem)_1fr] gap-4 px-4 py-2.5 sm:grid-cols-[14rem_1fr]">
                <dt className="text-gray-500">Skick</dt>
                <dd>
                  <ConditionBadge condition={listing.condition} />
                  <p className="mt-1 text-gray-600">{listing.conditionNote ?? condDesc}</p>
                </dd>
              </div>
              {listing.additionalNotes && (
                <div className="grid grid-cols-[minmax(0,10rem)_1fr] gap-4 px-4 py-2.5 sm:grid-cols-[14rem_1fr]">
                  <dt className="text-gray-500">Övrigt</dt>
                  <dd>{listing.additionalNotes}</dd>
                </div>
              )}
            </dl>
          </section>

          <button type="button" onClick={() => setReportOpen(true)} className="mt-6 inline-flex items-center gap-1.5 text-xs text-gray-500 hover:text-ink hover:underline">
            <Flag className="h-3.5 w-3.5" /> Rapportera annons
          </button>
        </div>

        {/* Sidebar */}
        <div className="hidden lg:block">
          <div className="sticky top-20">
            {renderSummary()}
          </div>
        </div>
      </div>

      {similar.length > 0 && (
        <section className="mt-16" aria-labelledby="liknande">
          <h2 id="liknande" className="text-lg font-semibold">
            Liknande delar
          </h2>
          <div className="mt-4 grid grid-cols-2 gap-3 sm:gap-4 md:grid-cols-4">
            {similar.map((l) => (
              <ListingCard key={l.id} listing={l} />
            ))}
          </div>
        </section>
      )}

      <Dialog open={reportOpen} onClose={() => setReportOpen(false)} title="Rapportera annons" footer={<button className="btn-primary" onClick={() => setReportOpen(false)}>Jag förstår</button>}>
        Rapportering av misstänkta annonser kommer att hanteras av Bidels moderering i den färdiga tjänsten. I prototypen skickas ingen rapport.
      </Dialog>
    </div>
  )

  function renderSummary() {
    return (
      <div className="space-y-4">
        <div className="card p-5">
          <div className="flex items-center gap-2">
            <ConditionBadge condition={listing!.condition} />
            <span className="text-xs text-gray-500">{cat.name}</span>
          </div>
          <h1 className="mt-2.5 text-xl font-semibold leading-snug tracking-tight sm:text-2xl">{listing!.title}</h1>
          <p className="mt-3 text-3xl font-bold tabular-nums tracking-tight">{formatPrice(listing!.price)}</p>
          <p className="mt-0.5 text-xs text-gray-500">{listing!.negotiable ? 'Priset kan diskuteras' : 'Fast pris'}</p>

          <ul className="mt-5 space-y-2 text-sm text-gray-700">
            <li className="flex items-center gap-2">
              <MapPin className="h-4 w-4 text-gray-400" aria-hidden />
              {listing!.city}, {listing!.postalCode.slice(0, 3)} xx
            </li>
            <li className="flex items-center gap-2">
              {listing!.shipping ? <Truck className="h-4 w-4 text-gray-400" aria-hidden /> : <X className="h-4 w-4 text-gray-400" aria-hidden />}
              {listing!.shipping ? 'Kan skickas – frakt enligt överenskommelse' : 'Skickas inte'}
            </li>
            <li className="flex items-center gap-2">
              {listing!.pickup ? <Check className="h-4 w-4 text-gray-400" aria-hidden /> : <X className="h-4 w-4 text-gray-400" aria-hidden />}
              {listing!.pickup ? 'Kan hämtas' : 'Ingen upphämtning'}
            </li>
            <li className="flex items-center gap-2">
              <Package className="h-4 w-4 text-gray-400" aria-hidden />
              {listing!.status === 'sold' ? 'Såld' : `Tillgänglig (${listing!.quantity} st)`}
            </li>
          </ul>

          <div className="mt-6 grid gap-2">
            {isMine ? (
              <Link to={`/salj/redigera/${listing!.id}`} className="btn-primary btn-lg">
                Redigera annons
              </Link>
            ) : (
              <button type="button" className="btn-primary btn-lg" onClick={contact} disabled={listing!.status === 'sold'}>
                <MessageSquare className="h-4 w-4" />
                Kontakta säljaren
              </button>
            )}
            <div className="grid grid-cols-2 gap-2">
              <FavoriteButton id={listing!.id} variant="full" />
              <button type="button" className="btn-secondary" onClick={share}>
                <Share2 className="h-4 w-4" />
                Dela
              </button>
            </div>
          </div>
          <p className="mt-4 text-xs leading-relaxed text-gray-500">Köp och betalning sker direkt mellan dig och säljaren. Bidel erbjuder ännu ingen betalning, köparskydd eller fraktbokning.</p>
        </div>

        {seller && (
          <div className="card p-5">
            <p className="eyebrow">Säljare</p>
            <div className="mt-3 flex items-center gap-3">
              <div className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-surface text-sm font-semibold text-gray-700">
                {seller.type === 'professional' ? <Store className="h-5 w-5" aria-hidden /> : seller.displayName.slice(0, 1)}
              </div>
              <div className="min-w-0">
                <p className="truncate font-semibold">{seller.displayName}</p>
                <div className="flex items-center gap-2 text-xs text-gray-500">
                  <SellerTypeBadge type={seller.type} />
                  <span>· {seller.city}</span>
                </div>
              </div>
            </div>
            <Link to={`/saljare/${seller.id}`} className="btn-secondary mt-4 w-full">
              Visa säljarens profil
            </Link>
          </div>
        )}
      </div>
    )
  }
}
