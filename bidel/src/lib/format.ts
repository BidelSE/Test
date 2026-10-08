const sek = new Intl.NumberFormat('sv-SE', { style: 'currency', currency: 'SEK', maximumFractionDigits: 0 })
const num = new Intl.NumberFormat('sv-SE')

export const formatPrice = (n: number) => sek.format(n)
export const formatNumber = (n: number) => num.format(n)
export const formatMileage = (km?: number) => (km ? `${num.format(Math.round(km / 10))} mil` : '–')

export function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('sv-SE', { day: 'numeric', month: 'short', year: 'numeric' })
}

export function formatTime(iso: string) {
  const d = new Date(iso)
  const today = new Date()
  const sameDay = d.toDateString() === today.toDateString()
  return sameDay
    ? d.toLocaleTimeString('sv-SE', { hour: '2-digit', minute: '2-digit' })
    : d.toLocaleDateString('sv-SE', { day: 'numeric', month: 'short' }) + ' ' + d.toLocaleTimeString('sv-SE', { hour: '2-digit', minute: '2-digit' })
}

export function relativeDate(iso: string) {
  const days = Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000)
  if (days <= 0) return 'Idag'
  if (days === 1) return 'Igår'
  if (days < 7) return `${days} dagar sedan`
  return formatDate(iso)
}

export function vehicleLabel(v: { make: string; model: string; generation?: string; engine?: string; year?: number }) {
  return [v.make, v.model, v.generation, v.engine].filter(Boolean).join(' ')
}

export const cx = (...parts: (string | false | null | undefined)[]) => parts.filter(Boolean).join(' ')

export const uid = (prefix = 'id') => `${prefix}-${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`
