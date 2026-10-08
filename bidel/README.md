# Bidel – prototyp

Interaktiv frontend-prototyp för Bidel, en svensk marknadsplats för begagnade bildelar.
Alla annonser, säljare och referensnummer är påhittade demonstrationsexempel.

## Kom igång

```bash
cd bidel
npm install
npm run dev      # utvecklingsserver på http://localhost:5173
npm run build    # typkontroll + produktionsbygge till dist/
```

## Struktur

```
src/
  components/   Delade UI-komponenter (kort, header, formulärfält, dialoger)
  pages/        Sidor, inklusive account/ för Mitt konto
  features/     Applikationstillstånd (AppStore: favoriter, annonser, chatt, profil)
  data/         Demodata: kategorier, fordonskatalog, annonser, säljare, konversationer
  hooks/        useStoredState (localStorage-backat state)
  lib/          Formatering, sökning/filtrering, lagring
  types/        TypeScript-typer för datamodellen
  styles/       Tailwind v4 och designtokens
```

## Vad som fungerar

- Sök med fritext, fordon (märke/modell/generation/motor/år), referensnummer
- Filter på kategori, pris, skick, säljartyp, ort och frakt – sparas i URL:en
- Annonssidor med galleri, passformsinformation och tekniska uppgifter
- Spara annonser, demochatt med automatiska svar
- Skapa och redigera annonser i sex steg med validering och bilduppladdning
- Mitt konto: översikt, mina annonser (sålt/ta bort), sparade, meddelanden, profil, inställningar
- Säljarprofiler för privatpersoner och företag
- Om Bidel, Så fungerar det, Vanliga frågor, Kontakt och villkorssidor

Allt sparas i webbläsarens localStorage. Återställ under Mitt konto → Inställningar.

## Inte implementerat (framtida integrationer)

Riktig inloggning, databas, betalning och köparskydd, sökning på registreringsnummer,
VIN-avkodning och passformsmatchning, fraktbokning, realtidschatt, e-post och lagerintegration
för bildemonteringar.

## Enfilsversion

`npm run build:single` bygger en fristående HTML-fil (`dist-single/bidel.html`) med hash-routing
och inbäddad CSS/JS, för att kunna visas där det inte finns någon server, t.ex. som artifact.
