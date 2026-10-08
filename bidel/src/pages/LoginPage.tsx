import { Info } from 'lucide-react'
import { useLocation, useNavigate } from 'react-router-dom'
import { Wordmark } from '../components/Wordmark'
import { useStore } from '../features/AppStore'

export function LoginPage() {
  const { login } = useStore()
  const navigate = useNavigate()
  const location = useLocation()
  const next = (location.state as { next?: string } | null)?.next ?? '/konto'
  return (
    <div className="container-page flex justify-center py-16">
      <div className="w-full max-w-sm">
        <LoginCard
          onLogin={() => {
            login()
            navigate(next, { replace: true })
          }}
        />
      </div>
    </div>
  )
}

export function LoginCard({ onLogin }: { onLogin: () => void }) {
  return (
    <div className="card p-6 sm:p-8">
      <Wordmark className="text-xl" />
      <h1 className="mt-5 text-xl font-semibold tracking-tight">Logga in</h1>
      <div className="mt-3 flex gap-2 rounded-md bg-surface p-3 text-sm text-gray-700">
        <Info className="mt-0.5 h-4 w-4 shrink-0 text-gray-500" aria-hidden />
        <p>Riktig inloggning finns inte ännu. Fortsätt som demoanvändare – allt du gör sparas bara i den här webbläsaren.</p>
      </div>
      <button type="button" className="btn-primary btn-lg mt-5 w-full" onClick={onLogin}>
        Fortsätt som demoanvändare
      </button>
      <div className="mt-6 space-y-3 opacity-60" aria-hidden>
        <input className="input" placeholder="E-postadress" disabled />
        <input className="input" placeholder="Lösenord" type="password" disabled />
        <button type="button" className="btn-secondary w-full" disabled>
          Logga in med e-post (kommer senare)
        </button>
      </div>
    </div>
  )
}
