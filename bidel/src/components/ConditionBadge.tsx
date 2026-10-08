import { conditionLabel } from '../data/categories'
import { cx } from '../lib/format'
import type { Condition } from '../types'

const tone: Record<Condition, string> = {
  ny: 'bg-emerald-50 text-emerald-800 ring-emerald-200',
  'mycket-bra': 'bg-emerald-50 text-emerald-800 ring-emerald-200',
  bra: 'bg-gray-100 text-gray-700 ring-gray-200',
  godtagbar: 'bg-amber-50 text-amber-800 ring-amber-200',
  renovering: 'bg-orange-50 text-orange-800 ring-orange-200',
}

export function ConditionBadge({ condition, className }: { condition: Condition; className?: string }) {
  return (
    <span className={cx('inline-flex items-center rounded px-1.5 py-0.5 text-[11px] font-medium ring-1 ring-inset', tone[condition], className)}>
      {conditionLabel[condition]}
    </span>
  )
}
