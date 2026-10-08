import { enginesFor, generationsFor, makes, modelsFor, yearsFor } from '../data/vehicles'
import { Select } from './Field'

export interface VehicleValue {
  make: string
  model: string
  generation?: string
  engine?: string
  year: string
}

/** Cascading make → model → (generation) → (engine) → year selectors backed by the reference catalogue. */
export function VehicleSelects({
  value,
  onChange,
  show = ['make', 'model', 'year'],
  className,
  idPrefix = 'veh',
  labels = true,
  errors = {},
}: {
  value: VehicleValue
  onChange: (v: VehicleValue) => void
  show?: ('make' | 'model' | 'generation' | 'engine' | 'year')[]
  className?: string
  idPrefix?: string
  labels?: boolean
  errors?: Partial<Record<'make' | 'model' | 'year', string>>
}) {
  const models = modelsFor(value.make)
  const gens = generationsFor(value.make, value.model)
  const engines = enginesFor(value.make, value.model, value.generation)
  const years = (() => {
    const all = yearsFor(value.make, value.model)
    const g = gens.find((x) => x.name === value.generation)
    return g ? all.filter((y) => y >= g.from && y <= g.to) : all
  })()

  const field = (key: 'make' | 'model' | 'generation' | 'engine' | 'year', label: string, el: React.ReactNode) =>
    show.includes(key) && (
      <div key={key}>
        <label htmlFor={`${idPrefix}-${key}`} className={labels ? 'label' : 'sr-only'}>
          {label}
        </label>
        {el}
        {errors[key as 'make'] && <p className="error-text">{errors[key as 'make']}</p>}
      </div>
    )

  return (
    <div className={className}>
      {field(
        'make',
        'Märke',
        <Select id={`${idPrefix}-make`} value={value.make} invalid={!!errors.make} onChange={(e) => onChange({ make: e.target.value, model: '', generation: '', engine: '', year: '' })}>
          <option value="">Alla märken</option>
          {makes.map((m) => (
            <option key={m}>{m}</option>
          ))}
        </Select>,
      )}
      {field(
        'model',
        'Modell',
        <Select id={`${idPrefix}-model`} value={value.model} invalid={!!errors.model} disabled={!value.make} onChange={(e) => onChange({ ...value, model: e.target.value, generation: '', engine: '', year: '' })}>
          <option value="">{value.make ? 'Alla modeller' : 'Välj märke först'}</option>
          {models.map((m) => (
            <option key={m.name}>{m.name}</option>
          ))}
        </Select>,
      )}
      {field(
        'generation',
        'Generation',
        <Select id={`${idPrefix}-generation`} value={value.generation ?? ''} disabled={!value.model} onChange={(e) => onChange({ ...value, generation: e.target.value, engine: '', year: '' })}>
          <option value="">Alla generationer</option>
          {gens.map((g) => (
            <option key={g.name} value={g.name}>
              {g.name} ({g.from}–{g.to})
            </option>
          ))}
        </Select>,
      )}
      {field(
        'engine',
        'Motor',
        <Select id={`${idPrefix}-engine`} value={value.engine ?? ''} disabled={!value.model} onChange={(e) => onChange({ ...value, engine: e.target.value })}>
          <option value="">Alla motorer</option>
          {engines.map((e) => (
            <option key={e}>{e}</option>
          ))}
        </Select>,
      )}
      {field(
        'year',
        'Årsmodell',
        <Select id={`${idPrefix}-year`} value={value.year} invalid={!!errors.year} onChange={(e) => onChange({ ...value, year: e.target.value })}>
          <option value="">Alla år</option>
          {years.map((y) => (
            <option key={y}>{y}</option>
          ))}
        </Select>,
      )}
    </div>
  )
}
