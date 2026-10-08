export type SellerType = 'private' | 'professional'

export type Condition = 'ny' | 'mycket-bra' | 'bra' | 'godtagbar' | 'renovering'

export type CategoryId =
  | 'motor'
  | 'vaxellada'
  | 'broms'
  | 'fjadring'
  | 'elektronik'
  | 'kaross'
  | 'belysning'
  | 'avgas'
  | 'turbo'
  | 'interior'
  | 'hjul'
  | 'kylsystem'

export interface Category {
  id: CategoryId
  name: string
  short: string
  examples: string[]
}

export interface VehicleRef {
  make: string
  model: string
  generation?: string
  year: number
  engine?: string
}

export interface Seller {
  id: string
  type: SellerType
  displayName: string
  city: string
  region: string
  description: string
  memberSince: string
  /** Professional sellers only */
  companyName?: string
  orgNumber?: string
  website?: string
  businessEmail?: string
  businessPhone?: string
  openingHours?: string
}

export type ListingStatus = 'active' | 'sold'

export interface Listing {
  id: string
  title: string
  categoryId: CategoryId
  partName: string
  description: string
  price: number
  negotiable: boolean
  condition: Condition
  conditionNote?: string
  /** OEM or reference number as written by the seller */
  oem?: string
  /** True when the reference is invented for demonstration purposes */
  oemIsDemo?: boolean
  vehicle: VehicleRef
  /** Seller-stated fitment notes. Never treated as verified. */
  fitmentNotes?: string
  donorMileageKm?: number
  vin?: string
  city: string
  postalCode: string
  sellerId: string
  shipping: boolean
  pickup: boolean
  quantity: number
  createdAt: string
  status: ListingStatus
  /** Photos uploaded by the user (data URLs). Demo listings use placeholders. */
  photos?: string[]
  placeholderViews?: number
  isUserCreated?: boolean
  additionalNotes?: string
}

export interface Message {
  id: string
  from: 'me' | 'them'
  text: string
  sentAt: string
  isDemoReply?: boolean
}

export interface Conversation {
  id: string
  listingId: string
  sellerId: string
  /** Name of the other party */
  withName: string
  messages: Message[]
  unread: number
}

export interface UserProfile {
  displayName: string
  email: string
  phone: string
  city: string
  postalCode: string
  sellerType: SellerType
  description: string
  companyName?: string
  orgNumber?: string
  website?: string
}

export interface UserSettings {
  emailNotifications: boolean
  showPhone: boolean
  newsletter: boolean
}

export type SortKey = 'relevance' | 'price-asc' | 'price-desc' | 'newest'

export interface ListingFilters {
  q: string
  make: string
  model: string
  generation: string
  engine: string
  year: string
  category: string
  part: string
  oem: string
  priceMin: string
  priceMax: string
  conditions: Condition[]
  sellerType: '' | SellerType
  city: string
  shipping: boolean
  sort: SortKey
}

/** The vehicle the visitor has saved as "Min bil". */
export interface MyCar {
  make: string
  model: string
  generation?: string
  engine?: string
  year: number
  /** Set when chosen via a fictional demo plate */
  demoPlate?: string
}
