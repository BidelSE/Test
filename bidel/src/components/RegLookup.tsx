import { Car, Info } from 'lucide-react'
import { useState } from 'react'
import { demoPlates } from '../data/vehicles'
import { cx } from '../lib/format'
import { FutureBadge } from './FutureBadge'

type DemoVehicle = (typeof demoPlates)[string]

/**
 * Placeholder for a future registration-number lookup. No external service is
 * called; only the clearly fictional plates in `demoPlates` resolve.
 */
export function RegLookup({ onVehicle, compact, actionLabel = 'Ja, visa delar' }: { onVehicle: (v: DemoVehicle) => void; compact?: boolean; actionLabel?: string }) {
  const [plate, setPlate] = useState('')
  const [result, setResult] = useState<null | { found: DemoVehicle | null; plate: string }>(null)

  const lookup = (p: string) => {
    const key = p.replace(/\s/g, '').toUpperCase()
    setResult({ plate: key, found: demoPlates[key] ?? null })
  }

  return (
    <div className={cx('rounded-lg border border-gray-200 bg-white', compact ? 'p-4' : 'p-5')}>
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-sm font-semibold">Sök på registreringsnummer</h2>
        <FutureBadge />
      </div>
      <p className="mt-1 text-xs leading-relaxed text-gray-600">Identifiering via registreringsnummer kräver en behörig fordonsdatakälla och är inte kopplad ännu. Prova med ett påhittat demofordon.</p>
      <form
        className="mt-3 flex gap-2"
        onSubmit={(e) => {
          e.preventDefault()
          if (plate.trim()) lookup(plate)
        }}
      >
        <label htmlFor="regnr" className="sr-only">
          Registreringsnummer
        </label>
        <div className="flex h-11 flex-1 overflow-hidden rounded-md border-2 border-ink bg-white focus-within:ring-2 focus-within:ring-brand-700/30">
          <span className="flex w-7 flex-col items-center justify-end bg-[#003399] pb-1 text-[9px] font-bold text-white" aria-hidden>
            S
          </span>
          <input
            id="regnr"
            value={plate}
            onChange={(e) => setPlate(e.target.value.toUpperCase().slice(0, 7))}
            placeholder="ABC 123"
            autoComplete="off"
            className="w-full min-w-0 px-3 text-lg font-semibold uppercase tracking-[0.15em] placeholder:font-medium placeholder:text-gray-300 focus:outline-none"
          />
        </div>
        <button type="submit" className="btn-secondary h-11">
          Hämta
        </button>
      </form>
      <div className="mt-2.5 flex flex-wrap items-center gap-1.5 text-xs text-gray-500">
        <span>Demofordon:</span>
        {Object.keys(demoPlates).map((p) => (
          <button
            key={p}
            type="button"
            className="rounded border border-gray-300 px-1.5 py-0.5 font-mono text-[11px] text-gray-700 hover:border-brand-700 hover:text-brand-700"
            onClick={() => {
              setPlate(p)
              lookup(p)
            }}
          >
            {p}
          </button>
        ))}
      </div>
      {result && (
        <div className="mt-3 rounded-md bg-surface p-3 text-sm animate-fade-in" role="status">
          {result.found ? (
            <>
              <p className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-wide text-gray-500">
                <Car className="h-3.5 w-3.5" aria-hidden /> Påhittat demofordon
              </p>
              <p className="mt-1 font-semibold">
                {result.found.make} {result.found.model} {result.found.generation} {result.found.engine}, {result.found.year}
              </p>
              <p className="mt-1 text-xs text-gray-600">Stämmer fordonet? Resultaten filtreras på märke, modell och år – inte på verifierad passform.</p>
              <button type="button" className="btn-primary btn-sm mt-3" onClick={() => onVehicle(result.found!)}>
                {actionLabel}
              </button>
            </>
          ) : (
            <p className="flex gap-2 text-gray-700">
              <Info className="mt-0.5 h-4 w-4 shrink-0 text-gray-500" aria-hidden />
              <span>
                Vi kan inte slå upp <strong>{result.plate}</strong> ännu. Välj din bil manuellt med märke, modell och årsmodell.
              </span>
            </p>
          )}
        </div>
      )}
    </div>
  )
}
