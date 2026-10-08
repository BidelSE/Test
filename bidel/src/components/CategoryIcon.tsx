import { Armchair, CarFront, Cloud, Cog, Cpu, Disc3, Fan, LifeBuoy, Lightbulb, MoveVertical, Settings2, ThermometerSnowflake, type LucideProps } from 'lucide-react'
import type { CategoryId } from '../types'

const icons: Record<CategoryId, React.ComponentType<LucideProps>> = {
  motor: Cog,
  vaxellada: Settings2,
  broms: Disc3,
  fjadring: MoveVertical,
  elektronik: Cpu,
  kaross: CarFront,
  belysning: Lightbulb,
  avgas: Cloud,
  turbo: Fan,
  interior: Armchair,
  hjul: LifeBuoy,
  kylsystem: ThermometerSnowflake,
}

export function CategoryIcon({ id, ...props }: { id: CategoryId } & LucideProps) {
  const Icon = icons[id] ?? Cog
  return <Icon strokeWidth={1.5} aria-hidden {...props} />
}
