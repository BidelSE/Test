import type { MyCar, VehicleRef } from '../types'

export type MatchLevel = 'engine' | 'generation' | 'model' | null

/**
 * Compares a listing's donor vehicle with the visitor's saved car.
 * This only says how similar the two vehicles are. It never says a part fits:
 * that needs reference numbers or a verified fitment catalogue.
 */
export function matchLevel(car: MyCar | null, donor: VehicleRef): MatchLevel {
  if (!car || car.make !== donor.make || car.model !== donor.model) return null
  const sameGen = !!car.generation && car.generation === donor.generation
  const genUnknown = !car.generation || !donor.generation
  if (!sameGen && !genUnknown) return null
  if (sameGen && car.engine && car.engine === donor.engine) return 'engine'
  if (sameGen) return 'generation'
  return 'model'
}

export const matchCopy: Record<Exclude<MatchLevel, null>, { short: string; long: string }> = {
  engine: { short: 'Samma modell och motor', long: 'Givarbilen är samma modell, generation och motor som din bil.' },
  generation: { short: 'Samma generation', long: 'Givarbilen är samma modell och generation som din bil, men motorn skiljer sig eller är okänd.' },
  model: { short: 'Samma modell', long: 'Givarbilen är samma modell som din bil. Generationen är okänd eller inte angiven.' },
}

export function carLabel(c: MyCar) {
  return [c.make, c.model, c.generation, c.engine].filter(Boolean).join(' ') + `, ${c.year}`
}
