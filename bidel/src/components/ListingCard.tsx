import { MapPin, Truck } from 'lucide-react'
import { Link, useLocation } from 'react-router-dom'
import { useStore } from '../features/AppStore'
import { formatPrice, relativeDate, vehicleLabel } from '../lib/format'
import type { Listing } from '../types'
import { ConditionBadge } from './ConditionBadge'
import { FavoriteButton } from './FavoriteButton'
import { PartImage } from './PartImage'
import { SellerTypeBadge } from './SellerTypeBadge'

export function ListingCard({ listing }: { listing: Listing }) {
  const { sellersById } = useStore()
  const seller = sellersById[listing.sellerId]
  const location = useLocation()
  return (
    <article className="group relative flex flex-col overflow-hidden rounded-lg border border-gray-200 bg-white transition hover:border-gray-300 hover:shadow-[0_2px_12px_-4px_rgba(0,0,0,0.12)]">
      <div className="relative aspect-[4/3] overflow-hidden border-b border-gray-100">
        <PartImage listing={listing} />
        <FavoriteButton id={listing.id} className="absolute right-2.5 top-2.5" />
        {listing.status === 'sold' && <span className="absolute left-2.5 top-2.5 rounded bg-ink px-2 py-0.5 text-xs font-semibold text-white">Såld</span>}
      </div>
      <div className="flex flex-1 flex-col p-3.5">
        <div className="flex flex-wrap items-center justify-between gap-x-2 gap-y-1">
          <p className="text-[17px] font-semibold tabular-nums tracking-tight">{formatPrice(listing.price)}</p>
          <ConditionBadge condition={listing.condition} className="shrink-0" />
        </div>
        <h3 className="mt-1 line-clamp-2 text-sm font-medium leading-snug text-ink">
          <Link to={`/annons/${listing.id}`} state={{ from: location.pathname + location.search }} className="after:absolute after:inset-0 focus-visible:outline-none group-focus-within:underline">
            {listing.title}
          </Link>
        </h3>
        <p className="mt-1 text-xs text-gray-600">
          Från: {vehicleLabel(listing.vehicle)} · {listing.vehicle.year}
        </p>
        <div className="mt-auto flex items-center justify-between gap-2 pt-3 text-xs text-gray-500">
          <span className="inline-flex min-w-0 items-center gap-1">
            <MapPin className="h-3.5 w-3.5 shrink-0" aria-hidden />
            <span className="truncate">{listing.city}</span>
            {listing.shipping && (
              <span className="inline-flex items-center gap-1 pl-1.5" title="Kan skickas">
                <Truck className="h-3.5 w-3.5" aria-hidden />
                <span className="sr-only">Kan skickas</span>
              </span>
            )}
          </span>
          {seller && <SellerTypeBadge type={seller.type} />}
        </div>
        <p className="mt-1 text-[11px] text-gray-400">{relativeDate(listing.createdAt)}</p>
      </div>
    </article>
  )
}
