import { categoryById } from '../data/categories'
import { cx } from '../lib/format'
import type { Listing } from '../types'
import { CategoryIcon } from './CategoryIcon'

/**
 * Consistent placeholder used when a listing has no real photograph.
 * We never show a photo of a different component just to fill space.
 */
export function PartImage({ listing, index = 0, className, size = 'md' }: { listing: Listing; index?: number; className?: string; size?: 'sm' | 'md' | 'lg' }) {
  const photo = listing.photos?.[index]
  if (photo) {
    return <img src={photo} alt={`${listing.title} – bild ${index + 1}`} className={cx('h-full w-full object-cover', className)} />
  }
  const cat = categoryById[listing.categoryId]
  const views = ['Översikt', 'Detalj', 'Märkning']
  return (
    <div
      role="img"
      aria-label={`Bild saknas – platshållare för ${listing.partName.toLowerCase()}`}
      className={cx('relative flex h-full w-full flex-col items-center justify-center bg-gradient-to-b from-gray-50 to-gray-100 text-gray-400', className)}
    >
      <svg className="absolute inset-0 h-full w-full text-gray-200" aria-hidden>
        <defs>
          <pattern id="grid" width="24" height="24" patternUnits="userSpaceOnUse">
            <path d="M24 0H0V24" fill="none" stroke="currentColor" strokeWidth="1" />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill="url(#grid)" opacity="0.6" />
      </svg>
      <CategoryIcon id={listing.categoryId} className={cx('relative', size === 'lg' ? 'h-20 w-20' : size === 'sm' ? 'h-8 w-8' : 'h-12 w-12')} />
      {size !== 'sm' && (
        <span className="relative mt-3 hidden text-[11px] sm:block font-medium uppercase tracking-wider text-gray-400">
          {cat?.short} · {index === 0 ? 'Bild saknas' : views[index % views.length]}
        </span>
      )}
    </div>
  )
}
