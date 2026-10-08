import { Heart } from 'lucide-react'
import { Link } from 'react-router-dom'
import { EmptyState } from '../../components/EmptyState'
import { ListingCard } from '../../components/ListingCard'
import { useStore } from '../../features/AppStore'

export function SavedPage() {
  const { favorites, getListing } = useStore()
  const saved = favorites.map(getListing).filter((l): l is NonNullable<typeof l> => !!l)
  return (
    <div>
      <h2 className="text-lg font-semibold">Sparade annonser</h2>
      <p className="mt-1 text-sm text-gray-600">Klicka på hjärtat för att ta bort en annons från listan.</p>
      {saved.length ? (
        <div className="mt-4 grid grid-cols-2 gap-3 sm:gap-4 md:grid-cols-3">
          {saved.map((l) => (
            <ListingCard key={l.id} listing={l} />
          ))}
        </div>
      ) : (
        <div className="mt-4">
          <EmptyState
            icon={<Heart className="h-6 w-6" />}
            title="Inga sparade annonser"
            body="Spara annonser du är intresserad av så hittar du dem snabbt igen."
            action={
              <Link to="/bildelar" className="btn-primary">
                Sök bildelar
              </Link>
            }
          />
        </div>
      )}
    </div>
  )
}
