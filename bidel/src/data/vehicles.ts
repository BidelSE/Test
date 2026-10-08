export interface Generation {
  name: string
  from: number
  to: number
  engines: string[]
}

export interface ModelDef {
  name: string
  generations: Generation[]
}

export interface MakeDef {
  name: string
  models: ModelDef[]
}

/**
 * Reference vehicle catalogue used by the manual vehicle selector.
 * Production years are approximate model-year ranges for the Swedish market.
 */
export const vehicleCatalogue: MakeDef[] = [
  {
    name: 'Audi',
    models: [
      {
        name: 'A4',
        generations: [
          { name: 'B6', from: 2001, to: 2005, engines: ['1.8T', '2.0', '1.9 TDI', '2.5 TDI', '3.0 V6'] },
          { name: 'B7', from: 2005, to: 2008, engines: ['1.8T', '2.0 TFSI', '2.0 TDI', '3.0 TDI'] },
          { name: 'B8', from: 2008, to: 2015, engines: ['1.8 TFSI', '2.0 TFSI', '2.0 TDI', '3.0 TDI'] },
        ],
      },
      {
        name: 'A6',
        generations: [
          { name: 'C6', from: 2005, to: 2011, engines: ['2.0 TFSI', '2.0 TDI', '2.7 TDI', '3.0 TDI', '3.2 FSI'] },
          { name: 'C7', from: 2011, to: 2018, engines: ['2.0 TDI', '3.0 TDI', '2.0 TFSI'] },
        ],
      },
    ],
  },
  {
    name: 'BMW',
    models: [
      {
        name: '3-serie',
        generations: [
          { name: 'E46', from: 1998, to: 2006, engines: ['318i', '320d', '325i', '330i'] },
          { name: 'E90', from: 2005, to: 2012, engines: ['318d', '320d', '320i', '325i', '330d'] },
          { name: 'F30', from: 2012, to: 2019, engines: ['318d', '320d', '320i', '330i'] },
        ],
      },
    ],
  },
  {
    name: 'Mercedes-Benz',
    models: [
      {
        name: 'E-klass',
        generations: [
          { name: 'W211', from: 2002, to: 2009, engines: ['E200 Kompressor', 'E220 CDI', 'E270 CDI', 'E320 CDI'] },
          { name: 'W212', from: 2009, to: 2016, engines: ['E200 CDI', 'E220 CDI', 'E250 CDI', 'E350 CDI'] },
        ],
      },
    ],
  },
  {
    name: 'Saab',
    models: [
      {
        name: '9-3',
        generations: [
          { name: 'II (YS3F)', from: 2003, to: 2011, engines: ['1.8t', '2.0t', '2.0T', '1.9 TiD', '2.8 V6 Turbo'] },
        ],
      },
      {
        name: '9-5',
        generations: [{ name: 'I (YS3E)', from: 1998, to: 2010, engines: ['2.0t', '2.3t', '2.3T', '3.0 TiD'] }],
      },
    ],
  },
  {
    name: 'Skoda',
    models: [
      {
        name: 'Octavia',
        generations: [
          { name: 'II (1Z)', from: 2004, to: 2013, engines: ['1.6 TDI', '1.9 TDI', '2.0 TDI', '1.8 TSI', '2.0 TFSI RS'] },
          { name: 'III (5E)', from: 2013, to: 2020, engines: ['1.4 TSI', '1.6 TDI', '2.0 TDI'] },
        ],
      },
    ],
  },
  {
    name: 'Volkswagen',
    models: [
      {
        name: 'Golf',
        generations: [
          { name: 'Mk5', from: 2004, to: 2008, engines: ['1.4 TSI', '1.9 TDI', '2.0 TDI', '2.0 TFSI GTI'] },
          { name: 'Mk6', from: 2008, to: 2012, engines: ['1.2 TSI', '1.4 TSI', '1.6 TDI', '2.0 TDI', '2.0 TSI GTI'] },
          { name: 'Mk7', from: 2012, to: 2019, engines: ['1.4 TSI', '1.6 TDI', '2.0 TDI', '2.0 TSI GTI'] },
        ],
      },
      {
        name: 'Passat',
        generations: [
          { name: 'B6', from: 2005, to: 2010, engines: ['1.9 TDI', '2.0 TDI', '2.0 TFSI'] },
          { name: 'B7', from: 2010, to: 2014, engines: ['1.6 TDI', '2.0 TDI', '1.4 TSI EcoFuel'] },
        ],
      },
    ],
  },
  {
    name: 'Volvo',
    models: [
      {
        name: 'V70',
        generations: [
          { name: 'II (P2)', from: 2000, to: 2007, engines: ['2.4', '2.4T', '2.5T', 'D5', '2.4D'] },
          { name: 'III (P3)', from: 2007, to: 2016, engines: ['2.0', 'D3', 'D4', 'D5', 'T6'] },
        ],
      },
      {
        name: 'V50',
        generations: [{ name: 'P1', from: 2004, to: 2012, engines: ['1.8', '2.4', 'T5', '1.6D', '2.0D', 'D5'] }],
      },
      {
        name: 'XC70',
        generations: [{ name: 'II (P3)', from: 2007, to: 2016, engines: ['D4', 'D5', 'T6'] }],
      },
    ],
  },
]

export const makes = vehicleCatalogue.map((m) => m.name)

export function modelsFor(make: string): ModelDef[] {
  return vehicleCatalogue.find((m) => m.name === make)?.models ?? []
}

export function generationsFor(make: string, model: string): Generation[] {
  return modelsFor(make).find((m) => m.name === model)?.generations ?? []
}

export function enginesFor(make: string, model: string, generation?: string): string[] {
  const gens = generationsFor(make, model).filter((g) => !generation || g.name === generation)
  return Array.from(new Set(gens.flatMap((g) => g.engines)))
}

export function yearsFor(make: string, model: string): number[] {
  const gens = generationsFor(make, model)
  if (!gens.length) {
    const now = new Date().getFullYear()
    return Array.from({ length: now - 1990 + 1 }, (_, i) => now - i)
  }
  const from = Math.min(...gens.map((g) => g.from))
  const to = Math.max(...gens.map((g) => g.to))
  return Array.from({ length: to - from + 1 }, (_, i) => to - i)
}

/**
 * Clearly fictional registration numbers used to demonstrate where a future
 * registration lookup would plug in. No real vehicle data is queried.
 */
export const demoPlates: Record<string, { make: string; model: string; generation: string; year: number; engine: string }> = {
  'DEM001': { make: 'Audi', model: 'A4', generation: 'B6', year: 2003, engine: '1.8T' },
  'DEM002': { make: 'Volvo', model: 'V70', generation: 'II (P2)', year: 2006, engine: 'D5' },
  'DEM003': { make: 'Volkswagen', model: 'Golf', generation: 'Mk6', year: 2010, engine: '1.6 TDI' },
}
