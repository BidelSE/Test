import type { Seller } from '../types'

/**
 * Fictional demonstration sellers. Business names are invented for the
 * prototype and do not refer to real companies.
 */
export const sellers: Seller[] = [
  {
    id: 's-norrkust',
    type: 'professional',
    displayName: 'Norrkust Bildemontering',
    companyName: 'Norrkust Bildemontering (demoföretag)',
    city: 'Örnsköldsvik',
    region: 'Västernorrland',
    description:
      'Demonterar personbilar med fokus på svenska och tyska märken. Delarna testas i den mån det går innan demontering och märks med givarbilens uppgifter.',
    memberSince: '2025-03-01',
    website: 'exempel.se',
    businessEmail: 'kontakt@exempel.se',
    openingHours: 'Mån–fre 08–16',
  },
  {
    id: 's-malardalen',
    type: 'professional',
    displayName: 'Mälardalens Bildelar',
    companyName: 'Mälardalens Bildelar (demoföretag)',
    city: 'Västerås',
    region: 'Västmanland',
    description:
      'Begagnade reservdelar till Volvo, Saab och VAG-koncernens bilar. Vi skickar mindre delar med paket och har upphämtning på plats.',
    memberSince: '2025-05-12',
    website: 'exempel.se',
    businessEmail: 'info@exempel.se',
    openingHours: 'Mån–fre 07–16, lör 10–13',
  },
  {
    id: 's-soderslatt',
    type: 'professional',
    displayName: 'Söderslätt Bilåtervinning',
    companyName: 'Söderslätt Bilåtervinning (demoföretag)',
    city: 'Malmö',
    region: 'Skåne',
    description: 'Bilåtervinning i Skåne. Inriktning på BMW och Mercedes-Benz men vi har delar till de flesta vanliga modeller.',
    memberSince: '2025-08-20',
    openingHours: 'Mån–tor 08–17, fre 08–15',
  },
  {
    id: 's-erik',
    type: 'private',
    displayName: 'Erik L.',
    city: 'Umeå',
    region: 'Västerbotten',
    description: 'Har skruvat på Audi och VW i många år. Säljer delar som blivit över efter projekt.',
    memberSince: '2025-04-03',
  },
  {
    id: 's-sara',
    type: 'private',
    displayName: 'Sara K.',
    city: 'Göteborg',
    region: 'Västra Götaland',
    description: 'Säljer delar från vår gamla V70 som skrotades efter en rostig bakaxel.',
    memberSince: '2025-09-15',
  },
  {
    id: 's-johan',
    type: 'private',
    displayName: 'Johan B.',
    city: 'Uppsala',
    region: 'Uppsala',
    description: 'BMW-entusiast. Bygger om en E90 och säljer originaldelar som byts ut.',
    memberSince: '2025-06-22',
  },
  {
    id: 's-amir',
    type: 'private',
    displayName: 'Amir H.',
    city: 'Stockholm',
    region: 'Stockholm',
    description: 'Säljer överblivna delar från garaget.',
    memberSince: '2025-10-01',
  },
  {
    id: 's-linnea',
    type: 'private',
    displayName: 'Linnea S.',
    city: 'Sundsvall',
    region: 'Västernorrland',
    description: 'Saab-ägare sedan länge. Rensar förrådet.',
    memberSince: '2025-07-11',
  },
]

/** The signed-in demonstration user. Their listings live in local storage. */
export const ME_ID = 'me'
