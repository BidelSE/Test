import { Link } from 'react-router-dom'

export function NotFoundPage({ title = 'Sidan hittades inte', body = 'Länken kan vara felaktig eller så har sidan flyttats.' }: { title?: string; body?: string }) {
  return (
    <div className="container-page flex flex-col items-center py-24 text-center">
      <p className="text-sm font-semibold text-brand-700">404</p>
      <h1 className="mt-2 text-2xl font-semibold tracking-tight">{title}</h1>
      <p className="mt-2 max-w-md text-gray-600">{body}</p>
      <div className="mt-6 flex gap-2">
        <Link to="/" className="btn-secondary">
          Till startsidan
        </Link>
        <Link to="/bildelar" className="btn-primary">
          Sök bildelar
        </Link>
      </div>
    </div>
  )
}
