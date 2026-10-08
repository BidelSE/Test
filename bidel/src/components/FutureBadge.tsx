import { cx } from '../lib/format'

export function FutureBadge({ children = 'Kommer senare', className }: { children?: string; className?: string }) {
  return <span className={cx('inline-flex items-center rounded-full border border-dashed border-gray-400 px-2 py-0.5 text-[11px] font-medium text-gray-600', className)}>{children}</span>
}
