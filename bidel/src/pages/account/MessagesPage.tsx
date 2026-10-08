import { ArrowLeft, Info, MessageSquare, Send } from 'lucide-react'
import { useEffect, useRef, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { EmptyState } from '../../components/EmptyState'
import { PartImage } from '../../components/PartImage'
import { useStore } from '../../features/AppStore'
import { cx, formatPrice, formatTime } from '../../lib/format'

export function MessagesPage() {
  const { cid } = useParams()
  const { conversations, getListing, sendMessage, markRead } = useStore()
  const active = conversations.find((c) => c.id === cid)
  const [text, setText] = useState('')
  const endRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (active?.unread) markRead(active.id)
  }, [active?.id, active?.unread, markRead])
  useEffect(() => {
    endRef.current?.scrollIntoView({ block: 'end' })
  }, [active?.messages.length])

  if (!conversations.length) {
    return (
      <EmptyState
        icon={<MessageSquare className="h-6 w-6" />}
        title="Inga meddelanden ännu"
        body="När du kontaktar en säljare via en annons visas konversationen här."
        action={
          <Link to="/bildelar" className="btn-primary">
            Sök bildelar
          </Link>
        }
      />
    )
  }

  const listing = active && getListing(active.listingId)

  return (
    <div>
      <h2 className="sr-only">Meddelanden</h2>
      <div className="mb-3 flex gap-2 rounded-md bg-surface p-3 text-xs text-gray-700">
        <Info className="h-4 w-4 shrink-0 text-gray-500" aria-hidden />
        <p>Demochatt: meddelanden sparas i din webbläsare och når inga riktiga säljare. Svaren är automatiska exempel.</p>
      </div>
      <div className="grid overflow-hidden rounded-lg border border-gray-200 md:h-[620px] md:grid-cols-[280px_1fr]">
        {/* Conversation list */}
        <ul className={cx('divide-y divide-gray-100 overflow-y-auto border-gray-200 md:border-r', active && 'hidden md:block')}>
          {conversations.map((c) => {
            const l = getListing(c.listingId)
            const last = c.messages[c.messages.length - 1]
            return (
              <li key={c.id}>
                <Link to={`/konto/meddelanden/${c.id}`} className={cx('flex gap-3 p-3 hover:bg-gray-50', c.id === cid && 'bg-brand-50/60')} aria-current={c.id === cid ? 'true' : undefined}>
                  <div className="h-12 w-12 shrink-0 overflow-hidden rounded border border-gray-100">{l && <PartImage listing={l} size="sm" />}</div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-baseline justify-between gap-2">
                      <p className={cx('truncate text-sm', c.unread ? 'font-semibold' : 'font-medium')}>{c.withName}</p>
                      {last && <span className="shrink-0 text-[11px] text-gray-500">{formatTime(last.sentAt)}</span>}
                    </div>
                    <p className="truncate text-xs text-gray-500">{l?.title}</p>
                    <p className={cx('truncate text-xs', c.unread ? 'text-ink' : 'text-gray-500')}>{last ? `${last.from === 'me' ? 'Du: ' : ''}${last.text}` : 'Skriv ett första meddelande'}</p>
                  </div>
                </Link>
              </li>
            )
          })}
        </ul>

        {/* Thread */}
        {active ? (
          <div className="flex h-[70vh] min-h-0 flex-col md:h-auto">
            <div className="flex items-center gap-3 border-b border-gray-200 p-3">
              <Link to="/konto/meddelanden" className="btn-ghost h-9 w-9 px-0 md:hidden" aria-label="Tillbaka till konversationer">
                <ArrowLeft className="h-5 w-5" />
              </Link>
              {listing && (
                <Link to={`/annons/${listing.id}`} className="flex min-w-0 flex-1 items-center gap-3 rounded hover:bg-gray-50">
                  <div className="h-10 w-10 shrink-0 overflow-hidden rounded border border-gray-100">
                    <PartImage listing={listing} size="sm" />
                  </div>
                  <div className="min-w-0">
                    <p className="truncate text-sm font-semibold">{active.withName}</p>
                    <p className="truncate text-xs text-gray-600">
                      {listing.title} · {formatPrice(listing.price)}
                    </p>
                  </div>
                </Link>
              )}
            </div>
            <div className="flex-1 space-y-3 overflow-y-auto bg-gray-50/60 p-4" aria-live="polite">
              {!active.messages.length && <p className="py-10 text-center text-sm text-gray-500">Skriv ett meddelande till {active.withName}. Fråga gärna om referensnummer och passform.</p>}
              {active.messages.map((m) => (
                <div key={m.id} className={cx('flex flex-col', m.from === 'me' ? 'items-end' : 'items-start')}>
                  <div className={cx('max-w-[80%] rounded-2xl px-3.5 py-2 text-sm leading-relaxed', m.from === 'me' ? 'rounded-br-sm bg-brand-700 text-white' : 'rounded-bl-sm border border-gray-200 bg-white')}>{m.text}</div>
                  <span className="mt-1 text-[11px] text-gray-500">
                    {formatTime(m.sentAt)}
                    {m.isDemoReply && ' · Automatiskt demosvar'}
                  </span>
                </div>
              ))}
              <div ref={endRef} />
            </div>
            <form
              className="flex gap-2 border-t border-gray-200 bg-white p-3"
              onSubmit={(e) => {
                e.preventDefault()
                if (!text.trim()) return
                sendMessage(active.id, text.trim())
                setText('')
              }}
            >
              <label htmlFor="msg" className="sr-only">
                Meddelande
              </label>
              <input id="msg" className="input" value={text} onChange={(e) => setText(e.target.value)} placeholder="Skriv ett meddelande…" autoComplete="off" />
              <button type="submit" className="btn-primary px-3" disabled={!text.trim()} aria-label="Skicka">
                <Send className="h-4 w-4" />
              </button>
            </form>
          </div>
        ) : (
          <div className="hidden items-center justify-center p-8 text-sm text-gray-500 md:flex">Välj en konversation</div>
        )}
      </div>
    </div>
  )
}
