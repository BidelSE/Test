import { Link } from 'react-router-dom'
import { FutureBadge } from '../components/FutureBadge'
import { InfoLayout } from './InfoLayout'

function Step({ n, title, children, future }: { n: number; title: string; children: React.ReactNode; future?: boolean }) {
  return (
    <div className="flex gap-4 border-t border-gray-200 py-5 first:border-0">
      <span className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-brand-700 text-sm font-semibold text-white">{n}</span>
      <div>
        <h3 className="!mt-0 flex flex-wrap items-center gap-2 text-base font-semibold">
          {title} {future && <FutureBadge />}
        </h3>
        <div className="mt-1 text-[15px] leading-relaxed text-gray-700">{children}</div>
      </div>
    </div>
  )
}

export function HowItWorksPage() {
  return (
    <InfoLayout eyebrow="Så fungerar det" title="Köpa och sälja bildelar på Bidel" intro="En praktisk genomgång av hur det är tänkt att fungera – och vad som finns i prototypen i dag.">
      <h2 id="kopa">Köpa bildelar</h2>
      <div className="mt-4">
        <Step n={1} title="Sök efter delen">
          Sök med fritext, till exempel <Link to="/bildelar?q=Audi%20A4%20turbo">”Audi A4 turbo”</Link>, eller välj märke, modell och årsmodell. Har du delens referensnummer kan du
          söka direkt på det.
        </Step>
        <Step n={2} title="Jämför annonser">Jämför pris, skick, givarbilens miltal och var delen finns. Filtrera på privat- eller företagssäljare och om delen kan skickas.</Step>
        <Step n={3} title="Kontrollera passformen">
          Att delen kommer från samma märke och modell betyder inte att den passar. Jämför referensnummer, motorkod och utrustning – och fråga säljaren om du är osäker.
        </Step>
        <Step n={4} title="Kontakta säljaren">Skicka ett meddelande via annonsen. I prototypen är chatten en demonstration och svaren automatiska.</Step>
        <Step n={5} title="Gör affären" future>
          I dag kommer köpare och säljare själva överens om betalning och leverans. Säker betalning och fraktbokning via Bidel är något vi vill bygga, men det finns inte ännu.
        </Step>
      </div>

      <h2 id="salja">Sälja bildelar</h2>
      <div className="mt-4">
        <Step n={1} title="Skapa ett konto">Som privatperson eller företag. I prototypen loggar du in som demoanvändare.</Step>
        <Step n={2} title="Lägg upp en annons">
          Formuläret guidar dig genom delen, givarbilen, skick och pris, bilder och leveranssätt. <Link to="/salj/ny">Prova att skapa en annons</Link>.
        </Step>
        <Step n={3} title="Svara köpare och avsluta">Svara på frågor under Meddelanden och markera annonsen som såld när affären är klar.</Step>
      </div>

      <h2>Sökning på registreringsnummer</h2>
      <p>
        Längre fram vill vi låta dig skriva in ditt registreringsnummer för att identifiera bilen. Det kräver en behörig leverantör av fordonsdata. Att identifiera bilen är dock
        inte samma sak som att veta vilka delar som passar – för det behövs en verifierad passformskatalog. Tills dess väljer du fordon manuellt.
      </p>
    </InfoLayout>
  )
}
