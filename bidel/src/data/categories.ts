import type { Category, CategoryId, Condition } from '../types'

export const categories: Category[] = [
  { id: 'motor', name: 'Motor & motordelar', short: 'Motor', examples: ['Motor', 'Topplock', 'Insprutare', 'Startmotor', 'Generator'] },
  { id: 'vaxellada', name: 'Växellåda & transmission', short: 'Växellåda', examples: ['Växellåda', 'Koppling', 'Drivaxel', 'Kardanaxel'] },
  { id: 'broms', name: 'Bromssystem', short: 'Bromsar', examples: ['Bromsok', 'Bromsskivor', 'ABS-enhet', 'Bromsservo'] },
  { id: 'fjadring', name: 'Fjädring & styrning', short: 'Fjädring', examples: ['Stötdämpare', 'Länkarm', 'Styrväxel', 'Fjäder'] },
  { id: 'elektronik', name: 'Elektronik', short: 'Elektronik', examples: ['Motorstyrenhet', 'Instrumentkluster', 'Radio', 'Komfortmodul'] },
  { id: 'kaross', name: 'Karossdelar', short: 'Kaross', examples: ['Dörr', 'Motorhuv', 'Stötfångare', 'Sidospegel', 'Skärm'] },
  { id: 'belysning', name: 'Belysning', short: 'Belysning', examples: ['Strålkastare', 'Baklykta', 'Dimljus', 'Xenonenhet'] },
  { id: 'avgas', name: 'Avgassystem', short: 'Avgas', examples: ['Katalysator', 'Partikelfilter', 'Ljuddämpare', 'Grenrör'] },
  { id: 'turbo', name: 'Turbo & insug', short: 'Turbo', examples: ['Turbo', 'Laddluftkylare', 'Insugsrör', 'Luftmassemätare'] },
  { id: 'interior', name: 'Interiör', short: 'Interiör', examples: ['Säten', 'Ratt', 'Mittkonsol', 'Klädsel'] },
  { id: 'hjul', name: 'Fälgar & hjul', short: 'Hjul', examples: ['Aluminiumfälgar', 'Kompletta hjul', 'Navkapslar'] },
  { id: 'kylsystem', name: 'Kylsystem', short: 'Kylning', examples: ['Kylare', 'Vattenpump', 'Termostat', 'AC-kondensor'] },
]

export const categoryById = Object.fromEntries(categories.map((c) => [c.id, c])) as Record<CategoryId, Category>

export const conditions: { id: Condition; label: string; description: string }[] = [
  { id: 'ny', label: 'Ny / oanvänd', description: 'Aldrig monterad. Kan sakna originalförpackning.' },
  { id: 'mycket-bra', label: 'Mycket bra skick', description: 'Begagnad med minimala bruksspår. Fungerade vid demontering.' },
  { id: 'bra', label: 'Bra skick', description: 'Normala bruksspår för åldern. Fungerade vid demontering.' },
  { id: 'godtagbar', label: 'Godtagbart skick', description: 'Tydliga bruksspår eller kosmetiska skador. Se beskrivning.' },
  { id: 'renovering', label: 'Renoveringsobjekt', description: 'Defekt eller ej testad. Säljs för renovering eller reservdelar.' },
]

export const conditionLabel = Object.fromEntries(conditions.map((c) => [c.id, c.label])) as Record<Condition, string>

export const cities = [
  'Stockholm',
  'Göteborg',
  'Malmö',
  'Uppsala',
  'Västerås',
  'Örebro',
  'Linköping',
  'Jönköping',
  'Sundsvall',
  'Umeå',
  'Örnsköldsvik',
  'Luleå',
] as const
