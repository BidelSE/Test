import { Clock, Globe, Mail, MapPin, MessageSquare, Store } from 'lucide-react'
import { useNavigate, useParams } from 'react-router-dom'
import { Breadcrumbs } from '../components/Breadcrumbs'
import { EmptyState } from '../components/EmptyState'
import { ListingCard } from '../components/ListingCard'
import { SellerTypeBadge } from '../components/SellerTypeBadge'
import { useStore } from '../features/AppStore'
import { formatDate } from '../lib/format'
import { NotFoundPage } from './NotFoundPage'

export function SellerPage() {
  const { id } = useParams()
  const { sellersById, listings, startConversation } = useStore()
  const navigate = useNavigate()
  const seller = id ? sellersById[id] : undefined
  if (!seller) return <NotFoundPage title="Säljaren finns inte" />
  const theirs = listings.filter((l) => l.sellerId === seller.id && l.status === 'active')
  const pro = seller.type === 'professional'

  const contact = () => {
    if (!theirs.length) return
    navigate(`/konto/meddelanden/${startConversation(theirs[0].id)}`)
  }

  return (
    <div className="container-page pt-6">
      <Breadcrumbs items={[{ label: 'Bildelar', to: '/bildelar' }, { label: 'Säljare' }, { label: seller.displayName }]} />
      <div className="mt-5 grid gap-8 lg:grid-cols-[320px_1fr]">
        <aside>
          <div className="card p-6">
            <div className="grid h-16 w-16 place-items-center rounded-full bg-surface text-xl font-semibold text-gray-700">{pro ? <Store className="h-7 w-7" aria-hidden /> : seller.displayName.slice(0, 1)}</div>
            <h1 className="mt-4 text-xl font-semibold tracking-tight">{seller.displayName}</h1>
            <SellerTypeBadge type={seller.type} className="mt-1" />
            <ul className="mt-5 space-y-2 text-sm text-gray-700">
              <li className="flex items-center gap-2">
                <MapPin className="h-4 w-4 text-gray-400" aria-hidden />
                {seller.city}
                {seller.region && `, ${seller.region}`}
              </li>
              <li className="text-gray-500">På Bidel sedan {formatDate(seller.memberSince)}</li>
            </ul>
            <p className="mt-4 text-sm leading-relaxed text-gray-700">{seller.description}</p>

            {pro && (
              <dl className="mt-5 space-y-2 border-t border-gray-100 pt-4 text-sm">
                {seller.companyName && (
                  <div>
                    <dt className="text-xs text-gray-500">Företagsnamn</dt>
                    <dd className="font-medium">{seller.companyName}</dd>
                  </div>
                )}
                <div>
                  <dt className="text-xs text-gray-500">Organisationsnummer</dt>
                  <dd className="font-medium">{seller.orgNumber ?? 'Ej angivet (demoföretag)'}</dd>
                </div>
                {seller.openingHours && (
                  <div className="flex items-center gap-2">
                    <Clock className="h-4 w-4 text-gray-400" aria-hidden />
                    <dd>{seller.openingHours}</dd>
                  </div>
                )}
                {seller.website && (
                  <div className="flex items-center gap-2">
                    <Globe className="h-4 w-4 text-gray-400" aria-hidden />
                    <dd>{seller.website} <span className="text-xs text-gray-500">(exempeladress)</span></dd>
                  </div>
                )}
                {seller.businessEmail && (
                  <div className="flex items-center gap-2">
                    <Mail className="h-4 w-4 text-gray-400" aria-hidden />
                    <dd>{seller.businessEmail}</dd>
                  </div>
                )}
              </dl>
            )}
            <p className="mt-4 text-xs leading-relaxed text-gray-500">
              {pro ? 'Bidel har inte verifierat företagsuppgifterna. Verifiering av företag planeras i den färdiga tjänsten.' : 'Privatpersoners kontaktuppgifter visas inte publikt.'}
            </p>
            {seller.id !== 'me' && (
              <button type="button" className="btn-primary mt-5 w-full" onClick={contact} disabled={!theirs.length}>
                <MessageSquare className="h-4 w-4" /> Kontakta säljaren
              </button>
            )}
          </div>
        </aside>
        <section aria-labelledby="saljarens-annonser">
          <h2 id="saljarens-annonser" className="text-lg font-semibold">
            Annonser ({theirs.length})
          </h2>
          {theirs.length ? (
            <div className="mt-4 grid grid-cols-2 gap-3 sm:gap-4 md:grid-cols-3">
              {theirs.map((l) => (
                <ListingCard key={l.id} listing={l} />
              ))}
            </div>
          ) : (
            <div className="mt-4">
              <EmptyState title="Inga aktiva annonser" body="Säljaren har inga aktiva annonser just nu." />
            </div>
          )}
        </section>
      </div>
    </div>
  )
}
