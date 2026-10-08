import { ChevronDown } from 'lucide-react'
import { Link } from 'react-router-dom'
import { InfoLayout } from './InfoLayout'

const faq: { group: string; items: [string, React.ReactNode][] }[] = [
  {
    group: 'Köpa',
    items: [
      ['Hur köper jag en del?', 'Kontakta säljaren via annonsen och kom överens om pris, betalning och leverans. Bidel hanterar inte köpet i dag.'],
      ['Kan jag lita på att delen passar min bil?', 'Nej, inte enbart utifrån annonsen. Bidel kontrollerar inte passform. Jämför referensnummer, motorkod och utrustning, och fråga säljaren innan du köper.'],
      ['Vad betyder skicken?', <>Skicket anges av säljaren enligt fem nivåer, från <em>Ny / oanvänd</em> till <em>Renoveringsobjekt</em>. Läs alltid beskrivningen och titta på bilderna.</>],
    ],
  },
  {
    group: 'Sälja',
    items: [
      ['Kostar det något att sälja?', 'Planen är att inte ta ut några säljavgifter under det första året efter lansering. Prissättning därefter är inte bestämd.'],
      ['Vad är skillnaden mellan privat- och företagssäljare?', 'Företag som säljer till konsumenter har andra skyldigheter, till exempel enligt konsumentköplagen och reglerna om ångerrätt vid distansköp. Därför visas säljartypen tydligt i varje annons.'],
      ['Hur skriver jag en bra annons?', 'Ange referensnumret, givarbilens märke, modell, årsmodell och motor, samt ärliga uppgifter om skick. Ta bilder på hela delen och eventuella skador.'],
    ],
  },
  {
    group: 'Betalning, frakt och retur',
    items: [
      ['Kan jag betala via Bidel?', 'Nej. Betalning via Bidel, köparskydd och liknande tjänster finns inte. Hur det ska fungera i den färdiga tjänsten är inte bestämt.'],
      ['Hur fungerar frakt?', 'Säljaren anger om delen kan skickas. Köpare och säljare kommer själva överens om fraktsätt och kostnad. Fraktbokning via Bidel finns inte ännu.'],
      ['Kan jag returnera en del?', 'Det beror på vem du köper av. Köper du av ett företag har du som konsument i regel lagstadgade rättigheter. Köp mellan privatpersoner styrs av vad ni kommer överens om. Bidel har ännu ingen egen returpolicy.'],
    ],
  },
  {
    group: 'Prototypen',
    items: [
      ['Är annonserna riktiga?', 'Nej. Alla annonser, säljare och referensnummer är påhittade demonstrationsexempel.'],
      ['Var sparas det jag gör?', 'I din webbläsares lokala lagring. Du kan återställa allt under Mitt konto → Inställningar.'],
    ],
  },
]

export function FaqPage() {
  return (
    <InfoLayout eyebrow="Hjälp" title="Vanliga frågor" intro={<>Hittar du inte svaret? <Link to="/kontakt" className="text-brand-700 underline underline-offset-2">Kontakta oss</Link>.</>}>
      {faq.map((g) => (
        <section key={g.group}>
          <h2>{g.group}</h2>
          <div className="mt-3 divide-y divide-gray-200 border-y border-gray-200">
            {g.items.map(([q, a]) => (
              <details key={q} className="group py-1">
                <summary className="flex cursor-pointer list-none items-center justify-between gap-4 rounded py-3 text-[15px] font-medium [&::-webkit-details-marker]:hidden">
                  {q}
                  <ChevronDown className="h-4 w-4 shrink-0 text-gray-500 transition-transform group-open:rotate-180" aria-hidden />
                </summary>
                <p className="!mt-0 pb-4 pr-8">{a}</p>
              </details>
            ))}
          </div>
        </section>
      ))}
    </InfoLayout>
  )
}
