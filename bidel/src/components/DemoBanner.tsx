import { Info, X } from 'lucide-react'
import { useState } from 'react'
import { Link } from 'react-router-dom'
import { readStore, writeStore } from '../lib/storage'

export function DemoBanner() {
  const [hidden, setHidden] = useState(() => readStore('bannerHidden', false))
  if (hidden) return null
  return (
    <div className="border-b border-brand-100 bg-brand-50 text-brand-900">
      <div className="container-page flex items-start gap-2.5 py-2 text-[13px] leading-snug sm:items-center">
        <Info className="mt-0.5 h-4 w-4 shrink-0 sm:mt-0" aria-hidden />
        <p className="flex-1">
          <strong className="font-semibold">Prototyp under utveckling.</strong> Alla annonser är demonstrationsexempel och inga köp, betalningar eller meddelanden skickas på riktigt.{' '}
          <Link to="/om-bidel#prototyp" className="font-medium underline underline-offset-2">
            Läs mer
          </Link>
        </p>
        <button
          type="button"
          aria-label="Dölj meddelandet"
          className="-mr-1 grid h-7 w-7 shrink-0 place-items-center rounded hover:bg-brand-100"
          onClick={() => {
            writeStore('bannerHidden', true)
            setHidden(true)
          }}
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    </div>
  )
}
