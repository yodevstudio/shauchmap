import { useEffect, useId, useRef } from 'preact/hooks';
import type { ComponentChildren } from 'preact';
import { TRAVEL_DISCLAIMER, travelChoices, type TravelMode } from '../domain/travel-mode';
import { IconCar, IconScooter, IconWalk } from './icons';

const FOCUSABLE =
  'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';

/** Lightweight modal shell: focus trap, Escape, focus restore, body scroll-lock,
 * backdrop-click close, aria-modal. No dialog library . */
export function ModalSheet({
  labelledBy,
  onClose,
  children,
}: {
  labelledBy: string;
  onClose: () => void;
  children: ComponentChildren;
}) {
  const sheet = useRef<HTMLDivElement>(null);
  const opener = useRef<Element | null>(null);

  useEffect(() => {
    opener.current = document.activeElement;
    document.body.classList.add('modal-open');

    const node = sheet.current!;
    // initial focus: the sheet itself (announced), then Tab reaches the actions
    node.focus();

    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        onClose();
        return;
      }
      if (e.key !== 'Tab') return;
      const items = [...node.querySelectorAll<HTMLElement>(FOCUSABLE)].filter((el) => {
        if (el.hasAttribute('hidden')) return false;
        const cs = getComputedStyle(el);
        return cs.display !== 'none' && cs.visibility !== 'hidden';
      });
      if (!items.length) {
        e.preventDefault();
        node.focus();
        return;
      }
      const first = items[0];
      const last = items[items.length - 1];
      const active = document.activeElement as HTMLElement;
      if (e.shiftKey && (active === first || active === node)) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && active === last) {
        e.preventDefault();
        first.focus();
      }
    };
    document.addEventListener('keydown', onKey, true);

    return () => {
      document.removeEventListener('keydown', onKey, true);
      document.body.classList.remove('modal-open');
      // restore focus to whatever opened the sheet
      const el = opener.current as HTMLElement | null;
      if (el && typeof el.focus === 'function') el.focus();
    };
  }, [onClose]);

  return (
    <div class="sheet-backdrop" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div
        class="sheet"
        role="dialog"
        aria-modal="true"
        aria-labelledby={labelledBy}
        tabIndex={-1}
        ref={sheet}
      >
        {children}
      </div>
    </div>
  );
}

const MODE_ICON: Record<TravelMode, (p: { size?: number }) => preact.JSX.Element> = {
  driving: IconCar,
  bicycling: IconScooter,
  walking: IconWalk,
};

/** How will you get there? — same modes / estimate / disclaimer as Android. */
export function TravelSheet({
  distanceMeters,
  onPick,
  onClose,
}: {
  distanceMeters: number | null;
  onPick: (mode: TravelMode) => void;
  onClose: () => void;
}) {
  const id = useId();
  const choices = travelChoices(distanceMeters);
  return (
    <ModalSheet labelledBy={id} onClose={onClose}>
      <h2 id={id}>How will you get there?</h2>
      {choices.map((c) => {
        const Icon = MODE_ICON[c.mode];
        return (
          <button class="mode-row" key={c.mode} onClick={() => onPick(c.mode)}>
            <Icon size={22} />
            <span class="label">{c.label}</span>
            {c.etaMinutes != null && <span class="eta">~{c.etaMinutes} min</span>}
          </button>
        );
      })}
      <p class="small muted" style="margin:6px 0 0">
        {TRAVEL_DISCLAIMER}
      </p>
    </ModalSheet>
  );
}

/** Confirmation shown ONLY with FRESH metadata . */
export function ConfirmDialog({
  title,
  body,
  confirmLabel,
  onConfirm,
  onClose,
}: {
  title: string;
  body: ComponentChildren;
  confirmLabel: string;
  onConfirm: () => void;
  onClose: () => void;
}) {
  const id = useId();
  return (
    <ModalSheet labelledBy={id} onClose={onClose}>
      <h2 id={id}>{title}</h2>
      <div class="small" style="color:var(--ink-2)">
        {body}
      </div>
      <div class="stack" style="margin-top:16px">
        <button class="btn btn-primary" onClick={onConfirm}>
          {confirmLabel}
        </button>
        <button class="btn btn-ghost" onClick={onClose} style="width:100%">
          Cancel
        </button>
      </div>
    </ModalSheet>
  );
}
