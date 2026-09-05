import type { ComponentChildren } from 'preact';
import { isDemo } from '../data/mode';
import { IconAlert } from './icons';

export function DemoBadge() {
  if (!isDemo()) return null;
  return (
    <div class="demo-badge" role="note">
      DEMO DATA — not a live toilet status. For testing only.
    </div>
  );
}

export function BrandMark({ small = false }: { small?: boolean }) {
  return (
    <div class="brandmark" style={small ? 'font-size:0.95rem' : 'font-size:1.05rem'}>
      <img src="/icons/icon.svg" alt="" width={small ? 22 : 28} height={small ? 22 : 28} />
      <span>
        ShauchMap <span class="muted" style="font-weight:600">Instant</span>
      </span>
    </div>
  );
}

export function Shell({
  children,
  header = true,
}: {
  children: ComponentChildren;
  header?: boolean;
}) {
  return (
    <>
      <DemoBadge />
      <main id="main" class="wrap stack">
        {header && (
          <header style="margin-bottom:4px">
            <a
              href="/"
              class="home-link"
              aria-label="ShauchMap Instant — home"
            >
              <BrandMark small />
            </a>
          </header>
        )}
        {children}
        <footer class="osm-attribution">
          Toilet data:{' '}
          <a
            href="https://www.openstreetmap.org/copyright"
            target="_blank"
            rel="noreferrer noopener"
          >
            © OpenStreetMap contributors
          </a>
        </footer>
      </main>
    </>
  );
}

export function Spinner({ label }: { label: string }) {
  return (
    <div class="state" role="status" aria-live="polite">
      <div class="spinner" aria-hidden="true" />
      <p class="muted">{label}</p>
    </div>
  );
}

export function Pill({
  children,
  kind = 'default',
}: {
  children: ComponentChildren;
  kind?: 'default' | 'distance' | 'warning' | 'muted';
}) {
  const cls =
    kind === 'distance'
      ? 'pill pill-distance'
      : kind === 'warning'
        ? 'pill pill-warning'
        : kind === 'muted'
          ? 'pill pill-muted'
          : 'pill';
  return <span class={cls}>{children}</span>;
}

export function StateBlock({
  icon,
  title,
  body,
  actions,
}: {
  /** A component from ui/icons — rendered decoratively (the text carries meaning). */
  icon: (p: { size?: number }) => import('preact').JSX.Element;
  title: string;
  body: ComponentChildren;
  actions?: ComponentChildren;
}) {
  const Icon = icon;
  return (
    <section class="state card" aria-live="polite">
      <div class="state-icon" aria-hidden="true">
        <Icon size={28} />
      </div>
      <h2>{title}</h2>
      <p>{body}</p>
      {actions && <div class="stack" style="margin-top:14px">{actions}</div>}
    </section>
  );
}

export function CautionList({ items }: { items: string[] }) {
  if (!items.length) return null;
  return (
    <ul class="cautions stack" aria-label="Cautions">
      {items.map((c) => (
        <li key={c}>
          <IconAlert size={16} />
          <span>{c}</span>
        </li>
      ))}
    </ul>
  );
}
