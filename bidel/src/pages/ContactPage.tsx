import { CheckCircle2 } from 'lucide-react'
import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Field, Select } from '../components/Field'
import { useStore } from '../features/AppStore'
import { cx } from '../lib/format'
import { readStore, writeStore } from '../lib/storage'

const empty = { name: '', email: '', topic: '', message: '', consent: false }

export function ContactPage() {
  const { toast } = useStore()
  const [f, setF] = useState(empty)
  const [errors, setErrors] = useState<Partial<Record<keyof typeof empty, string>>>({})
  const [sent, setSent] = useState(false)
  const set = (p: Partial<typeof empty>) => {
    setF((x) => ({ ...x, ...p }))
    setErrors((e) => {
      const n = { ...e }
      Object.keys(p).forEach((k) => delete n[k as keyof typeof empty])
      return n
    })
  }

  const submit = (e: React.FormEvent) => {
    e.preventDefault()
    const err: typeof errors = {}
    if (f.name.trim().length < 2) err.name = 'Ange ditt namn.'
    if (!/^\S+@\S+\.\S+$/.test(f.email)) err.email = 'Ange en giltig e-postadress.'
    if (!f.topic) err.topic = 'Välj ett ämne.'
    if (f.message.trim().length < 10) err.message = 'Skriv ett meddelande på minst 10 tecken.'
    if (!f.consent) err.consent = 'Du behöver godkänna att uppgifterna sparas.'
    setErrors(err)
    if (Object.keys(err).length) {
      document.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus()
      return
    }
    const ok = writeStore('contactMessages', [...readStore<unknown[]>('contactMessages', []), { ...f, at: new Date().toISOString() }])
    if (!ok) toast('Kunde inte spara meddelandet i webbläsaren', 'error')
    setSent(true)
  }

  return (
    <div className="container-page max-w-3xl pt-10 sm:pt-14">
      <p className="eyebrow">Kontakt</p>
      <h1 className="mt-2 text-3xl font-bold tracking-tight sm:text-4xl">Kontakta oss</h1>
      <p className="mt-4 text-lg leading-relaxed text-gray-600">
        Frågor, idéer eller intresse som säljare? Läs gärna <Link to="/vanliga-fragor" className="text-brand-700 underline underline-offset-2">vanliga frågor</Link> först.
      </p>

      {sent ? (
        <div className="mt-10 card p-6 animate-fade-in" role="status">
          <CheckCircle2 className="h-8 w-8 text-emerald-600" aria-hidden />
          <h2 className="mt-3 text-lg font-semibold">Meddelandet sparades lokalt</h2>
          <p className="mt-1 text-sm leading-relaxed text-gray-700">
            Tack, {f.name.split(' ')[0]}! I prototypen finns ingen e-posttjänst kopplad, så meddelandet har <strong>inte skickats</strong> – det har bara sparats i din webbläsare för
            att visa hur formuläret fungerar.
          </p>
          <button type="button" className="btn-secondary mt-5" onClick={() => { setF(empty); setSent(false) }}>
            Skriv ett nytt meddelande
          </button>
        </div>
      ) : (
        <form noValidate onSubmit={submit} className="mt-10 grid gap-5 sm:grid-cols-2">
          <Field label="Namn" required error={errors.name}>
            {(id) => <input id={id} autoComplete="name" aria-invalid={!!errors.name} className={cx('input', errors.name && 'input-error')} value={f.name} onChange={(e) => set({ name: e.target.value })} />}
          </Field>
          <Field label="E-post" required error={errors.email}>
            {(id) => <input id={id} type="email" autoComplete="email" aria-invalid={!!errors.email} className={cx('input', errors.email && 'input-error')} value={f.email} onChange={(e) => set({ email: e.target.value })} />}
          </Field>
          <Field label="Ämne" required error={errors.topic} className="sm:col-span-2">
            {(id) => (
              <Select id={id} invalid={!!errors.topic} value={f.topic} onChange={(e) => set({ topic: e.target.value })}>
                <option value="">Välj ämne</option>
                <option>Fråga om att köpa</option>
                <option>Fråga om att sälja</option>
                <option>Bildemontering / företag</option>
                <option>Synpunkter på prototypen</option>
                <option>Annat</option>
              </Select>
            )}
          </Field>
          <Field label="Meddelande" required error={errors.message} className="sm:col-span-2">
            {(id) => <textarea id={id} rows={6} aria-invalid={!!errors.message} className={cx('input', errors.message && 'input-error')} value={f.message} onChange={(e) => set({ message: e.target.value })} />}
          </Field>
          <div className="sm:col-span-2">
            <label className="flex cursor-pointer items-start gap-2.5 text-sm">
              <input type="checkbox" className="mt-0.5 h-4 w-4 accent-brand-700" checked={f.consent} aria-invalid={!!errors.consent} onChange={(e) => set({ consent: e.target.checked })} />
              <span>
                Jag godkänner att mina uppgifter sparas för att besvara meddelandet. Läs vår <Link to="/integritetspolicy" className="text-brand-700 underline">integritetspolicy</Link>.
              </span>
            </label>
            {errors.consent && <p className="error-text">{errors.consent}</p>}
          </div>
          <div className="sm:col-span-2">
            <button type="submit" className="btn-primary btn-lg">
              Skicka meddelande
            </button>
            <p className="mt-2 text-xs text-gray-500">Prototyp: meddelandet sparas bara i din webbläsare och skickas inte.</p>
          </div>
        </form>
      )}
    </div>
  )
}
