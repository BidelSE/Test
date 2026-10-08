import { CheckCircle2, Eye, Pencil, Plus, RotateCcw, Trash2, PackageOpen } from 'lucide-react'
import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { ConfirmDialog } from '../../components/Dialog'
import { EmptyState } from '../../components/EmptyState'
import { PartImage } from '../../components/PartImage'
import { useStore } from '../../features/AppStore'
import { cx, formatDate, formatPrice, vehicleLabel } from '../../lib/format'
import type { Listing } from '../../types'

export function MyListingsPage() {
  const { myListings, updateListing, deleteListing, toast } = useStore()
  const [params] = useSearchParams()
  const highlight = params.get('ny')
  const [filter, setFilter] = useState<'all' | 'active' | 'sold'>('all')
  const [toDelete, setToDelete] = useState<Listing | null>(null)
  const [toSell, setToSell] = useState<Listing | null>(null)
  const shown = myListings.filter((l) => filter === 'all' || l.status === filter)

  return (
    <div>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-lg font-semibold">Mina annonser</h2>
        <div className="flex rounded-md border border-gray-300 p-0.5 text-sm" role="group" aria-label="Visa">
          {([
            ['all', 'Alla'],
            ['active', 'Aktiva'],
            ['sold', 'Sålda'],
          ] as const).map(([k, l]) => (
            <button key={k} type="button" aria-pressed={filter === k} onClick={() => setFilter(k)} className={cx('rounded px-3 py-1 font-medium', filter === k ? 'bg-ink text-white' : 'text-gray-700 hover:bg-gray-100')}>
              {l}
            </button>
          ))}
        </div>
      </div>

      {highlight && myListings.some((l) => l.id === highlight) && (
        <div className="mt-4 flex gap-2.5 rounded-md border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-900" role="status">
          <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
          <p>Din annons har sparats i webbläsaren. Den syns i sökresultaten här i prototypen men publiceras inte för andra.</p>
        </div>
      )}

      {shown.length ? (
        <ul className="mt-4 space-y-3">
          {shown.map((l) => (
            <li key={l.id} className={cx('card flex flex-col gap-4 p-3 sm:flex-row sm:items-center', l.id === highlight && 'ring-2 ring-brand-700/30')}>
              <Link to={`/annons/${l.id}`} className="relative h-36 w-full shrink-0 overflow-hidden rounded-md border border-gray-100 sm:h-20 sm:w-28">
                <PartImage listing={l} size="sm" />
              </Link>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className={cx('rounded px-1.5 py-0.5 text-[11px] font-semibold', l.status === 'active' ? 'bg-emerald-50 text-emerald-800' : 'bg-gray-200 text-gray-700')}>{l.status === 'active' ? 'Aktiv' : 'Såld'}</span>
                  <span className="text-xs text-gray-500">Skapad {formatDate(l.createdAt)}</span>
                </div>
                <Link to={`/annons/${l.id}`} className="mt-1 block truncate font-medium hover:underline">
                  {l.title}
                </Link>
                <p className="truncate text-sm text-gray-600">
                  {formatPrice(l.price)} · {vehicleLabel(l.vehicle)} {l.vehicle.year}
                </p>
              </div>
              <div className="flex flex-wrap gap-1.5">
                <Link to={`/annons/${l.id}`} className="btn-ghost btn-sm" aria-label={`Visa ${l.title}`}>
                  <Eye className="h-4 w-4" /> Visa
                </Link>
                <Link to={`/salj/redigera/${l.id}`} className="btn-ghost btn-sm">
                  <Pencil className="h-4 w-4" /> Redigera
                </Link>
                {l.status === 'active' ? (
                  <button type="button" className="btn-ghost btn-sm" onClick={() => setToSell(l)}>
                    <CheckCircle2 className="h-4 w-4" /> Markera som såld
                  </button>
                ) : (
                  <button
                    type="button"
                    className="btn-ghost btn-sm"
                    onClick={() => {
                      updateListing(l.id, { status: 'active' })
                      toast('Annonsen är aktiv igen')
                    }}
                  >
                    <RotateCcw className="h-4 w-4" /> Återaktivera
                  </button>
                )}
                <button type="button" className="btn-ghost btn-sm text-red-600 hover:bg-red-50" onClick={() => setToDelete(l)}>
                  <Trash2 className="h-4 w-4" /> Ta bort
                </button>
              </div>
            </li>
          ))}
        </ul>
      ) : (
        <div className="mt-4">
          <EmptyState
            icon={<PackageOpen className="h-6 w-6" />}
            title={filter === 'sold' ? 'Inga sålda annonser' : 'Du har inga annonser här'}
            body="Annonser du skapar i prototypen sparas i den här webbläsaren."
            action={
              <Link to="/salj/ny" className="btn-primary">
                <Plus className="h-4 w-4" /> Skapa annons
              </Link>
            }
          />
        </div>
      )}

      <ConfirmDialog
        open={!!toDelete}
        onClose={() => setToDelete(null)}
        onConfirm={() => {
          deleteListing(toDelete!.id)
          toast('Annonsen togs bort')
        }}
        title="Ta bort annonsen?"
        body={<>”{toDelete?.title}” tas bort permanent från den här webbläsaren. Det går inte att ångra.</>}
        confirmLabel="Ta bort"
        danger
      />
      <ConfirmDialog
        open={!!toSell}
        onClose={() => setToSell(null)}
        onConfirm={() => {
          updateListing(toSell!.id, { status: 'sold' })
          toast('Annonsen markerades som såld', 'success')
        }}
        title="Markera som såld?"
        body="Annonsen döljs från sökresultaten men finns kvar under Mina annonser. Du kan återaktivera den senare."
        confirmLabel="Markera som såld"
      />
    </div>
  )
}
