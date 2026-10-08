import { createContext, useCallback, useContext, useMemo, useRef, useState, type ReactNode } from 'react'
import { demoConversations } from '../data/conversations'
import { demoListings, demoUserListings } from '../data/listings'
import { ME_ID, sellers as demoSellers } from '../data/sellers'
import { useStoredState } from '../hooks/useStoredState'
import { clearStore } from '../lib/storage'
import { uid } from '../lib/format'
import type { Conversation, Listing, Seller, UserProfile, UserSettings } from '../types'

const defaultProfile: UserProfile = {
  displayName: 'Demo Användare',
  email: 'demo@bidel.example',
  phone: '070-000 00 00',
  city: 'Stockholm',
  postalCode: '118 46',
  sellerType: 'private',
  description: 'Demokonto i Bidels prototyp.',
}

const defaultSettings: UserSettings = { emailNotifications: true, showPhone: false, newsletter: false }

export interface Toast {
  id: string
  text: string
  tone?: 'default' | 'success' | 'error'
}

const DEMO_REPLIES = [
  'Tack för ditt meddelande! Delen finns kvar. När skulle du kunna hämta den?',
  'Hej! Ja, det går bra. Jag kan skicka fler bilder om du vill.',
  'Absolut, skicka gärna din bils registreringsnummer eller referensnummer så kan vi jämföra.',
]

interface Store {
  listings: Listing[]
  myListings: Listing[]
  sellersById: Record<string, Seller>
  getListing: (id: string) => Listing | undefined
  favorites: string[]
  isFavorite: (id: string) => boolean
  toggleFavorite: (id: string) => void
  createListing: (l: Omit<Listing, 'id' | 'createdAt' | 'sellerId' | 'status'>) => Listing
  updateListing: (id: string, patch: Partial<Listing>) => void
  deleteListing: (id: string) => void
  conversations: Conversation[]
  unreadCount: number
  startConversation: (listingId: string) => string
  sendMessage: (conversationId: string, text: string) => void
  markRead: (conversationId: string) => void
  profile: UserProfile
  updateProfile: (p: UserProfile) => void
  settings: UserSettings
  updateSettings: (s: UserSettings) => void
  loggedIn: boolean
  login: () => void
  logout: () => void
  toasts: Toast[]
  toast: (text: string, tone?: Toast['tone']) => void
  dismissToast: (id: string) => void
  resetDemo: () => void
}

const Ctx = createContext<Store | null>(null)

export function AppStoreProvider({ children }: { children: ReactNode }) {
  const [favorites, setFavorites] = useStoredState<string[]>('favorites', ['l-1014', 'l-1010'])
  const [myListings, setMyListings] = useStoredState<Listing[]>('myListings', demoUserListings)
  const [conversations, setConversations] = useStoredState<Conversation[]>('conversations', demoConversations)
  const [profile, setProfile] = useStoredState<UserProfile>('profile', defaultProfile)
  const [settings, setSettings] = useStoredState<UserSettings>('settings', defaultSettings)
  const [loggedIn, setLoggedIn] = useStoredState<boolean>('loggedIn', false)
  const [toasts, setToasts] = useState<Toast[]>([])
  const replyIndex = useRef(0)

  const listings = useMemo(() => [...myListings, ...demoListings], [myListings])

  const sellersById = useMemo(() => {
    const me: Seller = {
      id: ME_ID,
      type: profile.sellerType,
      displayName: profile.sellerType === 'professional' && profile.companyName ? profile.companyName : profile.displayName,
      city: profile.city,
      region: '',
      description: profile.description,
      memberSince: '2026-10-01',
      companyName: profile.companyName,
      orgNumber: profile.orgNumber,
      website: profile.website,
    }
    return Object.fromEntries([...demoSellers, me].map((s) => [s.id, s])) as Record<string, Seller>
  }, [profile])

  const getListing = useCallback((id: string) => listings.find((l) => l.id === id), [listings])

  const dismissToast = useCallback((id: string) => setToasts((t) => t.filter((x) => x.id !== id)), [])
  const toast = useCallback(
    (text: string, tone: Toast['tone'] = 'default') => {
      const id = uid('t')
      setToasts((t) => [...t.slice(-2), { id, text, tone }])
      window.setTimeout(() => dismissToast(id), 3800)
    },
    [dismissToast],
  )

  const toggleFavorite = (id: string) => {
    const on = favorites.includes(id)
    setFavorites((f) => (on ? f.filter((x) => x !== id) : [id, ...f.filter((x) => x !== id)]))
    toast(on ? 'Annonsen togs bort från sparade' : 'Annonsen sparades', on ? 'default' : 'success')
  }

  const createListing: Store['createListing'] = (l) => {
    const listing: Listing = { ...l, id: uid('u'), createdAt: new Date().toISOString(), sellerId: ME_ID, status: 'active', isUserCreated: true }
    setMyListings((m) => [listing, ...m])
    return listing
  }
  const updateListing = (id: string, patch: Partial<Listing>) => setMyListings((m) => m.map((l) => (l.id === id ? { ...l, ...patch } : l)))
  const deleteListing = (id: string) => {
    setMyListings((m) => m.filter((l) => l.id !== id))
    setFavorites((f) => f.filter((x) => x !== id))
  }

  const startConversation = (listingId: string) => {
    const existing = conversations.find((c) => c.listingId === listingId)
    if (existing) return existing.id
    const listing = getListing(listingId)!
    const seller = sellersById[listing.sellerId]
    const id = uid('c')
    setConversations((c) => [{ id, listingId, sellerId: seller.id, withName: seller.displayName, messages: [], unread: 0 }, ...c])
    return id
  }

  const sendMessage = (conversationId: string, text: string) => {
    const msg = { id: uid('m'), from: 'me' as const, text, sentAt: new Date().toISOString() }
    setConversations((cs) => {
      const target = cs.find((c) => c.id === conversationId)
      if (!target) return cs
      return [{ ...target, messages: [...target.messages, msg] }, ...cs.filter((c) => c.id !== conversationId)]
    })
    window.setTimeout(() => {
      const reply = {
        id: uid('m'),
        from: 'them' as const,
        text: DEMO_REPLIES[replyIndex.current++ % DEMO_REPLIES.length],
        sentAt: new Date().toISOString(),
        isDemoReply: true,
      }
      setConversations((cs) => cs.map((c) => (c.id === conversationId ? { ...c, messages: [...c.messages, reply], unread: c.unread + 1 } : c)))
    }, 1600)
  }

  const markRead = useCallback(
    (conversationId: string) =>
      setConversations((cs) => (cs.some((c) => c.id === conversationId && c.unread) ? cs.map((c) => (c.id === conversationId ? { ...c, unread: 0 } : c)) : cs)),
    [setConversations],
  )

  const resetDemo = () => {
    clearStore()
    if (import.meta.env.VITE_HASH_ROUTER) {
      window.location.hash = '/'
      window.location.reload()
    } else window.location.assign('/')
  }

  const value: Store = {
    listings,
    myListings,
    sellersById,
    getListing,
    favorites,
    isFavorite: (id) => favorites.includes(id),
    toggleFavorite,
    createListing,
    updateListing,
    deleteListing,
    conversations,
    unreadCount: conversations.reduce((n, c) => n + c.unread, 0),
    startConversation,
    sendMessage,
    markRead,
    profile,
    updateProfile: setProfile,
    settings,
    updateSettings: setSettings,
    loggedIn,
    login: () => setLoggedIn(true),
    logout: () => setLoggedIn(false),
    toasts,
    toast,
    dismissToast,
    resetDemo,
  }

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useStore() {
  const s = useContext(Ctx)
  if (!s) throw new Error('useStore must be used inside AppStoreProvider')
  return s
}
