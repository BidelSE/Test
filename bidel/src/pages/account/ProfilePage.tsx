import { useState } from 'react'
import { Field, Select } from '../../components/Field'
import { cities } from '../../data/categories'
import { useStore } from '../../features/AppStore'
import { cx } from '../../lib/format'
import type { UserProfile } from '../../types'

export function ProfilePage() {
  const { profile, updateProfile, toast } = useStore()
  const [p, setP] = useState<UserProfile>(profile)
  const [errors, setErrors] = useState<Partial<Record<keyof UserProfile, string>>>({})
  const set = (patch: Partial<UserProfile>) => setP((x) => ({ ...x, ...patch }))
  const pro = p.sellerType === 'professional'

  const save = (e: React.FormEvent) => {
    e.preventDefault()
    const err: typeof errors = {}
    if (p.displayName.trim().length < 2) err.displayName = 'Ange ett visningsnamn.'
    if (!/^\S+@\S+\.\S+$/.test(p.email)) err.email = 'Ange en giltig e-postadress.'
    if (!/^\d{3}\s?\d{2}$/.test(p.postalCode.trim())) err.postalCode = 'Ange ett postnummer med fem siffror.'
    if (pro && !p.companyName?.trim()) err.companyName = 'Ange företagets namn.'
    if (pro && p.orgNumber && !/^\d{6}-?\d{4}$/.test(p.orgNumber.trim())) err.orgNumber = 'Organisationsnummer skrivs som 10 siffror, t.ex. 556000-0000.'
    setErrors(err)
    if (Object.keys(err).length) return
    updateProfile(p)
    toast('Profilen sparades i webbläsaren', 'success')
  }

  const input = (k: keyof UserProfile, props: React.InputHTMLAttributes<HTMLInputElement> = {}) => (id: string, db?: string) => (
    <input id={id} aria-describedby={db} aria-invalid={!!errors[k]} className={cx('input', errors[k] && 'input-error')} value={(p[k] as string) ?? ''} onChange={(e) => set({ [k]: e.target.value })} {...props} />
  )

  return (
    <form onSubmit={save} noValidate className="max-w-2xl">
      <h2 className="text-lg font-semibold">Profil</h2>
      <p className="mt-1 text-sm text-gray-600">Uppgifterna är påhittade och sparas bara i din webbläsare.</p>
      <fieldset className="mt-6">
        <legend className="label">Kontotyp</legend>
        <div className="grid gap-2 sm:grid-cols-2">
          {([
            ['private', 'Privatperson'],
            ['professional', 'Företag'],
          ] as const).map(([v, l]) => (
            <label key={v} className={cx('flex cursor-pointer items-center gap-2.5 rounded-md border p-3 text-sm font-medium', p.sellerType === v ? 'border-brand-700 bg-brand-50/50' : 'border-gray-200')}>
              <input type="radio" name="type" className="h-4 w-4 accent-brand-700" checked={p.sellerType === v} onChange={() => set({ sellerType: v })} />
              {l}
            </label>
          ))}
        </div>
      </fieldset>
      <div className="mt-5 grid gap-5 sm:grid-cols-2">
        <Field label="Visningsnamn" required error={errors.displayName} help={pro ? undefined : 'Visas för köpare. Vi rekommenderar förnamn och initial.'}>
          {input('displayName')}
        </Field>
        <Field label="E-post" required error={errors.email} help="Visas inte publikt.">
          {input('email', { type: 'email' })}
        </Field>
        <Field label="Telefon">{input('phone', { type: 'tel' })}</Field>
        <Field label="Ort">
          {(id) => (
            <Select id={id} value={p.city} onChange={(e) => set({ city: e.target.value })}>
              {cities.map((c) => (
                <option key={c}>{c}</option>
              ))}
            </Select>
          )}
        </Field>
        <Field label="Postnummer" required error={errors.postalCode}>
          {input('postalCode', { inputMode: 'numeric', maxLength: 6 })}
        </Field>
      </div>
      {pro && (
        <div className="mt-5 grid gap-5 rounded-lg border border-gray-200 p-4 sm:grid-cols-2">
          <p className="text-sm font-semibold sm:col-span-2">Företagsuppgifter</p>
          <Field label="Företagsnamn" required error={errors.companyName}>
            {input('companyName')}
          </Field>
          <Field label="Organisationsnummer" error={errors.orgNumber} help="Kontrolleras inte i prototypen.">
            {input('orgNumber', { inputMode: 'numeric' })}
          </Field>
          <Field label="Webbplats" className="sm:col-span-2">
            {input('website', { type: 'url', placeholder: 'https://' })}
          </Field>
        </div>
      )}
      <Field label="Om mig" className="mt-5">
        {(id) => <textarea id={id} rows={4} className="input" value={p.description} onChange={(e) => set({ description: e.target.value })} />}
      </Field>
      <div className="mt-6 flex gap-2">
        <button type="submit" className="btn-primary">
          Spara profil
        </button>
        <button type="button" className="btn-secondary" onClick={() => { setP(profile); setErrors({}) }}>
          Ångra ändringar
        </button>
      </div>
    </form>
  )
}
