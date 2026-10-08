import { CheckCircle2, X, AlertCircle } from 'lucide-react'
import { useStore } from '../features/AppStore'
import { cx } from '../lib/format'

export function Toasts() {
  const { toasts, dismissToast } = useStore()
  return (
    <div aria-live="polite" className="pointer-events-none fixed inset-x-0 bottom-4 z-[60] flex flex-col items-center gap-2 px-4 sm:bottom-6 sm:items-end sm:px-6">
      {toasts.map((t) => (
        <div key={t.id} className="pointer-events-auto flex w-full max-w-sm items-center gap-2.5 rounded-lg bg-ink px-4 py-3 text-sm text-white shadow-lg animate-fade-in">
          {t.tone === 'success' && <CheckCircle2 className="h-4 w-4 shrink-0 text-emerald-400" aria-hidden />}
          {t.tone === 'error' && <AlertCircle className="h-4 w-4 shrink-0 text-red-400" aria-hidden />}
          <p className="flex-1">{t.text}</p>
          <button type="button" aria-label="Stäng" className={cx('grid h-6 w-6 place-items-center rounded text-gray-400 hover:text-white')} onClick={() => dismissToast(t.id)}>
            <X className="h-4 w-4" />
          </button>
        </div>
      ))}
    </div>
  )
}
