import { useEffect, useState } from 'react'
import { useStore } from '../features/AppStore'
import { Dialog } from './Dialog'
import { RegLookup } from './RegLookup'
import { VehicleSelects, type VehicleValue } from './VehicleSelects'

const blank: VehicleValue = { make: '', model: '', generation: '', engine: '', year: '' }

export function MyCarDialog() {
  const { myCar, setMyCar, carDialogOpen, setCarDialogOpen, toast } = useStore()
  const [v, setV] = useState<VehicleValue>(blank)
  const [error, setError] = useState('')

  useEffect(() => {
    if (carDialogOpen) {
      setV(myCar ? { make: myCar.make, model: myCar.model, generation: myCar.generation ?? '', engine: myCar.engine ?? '', year: String(myCar.year) } : blank)
      setError('')
    }
  }, [carDialogOpen, myCar])

  const close = () => setCarDialogOpen(false)
  const save = () => {
    if (!v.make || !v.model || !v.year) {
      setError('Välj minst märke, modell och årsmodell.')
      return
    }
    setMyCar({ make: v.make, model: v.model, generation: v.generation || undefined, engine: v.engine || undefined, year: Number(v.year) })
    toast('Din bil sparades', 'success')
    close()
  }

  return (
    <Dialog
      open={carDialogOpen}
      onClose={close}
      title="Min bil"
      footer={
        <>
          {myCar && (
            <button
              type="button"
              className="btn-ghost text-red-600 sm:mr-auto"
              onClick={() => {
                setMyCar(null)
                toast('Bilen togs bort')
                close()
              }}
            >
              Ta bort bil
            </button>
          )}
          <button type="button" className="btn-secondary" onClick={close}>
            Avbryt
          </button>
          <button type="button" className="btn-primary" onClick={save}>
            Spara bil
          </button>
        </>
      }
    >
      <p>Spara din bil så visar vi vilka annonser som kommer från samma modell, generation och motor. Det är en vägledning – inte en garanti för att delen passar.</p>
      <VehicleSelects
        idPrefix="mycar"
        show={['make', 'model', 'generation', 'engine', 'year']}
        value={v}
        onChange={(nv) => {
          setV(nv)
          setError('')
        }}
        className="mt-4 grid gap-3 sm:grid-cols-2"
      />
      {error && (
        <p className="error-text" role="alert">
          {error}
        </p>
      )}
      <div className="mt-4">
        <RegLookup
          compact
          onVehicle={(car) => setV({ make: car.make, model: car.model, generation: car.generation, engine: car.engine, year: String(car.year) })}
          actionLabel="Använd fordonet"
        />
      </div>
    </Dialog>
  )
}
