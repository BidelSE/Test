import { Link } from 'react-router-dom'
import { InfoLayout } from './InfoLayout'

const pages = {
  integritet: {
    title: 'Integritetspolicy',
    body: (
      <>
        <p>Den här sidan är en platshållare. Bidel är en prototyp och någon slutlig integritetspolicy har inte tagits fram.</p>
        <h2>Vad prototypen sparar</h2>
        <p>
          Prototypen har ingen server. Annonser, sparade annonser, meddelanden, profiluppgifter och kontaktformulär sparas endast i din webbläsares lokala lagring på din egen
          enhet. Du kan radera allt under Mitt konto → Inställningar eller genom att rensa webbplatsdata i webbläsaren.
        </p>
        <h2>Den färdiga tjänsten</h2>
        <p>
          När Bidel lanseras kommer personuppgifter att behandlas enligt dataskyddsförordningen (GDPR). Policyn kommer bland annat att beskriva vilka uppgifter som samlas in,
          varför, hur länge de sparas och hur du utövar dina rättigheter.
        </p>
      </>
    ),
  },
  villkor: {
    title: 'Användarvillkor',
    body: (
      <>
        <p>Den här sidan är en platshållare. Användarvillkor för den färdiga tjänsten är inte framtagna.</p>
        <p>
          Prototypen är till för att visa hur marknadsplatsen är tänkt att fungera. Inga riktiga köp, försäljningar eller avtal kan ingås via prototypen, och alla annonser är
          påhittade.
        </p>
      </>
    ),
  },
  cookies: {
    title: 'Cookies',
    body: (
      <>
        <p>Prototypen använder inga cookies för spårning eller marknadsföring.</p>
        <p>
          Webbläsarens lokala lagring (localStorage) används för att komma ihåg dina demoannonser, sparade annonser, meddelanden och inställningar. Uppgifterna lämnar aldrig din
          enhet.
        </p>
      </>
    ),
  },
}

export function LegalPage({ page }: { page: keyof typeof pages }) {
  const p = pages[page]
  return (
    <InfoLayout eyebrow="Villkor" title={p.title}>
      {p.body}
      <p className="!mt-10 text-sm">
        Frågor? <Link to="/kontakt">Kontakta oss</Link>.
      </p>
    </InfoLayout>
  )
}
