import type { ReactNode } from 'react'

export function InfoLayout({ eyebrow, title, intro, children }: { eyebrow?: string; title: string; intro?: ReactNode; children: ReactNode }) {
  return (
    <div className="container-page max-w-3xl pt-10 sm:pt-14">
      {eyebrow && <p className="eyebrow">{eyebrow}</p>}
      <h1 className="mt-2 text-3xl font-bold tracking-tight sm:text-4xl">{title}</h1>
      {intro && <p className="mt-4 text-lg leading-relaxed text-gray-600">{intro}</p>}
      <div className="prose-bidel mt-10">{children}</div>
    </div>
  )
}
