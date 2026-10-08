import { type ReactNode, useId } from 'react'
import { cx } from '../lib/format'

export function Field({ label, error, help, children, className, required, htmlFor }: { label: string; error?: string; help?: ReactNode; children: (id: string, describedBy?: string) => ReactNode; className?: string; required?: boolean; htmlFor?: string }) {
  const auto = useId()
  const id = htmlFor ?? auto
  const describedBy = error ? `${id}-err` : help ? `${id}-help` : undefined
  return (
    <div className={className}>
      <label htmlFor={id} className="label">
        {label}
        {required && <span className="text-red-600"> *</span>}
      </label>
      {children(id, describedBy)}
      {error ? (
        <p id={`${id}-err`} className="error-text" role="alert">
          {error}
        </p>
      ) : help ? (
        <p id={`${id}-help`} className="help">
          {help}
        </p>
      ) : null}
    </div>
  )
}

export function Select({ className, invalid, ...props }: React.SelectHTMLAttributes<HTMLSelectElement> & { invalid?: boolean }) {
  return (
    <select
      {...props}
      aria-invalid={invalid || undefined}
      className={cx(
        'input appearance-none bg-[url("data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A//www.w3.org/2000/svg%22%20viewBox%3D%220%200%2020%2020%22%20fill%3D%22%236b7280%22%3E%3Cpath%20d%3D%22M5.5%207.5l4.5%204.5%204.5-4.5%22%20stroke%3D%22%236b7280%22%20stroke-width%3D%221.5%22%20fill%3D%22none%22/%3E%3C/svg%3E")] bg-[length:18px] bg-[right_0.6rem_center] bg-no-repeat pr-8',
        invalid && 'input-error',
        className,
      )}
    />
  )
}
