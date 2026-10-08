import { ArrowLeft, ArrowRight, ChevronLeft, ChevronRight, ImagePlus, Info, Trash2 } from 'lucide-react'
import { useRef, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { ConditionBadge } from '../components/ConditionBadge'
import { ConfirmDialog } from '../components/Dialog'
import { Field, Select } from '../components/Field'
import { ListingCard } from '../components/ListingCard'
import { VehicleSelects } from '../components/VehicleSelects'
import { categories, categoryById, cities, conditions } from '../data/categories'
import { useStore } from '../features/AppStore'
import { useStoredState } from '../hooks/useStoredState'
import { cx, formatMileage, formatPrice, vehicleLabel } from '../lib/format'
import type { CategoryId, Condition, Listing, SellerType } from '../types'
import { NotFoundPage } from './NotFoundPage'

interface Draft {
  title: string
  categoryId: CategoryId | ''
  partName: string
  description: string
  oem: string
  make: string
  model: string
  generation: string
  engine: string
  year: string
  vin: string
  condition: Condition | ''
  conditionNote: string
  donorMileage: string
  price: string
  negotiable: boolean
  photos: string[]
  city: string
  postalCode: string
  pickup: boolean
  shipping: boolean
  sellerType: SellerType
  fitmentNotes: string
  quantity: string
}

const emptyDraft = (sellerType: SellerType, city: string, postalCode: string): Draft => ({
  title: '',
  categoryId: '',
  partName: '',
  description: '',
  oem: '',
  make: '',
  model: '',
  generation: '',
  engine: '',
  year: '',
  vin: '',
  condition: '',
  conditionNote: '',
  donorMileage: '',
  price: '',
  negotiable: false,
  photos: [],
  city,
  postalCode,
  pickup: true,
  shipping: false,
  sellerType,
  fitmentNotes: '',
  quantity: '1',
})

const fromListing = (l: Listing, sellerType: SellerType): Draft => ({
  title: l.title,
  categoryId: l.categoryId,
  partName: l.partName,
  description: l.description,
  oem: l.oem ?? '',
  make: l.vehicle.make,
  model: l.vehicle.model,
  generation: l.vehicle.generation ?? '',
  engine: l.vehicle.engine ?? '',
  year: String(l.vehicle.year),
  vin: l.vin ?? '',
  condition: l.condition,
  conditionNote: l.conditionNote ?? '',
  donorMileage: l.donorMileageKm ? String(Math.round(l.donorMileageKm / 10)) : '',
  price: String(l.price),
  negotiable: l.negotiable,
  photos: l.photos ?? [],
  city: l.city,
  postalCode: l.postalCode,
  pickup: l.pickup,
  shipping: l.shipping,
  sellerType,
  fitmentNotes: l.fitmentNotes ?? '',
  quantity: String(l.quantity),
})

const steps = ['Del', 'Fordon', 'Skick och pris', 'Bilder', 'Plats och leverans', 'Förhandsgranska']

type Errors = Partial<Record<keyof Draft, string>>

function validate(step: number, d: Draft): Errors {
  const e: Errors = {}
  if (step === 0) {
    if (d.title.trim().length < 5) e.title = 'Skriv en rubrik på minst 5 tecken.'
    if (!d.categoryId) e.categoryId = 'Välj en kategori.'
    if (!d.partName.trim()) e.partName = 'Ange vilken del det är.'
    if (d.description.trim().length < 20) e.description = 'Beskriv delen med minst 20 tecken.'
  }
  if (step === 1) {
    if (!d.make) e.make = 'Välj märke.'
    if (!d.model) e.model = 'Välj modell.'
    if (!d.year) e.year = 'Välj årsmodell.'
    if (d.vin && !/^[A-HJ-NPR-Z0-9]{17}$/i.test(d.vin.trim())) e.vin = 'Ett chassinummer (VIN) har 17 tecken och innehåller inte I, O eller Q.'
  }
  if (step === 2) {
    if (!d.condition) e.condition = 'Välj skick.'
    const p = Number(d.price)
    if (!d.price || !Number.isFinite(p) || p <= 0) e.price = 'Ange ett pris i hela kronor.'
    else if (p > 500000) e.price = 'Priset verkar orimligt högt. Kontrollera beloppet.'
    if (d.donorMileage && !/^\d+$/.test(d.donorMileage)) e.donorMileage = 'Ange miltal med siffror.'
    if (!/^\d+$/.test(d.quantity) || +d.quantity < 1) e.quantity = 'Ange antal.'
  }
  if (step === 4) {
    if (!d.city) e.city = 'Välj ort.'
    if (!/^\d{3}\s?\d{2}$/.test(d.postalCode.trim())) e.postalCode = 'Ange ett postnummer med fem siffror, t.ex. 118 46.'
    if (!d.pickup && !d.shipping) e.pickup = 'Välj minst ett leveranssätt.'
  }
  return e
}

/** Downscale uploaded photos so they fit comfortably in browser storage. */
function readImage(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = reject
    reader.onload = () => {
      const img = new Image()
      img.onerror = reject
      img.onload = () => {
        const max = 1000
        const scale = Math.min(1, max / Math.max(img.width, img.height))
        const canvas = document.createElement('canvas')
        canvas.width = Math.round(img.width * scale)
        canvas.height = Math.round(img.height * scale)
        canvas.getContext('2d')!.drawImage(img, 0, 0, canvas.width, canvas.height)
        resolve(canvas.toDataURL('image/jpeg', 0.75))
      }
      img.src = reader.result as string
    }
    reader.readAsDataURL(file)
  })
}

export function SellFormPage() {
  const { id } = useParams()
  const { myListings, profile } = useStore()
  if (id) {
    const listing = myListings.find((l) => l.id === id)
    if (!listing) return <NotFoundPage title="Annonsen kan inte redigeras" body="Du kan bara redigera dina egna annonser." />
    return <SellForm key={id} editing={listing} initial={fromListing(listing, profile.sellerType)} />
  }
  return <NewSellForm />
}

function NewSellForm() {
  const { profile } = useStore()
  const [draft, setDraft] = useStoredState<Draft>('sellDraft', () => emptyDraft(profile.sellerType, profile.city, profile.postalCode))
  return <SellForm initial={draft} onDraftChange={setDraft} onReset={() => setDraft(emptyDraft(profile.sellerType, profile.city, profile.postalCode))} />
}

function SellForm({ initial, editing, onDraftChange, onReset }: { initial: Draft; editing?: Listing; onDraftChange?: (d: Draft) => void; onReset?: () => void }) {
  const { createListing, updateListing, toast, loggedIn, login, profile, updateProfile } = useStore()
  const navigate = useNavigate()
  const [d, setD] = useState<Draft>(initial)
  const [step, setStep] = useState(0)
  const [errors, setErrors] = useState<Errors>({})
  const [confirm, setConfirm] = useState(false)
  const [uploading, setUploading] = useState(false)
  const topRef = useRef<HTMLDivElement>(null)

  const set = (patch: Partial<Draft>) => {
    const next = { ...d, ...patch }
    setD(next)
    onDraftChange?.(next)
    const cleared = { ...errors }
    Object.keys(patch).forEach((k) => delete cleared[k as keyof Draft])
    setErrors(cleared)
  }

  const go = (to: number) => {
    if (to > step) {
      for (let s = step; s < to; s++) {
        const e = validate(s, d)
        if (Object.keys(e).length) {
          setStep(s)
          setErrors(e)
          requestAnimationFrame(() => document.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus())
          return
        }
      }
    }
    setErrors({})
    setStep(to)
    topRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }

  const toListing = (): Omit<Listing, 'id' | 'createdAt' | 'sellerId' | 'status'> => ({
    title: d.title.trim(),
    categoryId: d.categoryId as CategoryId,
    partName: d.partName.trim(),
    description: d.description.trim(),
    price: Number(d.price),
    negotiable: d.negotiable,
    condition: d.condition as Condition,
    conditionNote: d.conditionNote.trim() || undefined,
    oem: d.oem.trim() || undefined,
    oemIsDemo: false,
    vehicle: { make: d.make, model: d.model, generation: d.generation || undefined, year: Number(d.year), engine: d.engine || undefined },
    fitmentNotes: d.fitmentNotes.trim() || undefined,
    donorMileageKm: d.donorMileage ? Number(d.donorMileage) * 10 : undefined,
    vin: d.vin.trim() || undefined,
    city: d.city,
    postalCode: d.postalCode.trim(),
    shipping: d.shipping,
    pickup: d.pickup,
    quantity: Number(d.quantity) || 1,
    photos: d.photos,
    placeholderViews: 1,
    isUserCreated: true,
  })

  const publish = () => {
    if (!loggedIn) login()
    if (profile.sellerType !== d.sellerType) updateProfile({ ...profile, sellerType: d.sellerType })
    try {
      if (editing) {
        updateListing(editing.id, toListing())
        toast('Ändringarna sparades i din webbläsare', 'success')
        navigate(`/annons/${editing.id}`)
      } else {
        const l = createListing(toListing())
        onReset?.()
        toast('Annonsen sparades lokalt i din webbläsare', 'success')
        navigate(`/konto/annonser?ny=${l.id}`)
      }
    } catch {
      toast('Kunde inte spara annonsen. Webbläsarens lagring kan vara full.', 'error')
    }
  }

  const addPhotos = async (files: FileList | null) => {
    if (!files?.length) return
    setUploading(true)
    try {
      const room = 8 - d.photos.length
      const imgs = await Promise.all(Array.from(files).filter((f) => f.type.startsWith('image/')).slice(0, room).map(readImage))
      set({ photos: [...d.photos, ...imgs] })
      if (files.length > room) toast('Du kan ladda upp högst 8 bilder.', 'error')
    } catch {
      toast('En av bilderna kunde inte läsas.', 'error')
    } finally {
      setUploading(false)
    }
  }

  const movePhoto = (i: number, dir: -1 | 1) => {
    const p = [...d.photos]
    const j = i + dir
    if (j < 0 || j >= p.length) return
    ;[p[i], p[j]] = [p[j], p[i]]
    set({ photos: p })
  }

  const previewListing: Listing = { ...toListing(), id: 'preview', createdAt: new Date().toISOString(), sellerId: 'me', status: 'active' }

  return (
    <div className="container-page max-w-4xl pt-6" ref={topRef}>
      <Link to={editing ? `/annons/${editing.id}` : '/salj'} className="inline-flex items-center gap-1 text-sm text-gray-600 hover:text-ink">
        <ArrowLeft className="h-4 w-4" /> {editing ? 'Tillbaka till annonsen' : 'Sälja bildelar'}
      </Link>
      <h1 className="mt-3 text-2xl font-semibold tracking-tight sm:text-3xl">{editing ? 'Redigera annons' : 'Lägg upp annons'}</h1>
      <p className="mt-1 flex items-start gap-1.5 text-sm text-gray-600">
        <Info className="mt-0.5 h-4 w-4 shrink-0" aria-hidden />
        I prototypen sparas annonsen bara i din webbläsare. Den publiceras inte och syns inte för andra.
      </p>

      {/* Stepper */}
      <ol className="mt-6 grid grid-cols-6 gap-1.5" aria-label="Steg">
        {steps.map((s, i) => (
          <li key={s}>
            <button type="button" onClick={() => go(i)} className="group w-full text-left" aria-current={i === step ? 'step' : undefined}>
              <span className={cx('block h-1 rounded-full', i < step ? 'bg-brand-700' : i === step ? 'bg-brand-500' : 'bg-gray-200')} />
              <span className={cx('mt-2 hidden text-xs font-medium sm:block', i === step ? 'text-ink' : 'text-gray-500 group-hover:text-ink')}>
                {i + 1}. {s}
              </span>
            </button>
          </li>
        ))}
      </ol>
      <p className="mt-3 text-sm font-medium sm:hidden">
        Steg {step + 1} av {steps.length}: {steps[step]}
      </p>

      <form
        noValidate
        className="mt-6 card p-5 sm:p-8"
        onSubmit={(e) => {
          e.preventDefault()
          if (step < steps.length - 1) go(step + 1)
          else setConfirm(true)
        }}
      >
        {step === 0 && (
          <div className="grid gap-5">
            <Field label="Rubrik" required error={errors.title} help="Skriv vad delen är och vilken bil den kommer från, t.ex. ”Generator – Volvo V70 D5”.">
              {(id, db) => <input id={id} aria-describedby={db} aria-invalid={!!errors.title} className={cx('input', errors.title && 'input-error')} value={d.title} onChange={(e) => set({ title: e.target.value })} maxLength={90} />}
            </Field>
            <div className="grid gap-5 sm:grid-cols-2">
              <Field label="Kategori" required error={errors.categoryId}>
                {(id) => (
                  <Select id={id} invalid={!!errors.categoryId} value={d.categoryId} onChange={(e) => set({ categoryId: e.target.value as CategoryId })}>
                    <option value="">Välj kategori</option>
                    {categories.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.name}
                      </option>
                    ))}
                  </Select>
                )}
              </Field>
              <Field label="Del" required error={errors.partName} help={d.categoryId ? `T.ex. ${categoryById[d.categoryId].examples.slice(0, 3).join(', ').toLowerCase()}` : undefined}>
                {(id, db) => <input id={id} aria-describedby={db} aria-invalid={!!errors.partName} className={cx('input', errors.partName && 'input-error')} value={d.partName} onChange={(e) => set({ partName: e.target.value })} />}
              </Field>
            </div>
            <Field label="Beskrivning" required error={errors.description} help="Berätta om skick, vad som ingår och hur delen fungerade vid demontering.">
              {(id, db) => <textarea id={id} aria-describedby={db} aria-invalid={!!errors.description} rows={5} className={cx('input', errors.description && 'input-error')} value={d.description} onChange={(e) => set({ description: e.target.value })} />}
            </Field>
            <Field label="OEM-/referensnummer" help="Står ofta på en etikett eller är instansat i delen. Skriv av det exakt – det hjälper köparen att kontrollera passform.">
              {(id, db) => <input id={id} aria-describedby={db} className="input font-mono" value={d.oem} onChange={(e) => set({ oem: e.target.value })} />}
            </Field>
          </div>
        )}

        {step === 1 && (
          <div className="grid gap-5">
            <p className="text-sm text-gray-600">Uppgifter om bilen som delen kommer från (givarbilen).</p>
            <VehicleSelects
              idPrefix="sell"
              show={['make', 'model', 'generation', 'engine', 'year']}
              value={{ make: d.make, model: d.model, generation: d.generation, engine: d.engine, year: d.year }}
              onChange={(v) => set({ make: v.make, model: v.model, generation: v.generation ?? '', engine: v.engine ?? '', year: v.year })}
              errors={{ make: errors.make, model: errors.model, year: errors.year }}
              className="grid gap-5 sm:grid-cols-2"
            />
            <Field label="Chassinummer (VIN)" error={errors.vin} help="Valfritt. Visas inte publikt i den färdiga tjänsten. Avkodning av VIN är inte kopplad ännu.">
              {(id, db) => <input id={id} aria-describedby={db} aria-invalid={!!errors.vin} className={cx('input font-mono uppercase', errors.vin && 'input-error')} value={d.vin} onChange={(e) => set({ vin: e.target.value.toUpperCase() })} maxLength={17} />}
            </Field>
            <Field label="Passform enligt dig" help="Valfritt. T.ex. motorkod, före/efter facelift eller utrustning som påverkar om delen passar.">
              {(id, db) => <textarea id={id} aria-describedby={db} rows={3} className="input" value={d.fitmentNotes} onChange={(e) => set({ fitmentNotes: e.target.value })} />}
            </Field>
          </div>
        )}

        {step === 2 && (
          <div className="grid gap-6">
            <fieldset>
              <legend className="label">
                Skick <span className="text-red-600">*</span>
              </legend>
              <div className="grid gap-2 sm:grid-cols-2">
                {conditions.map((c) => (
                  <label key={c.id} className={cx('flex cursor-pointer gap-3 rounded-md border p-3 transition-colors', d.condition === c.id ? 'border-brand-700 bg-brand-50/50' : 'border-gray-200 hover:border-gray-300', errors.condition && 'border-red-300')}>
                    <input type="radio" name="condition" className="mt-0.5 h-4 w-4 accent-brand-700" checked={d.condition === c.id} onChange={() => set({ condition: c.id })} aria-invalid={!!errors.condition} />
                    <span>
                      <span className="block text-sm font-medium">{c.label}</span>
                      <span className="block text-xs text-gray-600">{c.description}</span>
                    </span>
                  </label>
                ))}
              </div>
              {errors.condition && <p className="error-text">{errors.condition}</p>}
            </fieldset>
            <Field label="Kommentar om skicket">
              {(id) => <input id={id} className="input" value={d.conditionNote} onChange={(e) => set({ conditionNote: e.target.value })} placeholder="T.ex. repa på ovansidan, fäste lagat" />}
            </Field>
            <div className="grid gap-5 sm:grid-cols-3">
              <Field label="Pris (kr)" required error={errors.price}>
                {(id) => <input id={id} inputMode="numeric" aria-invalid={!!errors.price} className={cx('input', errors.price && 'input-error')} value={d.price} onChange={(e) => set({ price: e.target.value.replace(/\D/g, '') })} />}
              </Field>
              <Field label="Givarbilens miltal" error={errors.donorMileage} help="I mil (1 mil = 10 km)">
                {(id, db) => <input id={id} aria-describedby={db} inputMode="numeric" aria-invalid={!!errors.donorMileage} className={cx('input', errors.donorMileage && 'input-error')} value={d.donorMileage} onChange={(e) => set({ donorMileage: e.target.value.replace(/\D/g, '') })} />}
              </Field>
              <Field label="Antal" required error={errors.quantity}>
                {(id) => <input id={id} inputMode="numeric" aria-invalid={!!errors.quantity} className={cx('input', errors.quantity && 'input-error')} value={d.quantity} onChange={(e) => set({ quantity: e.target.value.replace(/\D/g, '') })} />}
              </Field>
            </div>
            <label className="flex cursor-pointer items-center gap-2.5 text-sm">
              <input type="checkbox" className="h-4 w-4 accent-brand-700" checked={d.negotiable} onChange={(e) => set({ negotiable: e.target.checked })} />
              Priset kan diskuteras
            </label>
          </div>
        )}

        {step === 3 && (
          <div>
            <p className="text-sm text-gray-600">Lägg till upp till 8 bilder. Visa hela delen, eventuella skador och etiketten med referensnummer. Den första bilden blir huvudbild.</p>
            <ul className="mt-5 grid grid-cols-2 gap-3 sm:grid-cols-4">
              {d.photos.map((p, i) => (
                <li key={i} className="group relative aspect-[4/3] overflow-hidden rounded-md border border-gray-200">
                  <img src={p} alt={`Uppladdad bild ${i + 1}`} className="h-full w-full object-cover" />
                  {i === 0 && <span className="absolute left-1.5 top-1.5 rounded bg-ink/80 px-1.5 py-0.5 text-[10px] font-semibold text-white">Huvudbild</span>}
                  <div className="absolute inset-x-0 bottom-0 flex justify-between bg-gradient-to-t from-black/60 to-transparent p-1.5">
                    <div className="flex gap-1">
                      <button type="button" aria-label="Flytta vänster" disabled={i === 0} onClick={() => movePhoto(i, -1)} className="grid h-7 w-7 place-items-center rounded bg-white/90 disabled:opacity-40">
                        <ChevronLeft className="h-4 w-4" />
                      </button>
                      <button type="button" aria-label="Flytta höger" disabled={i === d.photos.length - 1} onClick={() => movePhoto(i, 1)} className="grid h-7 w-7 place-items-center rounded bg-white/90 disabled:opacity-40">
                        <ChevronRight className="h-4 w-4" />
                      </button>
                    </div>
                    <button type="button" aria-label={`Ta bort bild ${i + 1}`} onClick={() => set({ photos: d.photos.filter((_, j) => j !== i) })} className="grid h-7 w-7 place-items-center rounded bg-white/90 text-red-600">
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>
                </li>
              ))}
              {d.photos.length < 8 && (
                <li>
                  <label className="flex aspect-[4/3] cursor-pointer flex-col items-center justify-center gap-1.5 rounded-md border-2 border-dashed border-gray-300 text-sm text-gray-600 hover:border-brand-700 hover:text-brand-700 focus-within:border-brand-700">
                    <ImagePlus className="h-6 w-6" aria-hidden />
                    {uploading ? 'Laddar…' : 'Lägg till bilder'}
                    <input type="file" accept="image/*" multiple className="sr-only" onChange={(e) => addPhotos(e.target.files)} />
                  </label>
                </li>
              )}
            </ul>
            {!d.photos.length && <p className="mt-4 text-xs text-gray-500">Bilder är valfria i prototypen. Annonser utan bild visar en neutral platshållare.</p>}
          </div>
        )}

        {step === 4 && (
          <div className="grid gap-5">
            <div className="grid gap-5 sm:grid-cols-2">
              <Field label="Ort" required error={errors.city}>
                {(id) => (
                  <Select id={id} invalid={!!errors.city} value={d.city} onChange={(e) => set({ city: e.target.value })}>
                    <option value="">Välj ort</option>
                    {cities.map((c) => (
                      <option key={c}>{c}</option>
                    ))}
                  </Select>
                )}
              </Field>
              <Field label="Postnummer" required error={errors.postalCode} help="Endast de tre första siffrorna visas i annonsen.">
                {(id, db) => <input id={id} aria-describedby={db} inputMode="numeric" aria-invalid={!!errors.postalCode} className={cx('input', errors.postalCode && 'input-error')} value={d.postalCode} onChange={(e) => set({ postalCode: e.target.value })} maxLength={6} />}
              </Field>
            </div>
            <fieldset>
              <legend className="label">Leverans</legend>
              <div className="space-y-2">
                <label className="flex cursor-pointer items-center gap-2.5 text-sm">
                  <input type="checkbox" className="h-4 w-4 accent-brand-700" checked={d.pickup} onChange={(e) => set({ pickup: e.target.checked })} />
                  Kan hämtas hos mig
                </label>
                <label className="flex cursor-pointer items-center gap-2.5 text-sm">
                  <input type="checkbox" className="h-4 w-4 accent-brand-700" checked={d.shipping} onChange={(e) => set({ shipping: e.target.checked })} />
                  Kan skickas – frakt enligt överenskommelse med köparen
                </label>
              </div>
              {errors.pickup && <p className="error-text">{errors.pickup}</p>}
            </fieldset>
            <fieldset>
              <legend className="label">Jag säljer som</legend>
              <div className="grid gap-2 sm:grid-cols-2">
                {([
                  ['private', 'Privatperson', 'Säljer egna, överblivna delar.'],
                  ['professional', 'Företag', 'Bildemontering, bilskrot eller verkstad.'],
                ] as const).map(([v, label, desc]) => (
                  <label key={v} className={cx('flex cursor-pointer gap-3 rounded-md border p-3', d.sellerType === v ? 'border-brand-700 bg-brand-50/50' : 'border-gray-200 hover:border-gray-300')}>
                    <input type="radio" name="sellerType" className="mt-0.5 h-4 w-4 accent-brand-700" checked={d.sellerType === v} onChange={() => set({ sellerType: v })} />
                    <span>
                      <span className="block text-sm font-medium">{label}</span>
                      <span className="block text-xs text-gray-600">{desc}</span>
                    </span>
                  </label>
                ))}
              </div>
              <p className="help">Företag och privatpersoner har olika ansvar mot köpare enligt konsumentlagstiftningen.</p>
            </fieldset>
          </div>
        )}

        {step === 5 && (
          <div className="grid gap-8 md:grid-cols-[240px_1fr]">
            <div>
              <p className="eyebrow mb-2">Så visas kortet</p>
              <div className="pointer-events-none">
                <ListingCard listing={previewListing} />
              </div>
            </div>
            <dl className="divide-y divide-gray-100 text-sm">
              {(
                [
                  ['Rubrik', d.title, 0],
                  ['Kategori', d.categoryId ? categoryById[d.categoryId].name : '', 0],
                  ['Del', d.partName, 0],
                  ['Referensnummer', d.oem || 'Ej angivet', 0],
                  ['Givarbil', `${vehicleLabel({ make: d.make, model: d.model, generation: d.generation, engine: d.engine })}, ${d.year}`, 1],
                  ['Skick', d.condition ? <ConditionBadge condition={d.condition} /> : '', 2],
                  ['Pris', `${d.price ? formatPrice(+d.price) : ''}${d.negotiable ? ' (kan diskuteras)' : ''}`, 2],
                  ['Miltal', d.donorMileage ? formatMileage(+d.donorMileage * 10) : 'Ej angivet', 2],
                  ['Bilder', `${d.photos.length} st`, 3],
                  ['Plats', `${d.city}, ${d.postalCode}`, 4],
                  ['Leverans', [d.pickup && 'Hämtas', d.shipping && 'Skickas'].filter(Boolean).join(' eller '), 4],
                  ['Säljare', d.sellerType === 'private' ? 'Privatperson' : 'Företag', 4],
                ] as [string, React.ReactNode, number][]
              ).map(([k, v, s]) => (
                <div key={k} className="flex items-start justify-between gap-4 py-2.5">
                  <dt className="w-32 shrink-0 text-gray-500">{k}</dt>
                  <dd className="flex-1 break-words font-medium">{v}</dd>
                  <button type="button" onClick={() => go(s)} className="text-xs font-medium text-brand-700 hover:underline">
                    Ändra
                  </button>
                </div>
              ))}
              <div className="py-3">
                <dt className="text-gray-500">Beskrivning</dt>
                <dd className="mt-1 whitespace-pre-line">{d.description}</dd>
              </div>
            </dl>
          </div>
        )}

        <div className="mt-8 flex items-center justify-between gap-3 border-t border-gray-100 pt-5">
          {step > 0 ? (
            <button type="button" className="btn-secondary" onClick={() => go(step - 1)}>
              <ArrowLeft className="h-4 w-4" /> Tillbaka
            </button>
          ) : (
            <span />
          )}
          <button type="submit" className="btn-primary">
            {step < steps.length - 1 ? (
              <>
                Fortsätt <ArrowRight className="h-4 w-4" />
              </>
            ) : editing ? (
              'Spara ändringar'
            ) : (
              'Skapa annons'
            )}
          </button>
        </div>
      </form>
      {!editing && step === 0 && (d.title || d.description) && (
        <button type="button" className="mt-3 text-xs text-gray-500 underline hover:text-ink" onClick={() => { onReset?.(); setD(emptyDraft(d.sellerType, d.city, d.postalCode)) }}>
          Börja om med ett tomt formulär
        </button>
      )}

      <ConfirmDialog
        open={confirm}
        onClose={() => setConfirm(false)}
        onConfirm={publish}
        title={editing ? 'Spara ändringar?' : 'Skapa annonsen?'}
        confirmLabel={editing ? 'Spara' : 'Skapa annons'}
        body={
          <>
            Annonsen sparas <strong>endast i den här webbläsaren</strong> och hamnar under Mina annonser. Den publiceras inte på en riktig marknadsplats och ingen annan kan se den.
            {!loggedIn && <> Du loggas in som demoanvändare.</>}
          </>
        }
      />
    </div>
  )
}
