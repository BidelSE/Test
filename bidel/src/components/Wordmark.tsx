import { Link } from 'react-router-dom'
import { cx } from '../lib/format'

export function Wordmark({ className, inverted }: { className?: string; inverted?: boolean }) {
  return (
    <Link
      to="/"
      aria-label="Bidel – till startsidan"
      className={cx('select-none font-bold tracking-[0.12em] leading-none', inverted ? 'text-white' : 'text-brand-700', className)}
      style={{ fontFamily: '"Helvetica Neue", Helvetica, Arial, sans-serif' }}
    >
      BIDEL
    </Link>
  )
}
