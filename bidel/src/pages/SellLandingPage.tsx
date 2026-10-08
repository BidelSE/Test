import { Camera, ClipboardList, MessageSquare, Plus } from 'lucide-react'
import { Link } from 'react-router-dom'

export function SellLandingPage() {
  return (
    <>
      <section className="border-b border-gray-200 bg-surface">
        <div className="container-page py-12 sm:py-16">
          <p className="eyebrow">Sälj bildelar</p>
          <h1 className="mt-2 max-w-2xl text-3xl font-bold leading-tight tracking-tight sm:text-5xl">Har du delar som ligger och samlar damm?</h1>
          <p className="mt-4 max-w-xl text-base leading-relaxed text-gray-600 sm:text-lg">
            Lägg upp dem på Bidel och nå motorister som letar efter just den delen. Fungerar för privatpersoner med några överblivna delar och för bildemonteringar med stora lager.
          </p>
          <div className="mt-7 flex flex-wrap gap-3">
            <Link to="/salj/ny" className="btn-primary btn-lg">
              <Plus className="h-4 w-4" /> Skapa annons
            </Link>
            <Link to="/sa-fungerar-det#salja" className="btn-secondary btn-lg">
              Så fungerar det
            </Link>
          </div>
        </div>
      </section>

      <section className="container-page pt-14">
        <h2 className="text-xl font-semibold tracking-tight">En bra annons på några minuter</h2>
        <div className="mt-6 grid gap-4 md:grid-cols-3">
          {[
            [ClipboardList, 'Beskriv delen', 'Rubrik, kategori och referensnummer. Ju mer exakt, desto lättare för köparen att veta om delen passar.'],
            [Camera, 'Ta bra bilder', 'Visa hela delen, eventuella skador och etiketten med referensnummer.'],
            [MessageSquare, 'Svara på frågor', 'Köpare kontaktar dig via meddelanden. Ni kommer själva överens om betalning och frakt.'],
          ].map(([Icon, t, d]) => {
            const I = Icon as typeof Camera
            return (
              <div key={t as string} className="card p-6">
                <I className="h-6 w-6 text-brand-700" strokeWidth={1.5} aria-hidden />
                <h3 className="mt-4 font-semibold">{t as string}</h3>
                <p className="mt-1.5 text-sm leading-relaxed text-gray-600">{d as string}</p>
              </div>
            )
          })}
        </div>
      </section>

      <section className="container-page pt-14">
        <div className="grid gap-6 md:grid-cols-2">
          <div className="card p-6">
            <h2 className="text-lg font-semibold">Privatpersoner</h2>
            <p className="mt-2 text-sm leading-relaxed text-gray-600">
              Delar över efter ett bygge, en skrotad bil eller vinterhjul som inte passar den nya bilen. Lägg upp en annons per del eller set och välj om du kan skicka.
            </p>
          </div>
          <div className="card p-6">
            <h2 className="text-lg font-semibold">Bildemonteringar och företag</h2>
            <p className="mt-2 text-sm leading-relaxed text-gray-600">
              Företagsprofil med kontaktuppgifter och öppettider. Längre fram vill vi erbjuda import av hela lager och integration med lagersystem – det finns inte i prototypen.
            </p>
          </div>
        </div>
        <div className="mt-6 rounded-lg border border-gray-200 p-5 text-sm leading-relaxed text-gray-700">
          <strong className="font-semibold">Avgifter:</strong> Planen är att inte ta ut några säljavgifter under det första året efter lansering. Hur prissättningen ser ut därefter är inte bestämt.
        </div>
      </section>
    </>
  )
}
