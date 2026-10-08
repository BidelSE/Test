import type { ReactNode } from 'react'

export function EmptyState({ icon, title, body, action }: { icon?: ReactNode; title: string; body?: ReactNode; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center rounded-lg border border-dashed border-gray-300 px-6 py-14 text-center">
      {icon && <div className="mb-4 grid h-12 w-12 place-items-center rounded-full bg-gray-100 text-gray-500">{icon}</div>}
      <h3 className="text-base font-semibold">{title}</h3>
      {body && <p className="mt-1.5 max-w-md text-sm text-gray-600">{body}</p>}
      {action && <div className="mt-5">{action}</div>}
    </div>
  )
}
