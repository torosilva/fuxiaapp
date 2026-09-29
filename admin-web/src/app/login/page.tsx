import { LoginForm } from './LoginForm';

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ motivo?: string }> }) {
  const { motivo } = await searchParams;
  const staging = process.env.NEXT_PUBLIC_F360_ENV === 'staging';
  return (
    <div className="grid min-h-dvh lg:grid-cols-2">
      <div className="relative hidden overflow-hidden bg-ink lg:block">
        <div className="absolute inset-0 bg-[radial-gradient(circle_at_30%_20%,rgba(168,123,31,0.35),transparent_55%)]" />
        <div className="relative flex h-full flex-col justify-between p-14 text-surface">
          <div className="text-xs uppercase tracking-[0.3em] text-surface/60">Fuxia Ballerinas</div>
          <div>
            <h1 className="font-display text-7xl leading-none">Fuxia <span className="text-gold">360</span></h1>
            <p className="mt-6 max-w-sm text-lg text-surface/70">Tus productos y tu inventario, en un solo lugar.</p>
          </div>
        </div>
      </div>
      <div className="flex flex-col items-center justify-center px-6 py-12">
        <div className="mb-10 text-center lg:hidden">
          <h1 className="font-display text-5xl">Fuxia <span className="text-gold">360</span></h1>
          <p className="mt-2 text-sm text-muted">Tus productos y tu inventario, en un solo lugar.</p>
        </div>
        <h2 className="font-display mb-8 hidden text-4xl lg:block">Bienvenida</h2>
        <LoginForm staging={staging} reason={motivo} />
        {staging && <p className="mt-10 text-xs text-muted">Ambiente de pruebas</p>}
      </div>
    </div>
  );
}
