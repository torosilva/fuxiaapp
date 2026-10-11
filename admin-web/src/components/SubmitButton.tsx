'use client';
import { useFormStatus } from 'react-dom';

// A submit button that disables itself while the server action runs (no double captures on a slow connection).
export function SubmitButton({ children, pendingText = 'Guardando…', className, name, value }: { children: React.ReactNode; pendingText?: string; className?: string; name?: string; value?: string }) {
  const { pending } = useFormStatus();
  return <button type="submit" name={name} value={value} disabled={pending} className={`${className ?? ''} disabled:opacity-50`}>{pending ? pendingText : children}</button>;
}
