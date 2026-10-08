import { CarFront } from 'lucide-react'
import { useStore } from '../features/AppStore'
import { cx } from '../lib/format'
import { matchCopy, matchLevel } from '../lib/fitment'
import type { VehicleRef } from '../types'

export function MatchBadge({ vehicle, className }: { vehicle: VehicleRef; className?: string }) {
  const { myCar } = useStore()
  const level = matchLevel(myCar, vehicle)
  if (!level) return null
  return (
    <span
      title={`${matchCopy[level].long} Det betyder inte att delen passar.`}
      className={cx(
        'inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[11px] font-medium ring-1 ring-inset',
        level === 'engine' ? 'bg-brand-50 text-brand-800 ring-brand-200' : 'bg-white text-gray-700 ring-gray-300',
        className,
      )}
    >
      <CarFront className="h-3 w-3" aria-hidden />
      {matchCopy[level].short}
    </span>
  )
}
