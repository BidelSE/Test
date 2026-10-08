import { Link } from 'react-router-dom'
import { InfoLayout } from './InfoLayout'

export function AboutPage() {
  return (
    <InfoLayout eyebrow="Om Bidel" title="Rätt del ska vara lätt att hitta." intro="Bidel är en marknadsplats under utveckling för begagnade bildelar i Sverige – för dig som lagar bilen själv, för verkstäder och för alla som har delar som borde få komma till användning.">
      <h2>Varför Bidel finns</h2>
      <p>
        Att hitta en specifik begagnad bildel kan ta onödigt lång tid. Den turbo, styrenhet eller strålkastare du behöver finns ofta redan – i ett garage, ett förråd eller på
        en bildemontering. Men på breda annonssajter får du leta bland irrelevanta annonser, kontakta flera säljare och själv reda ut om delen passar.
      </p>
      <p>Bidel ska göra det enklare genom att bara handla om bildelar, med sökning på fordon, referensnummer och tydliga uppgifter om givarbilen och delens skick.</p>

      <h2>Varför begagnade delar</h2>
      <p>
        En begagnad originaldel är ofta ett bra alternativ till en ny – särskilt till äldre bilar där nya delar är dyra eller inte längre tillverkas. Varje del som återanvänds
        är en del som inte behöver tillverkas på nytt, och det gör det rimligare att reparera en bil i stället för att skrota den.
      </p>

      <h2>Privatpersoner och bildemonteringar</h2>
      <p>
        Bidel ska fungera lika bra för den som säljer några överblivna delar som för en bildemontering med ett stort lager. Privatpersoner och företag visas tydligt åtskilda,
        eftersom de har olika ansvar mot köpare enligt konsumentlagstiftningen.
      </p>

      <h2>Bakgrund och ambition</h2>
      <p>
        Idén kommer från specialiserade bildelsmarknader i bland annat Litauen och övriga Europa. Bidel startade som ett UF-företag under 2025. Målet är att utveckla konceptet
        till en seriös marknadsplats för hela Sverige och på sikt övriga Norden.
      </p>
      <p>
        På längre sikt vill vi bygga samarbeten med svenska bildemonteringar, så att hela lager kan nå köpare i hela landet, och erbjuda sökning på registreringsnummer med
        verifierad passformsdata. Inget av detta är i drift i dag.
      </p>

      <h2 id="prototyp">Om prototypen</h2>
      <p>Det du ser är en prototyp. Det betyder att:</p>
      <ul>
        <li>alla annonser, säljare och referensnummer är påhittade exempel,</li>
        <li>annonser, sparade annonser och meddelanden bara sparas i din egen webbläsare,</li>
        <li>det inte finns någon riktig inloggning, betalning, frakt eller sökning på registreringsnummer,</li>
        <li>inga meddelanden eller e-post skickas till någon.</li>
      </ul>
      <p>
        Har du synpunkter? <Link to="/kontakt">Kontakta oss</Link>.
      </p>
    </InfoLayout>
  )
}
