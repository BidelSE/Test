import { useEffect, useState } from 'react'
import { readStore, writeStore } from '../lib/storage'

export function useStoredState<T>(key: string, initial: T | (() => T)) {
  const [value, setValue] = useState<T>(() =>
    readStore<T>(key, typeof initial === 'function' ? (initial as () => T)() : initial),
  )
  useEffect(() => {
    writeStore(key, value)
  }, [key, value])
  return [value, setValue] as const
}
