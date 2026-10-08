import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ConfirmDialog } from '../../components/Dialog'
import { FutureBadge } from '../../components/FutureBadge'
import { useStore } from '../../features/AppStore'
import type { UserSettings } from '../../types'

export function SettingsPage() {
  const { settings, updateSettings, logout, resetDemo, toast } = useStore()
  const [confirmReset, setConfirmReset] = useState(false)
  const navigate = useNavigate()
  const toggle = (k: keyof UserSettings) => {
    updateSettings({ ...settings, [k]: !settings[k] })
    toast('Inställningen sparades')
  }
  const rows: [keyof UserSettings, string, string, boolean][] = [
    ['emailNotifications', 'E-post vid nya meddelanden', 'Inga e-postmeddelanden skickas i prototypen.', true],
    ['showPhone', 'Visa telefonnummer i mina annonser', 'Av som standard för att skydda dina personuppgifter.', false],
    ['newsletter', 'Nyheter om Bidel', 'Information när tjänsten utvecklas.', true],
  ]
  return (
    <div className="max-w-2xl">
      <h2 className="text-lg font-semibold">Inställningar</h2>
      <ul className="mt-4 divide-y divide-gray-100 rounded-lg border border-gray-200">
        {rows.map(([k, label, help, future]) => (
          <li key={k} className="flex items-center justify-between gap-4 p-4">
            <div>
              <p className="flex flex-wrap items-center gap-2 text-sm font-medium">
                {label} {future && <FutureBadge />}
              </p>
              <p className="mt-0.5 text-xs text-gray-600">{help}</p>
            </div>
            <button
              type="button"
              role="switch"
              aria-checked={settings[k]}
              aria-label={label}
              onClick={() => toggle(k)}
              className={`relative h-6 w-11 shrink-0 rounded-full transition-colors ${settings[k] ? 'bg-brand-700' : 'bg-gray-300'}`}
            >
              <span className={`absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-transform ${settings[k] ? 'translate-x-5' : 'translate-x-0.5'}`} />
            </button>
          </li>
        ))}
      </ul>

      <h3 className="mt-10 font-semibold">Demodata</h3>
      <p className="mt-1 text-sm text-gray-600">Allt du gör i prototypen sparas i webbläsarens lokala lagring.</p>
      <div className="mt-4 flex flex-wrap gap-2">
        <button
          type="button"
          className="btn-secondary"
          onClick={() => {
            logout()
            navigate('/')
          }}
        >
          Logga ut
        </button>
        <button type="button" className="btn-secondary text-red-600" onClick={() => setConfirmReset(true)}>
          Återställ demodata
        </button>
      </div>
      <ConfirmDialog
        open={confirmReset}
        onClose={() => setConfirmReset(false)}
        onConfirm={resetDemo}
        title="Återställ demodata?"
        body="Dina skapade annonser, sparade annonser, meddelanden och profiländringar raderas från den här webbläsaren."
        confirmLabel="Återställ"
        danger
      />
    </div>
  )
}
