import { Building2, User } from 'lucide-react'
import { cx } from '../lib/format'
import type { SellerType } from '../types'

export function SellerTypeBadge({ type, className }: { type: SellerType; className?: string }) {
  const pro = type === 'professional'
  return (
    <span className={cx('inline-flex items-center gap-1 text-xs font-medium', pro ? 'text-brand-700' : 'text-gray-600', className)}>
      {pro ? <Building2 className="h-3.5 w-3.5" aria-hidden /> : <User className="h-3.5 w-3.5" aria-hidden />}
      {pro ? 'Företag' : 'Privat'}
    </span>
  )
}
