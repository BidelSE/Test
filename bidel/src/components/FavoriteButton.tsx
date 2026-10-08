import { Heart } from 'lucide-react'
import { useStore } from '../features/AppStore'
import { cx } from '../lib/format'

export function FavoriteButton({ id, variant = 'icon', className }: { id: string; variant?: 'icon' | 'full'; className?: string }) {
  const { isFavorite, toggleFavorite } = useStore()
  const on = isFavorite(id)
  if (variant === 'full') {
    return (
      <button type="button" onClick={() => toggleFavorite(id)} aria-pressed={on} className={cx('btn-secondary', on && 'border-brand-700 text-brand-700', className)}>
        <Heart className={cx('h-4 w-4', on && 'fill-current')} />
        {on ? 'Sparad' : 'Spara annons'}
      </button>
    )
  }
  return (
    <button
      type="button"
      onClick={(e) => {
        e.preventDefault()
        e.stopPropagation()
        toggleFavorite(id)
      }}
      aria-pressed={on}
      aria-label={on ? 'Ta bort från sparade' : 'Spara annons'}
      className={cx('grid h-9 w-9 place-items-center rounded-full bg-white/95 shadow-sm ring-1 ring-black/5 transition hover:scale-105', on ? 'text-brand-700' : 'text-gray-600', className)}
    >
      <Heart className={cx('h-[18px] w-[18px]', on && 'fill-current')} />
    </button>
  )
}
