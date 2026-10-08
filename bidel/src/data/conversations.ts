import type { Conversation } from '../types'

export const demoConversations: Conversation[] = [
  {
    id: 'c-1',
    listingId: 'l-1001',
    sellerId: 's-erik',
    withName: 'Erik L.',
    unread: 1,
    messages: [
      { id: 'm-1', from: 'me', text: 'Hej! Är turbon fortfarande till salu? Vilken motorkod satt den på?', sentAt: '2026-10-07T17:02:00Z' },
      { id: 'm-2', from: 'them', text: 'Hej, ja den finns kvar. Den satt på en AMB. Jag kan skicka fler bilder på axeln om du vill.', sentAt: '2026-10-07T17:40:00Z', isDemoReply: true },
    ],
  },
  {
    id: 'c-2',
    listingId: 'l-1023',
    sellerId: 's-malardalen',
    withName: 'Mälardalens Bildelar',
    unread: 0,
    messages: [
      { id: 'm-3', from: 'me', text: 'Hej, går det att skicka ABS-enheten till Stockholm?', sentAt: '2026-10-04T09:15:00Z' },
      { id: 'm-4', from: 'them', text: 'Hej! Ja, vi skickar med paket. Frakten bokas separat efter överenskommelse.', sentAt: '2026-10-04T10:02:00Z', isDemoReply: true },
    ],
  },
]
