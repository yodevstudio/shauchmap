import type { ComponentChildren } from 'preact';
import type { GoAlternativeJson, GoPresentationJson } from '../core/types';
import type { GoResult } from '../domain/resolve-go';
import type { ShauchmapCore } from '../core/interop';
import { poolEntry } from '../domain/resolve-go';
import {
  authorityLabel,
  cautionLabel,
  conditionFreshness,
  conditionLabel,
  goView,
  identityLabel,
  metersLabel,
  ratingsLine,
  secondaryDescriptor,
} from './present';
import { CautionList, Pill } from './components';

function toneClass(tone: GoPresentationJson['tone']): string {
  return tone === 'positive'
    ? 'tone-positive'
    : tone === 'warning'
      ? 'tone-warning'
      : 'tone-neutral';
}
function toneColor(tone: GoPresentationJson['tone']): string {
  return tone === 'positive' ? 'var(--go)' : tone === 'warning' ? 'var(--caution)' : 'var(--ink-2)';
}
function nameFor(map: Record<string, unknown> | undefined): string {
  const n = map?.['name'];
  return typeof n === 'string' && n.trim() ? n : 'Unnamed toilet';
}

/** The GO-selected recommendation. Renders the CORE's presentation verbatim. */
export function GoCard({
  result,
  core,
  onNavigate,
  note,
}: {
  result: GoResult;
  core: ShauchmapCore;
  onNavigate: () => void;
  /** Optional honest note above the CTAs (e.g. the hint-ineligible message). */
  note?: ComponentChildren;
}) {
  const { go } = result;
  const v = goView(go);
  const sel = poolEntry(result.pool, go.selectedId);
  const truth = sel ? core.evaluateTruth(sel.map) : null;
  const evidence = sel ? core.evaluateEvidence(sel.map['evidence_v2'] ?? null, result.nowMs) : null;
  const freshness = evidence ? conditionFreshness(evidence.condition) : null;

  return (
    <section class={`card ${toneClass(v.tone)}`} aria-label="Recommended toilet">
      <div class="spread">
        <h1 style="margin:0">{sel ? nameFor(sel.map) : v.headline}</h1>
        <Pill kind="distance">{metersLabel(go.selectedDistanceMeters)}</Pill>
      </div>
      <p class="small" style={`margin-top:6px;font-weight:650;color:${toneColor(v.tone)}`}>
        {v.headline}
        {freshness && <span class="muted" style="font-weight:500"> · {freshness}</span>}
      </p>
      <p style="margin-top:8px">{v.explanation}</p>

      {sel && truth && secondaryDescriptor(sel.map, truth) && (
        <p class="small" style="margin:6px 0 0">
          {secondaryDescriptor(sel.map, truth)}
        </p>
      )}
      {truth && (
        <p class="small muted" style="margin:4px 0 0">
          {identityLabel(truth.identityStatus)}
          {truth.fee === 'paid' ? ' · Paid' : truth.fee === 'free' ? ' · Free' : ''}
        </p>
      )}
      {evidence && ratingsLine(evidence) && (
        <p class="small muted" style="margin:4px 0 0">
          {ratingsLine(evidence)}
        </p>
      )}

      <div style="margin-top:12px">
        <CautionList items={v.cautions} />
      </div>

      {note && (
        <p class="small" style="margin-top:10px" role="note">
          {note}
        </p>
      )}

      {v.requiresConfirmation && (
        <p class="small" style="margin-top:10px;font-weight:600;color:var(--caution)" role="note">
          Confirm before you rely on this — details will be re-checked when you tap {v.primaryCta}.
        </p>
      )}

      <div class="stack" style="margin-top:14px">
        <button
          class="btn btn-primary"
          onClick={onNavigate}
          disabled={!v.navigationAllowed && !v.requiresConfirmation}
        >
          {v.primaryCta}
        </button>
        {v.secondaryCta && (
          <a class="btn btn-secondary" href="/go">
            {v.secondaryCta}
          </a>
        )}
      </div>
    </section>
  );
}

/** The /t/:id FOCUSED facility — the hinted alternative, rendered from the
 *  shared core's `focus` block (`presentGoAlternative` copy). FOCUS != SELECTED:
 *  the GO-selected toilet is shown only as secondary context. */
export function FocusCard({
  result,
  core,
  onNavigate,
}: {
  result: GoResult;
  core: ShauchmapCore;
  onNavigate: () => void;
}) {
  const focus = result.focus!;
  const p = focus.presentation;
  const entry = poolEntry(result.pool, focus.id);
  const truth = entry ? core.evaluateTruth(entry.map) : null;
  const selName = (() => {
    const s = poolEntry(result.pool, result.go.selectedId);
    return s ? nameFor(s.map) : result.go.selectedId;
  })();

  return (
    <section class={`card ${toneClass(p.tone)}`} aria-label="Recommended toilet">
      <p class="small muted" style="margin:0 0 4px;text-transform:uppercase;letter-spacing:0.04em">
        From your link
      </p>
      <div class="spread">
        <h1 style="margin:0">{entry ? nameFor(entry.map) : focus.id}</h1>
        <Pill kind="distance">{metersLabel(focus.distanceMeters)}</Pill>
      </div>
      <p class="small" style={`margin-top:6px;font-weight:650;color:${toneColor(p.tone)}`}>
        {p.headline}
      </p>
      <p style="margin-top:8px">{p.explanation}</p>

      {entry && truth && secondaryDescriptor(entry.map, truth) && (
        <p class="small" style="margin:6px 0 0">
          {secondaryDescriptor(entry.map, truth)}
        </p>
      )}
      {truth && (
        <p class="small muted" style="margin:4px 0 0">
          {identityLabel(truth.identityStatus)}
          {truth.fee === 'paid' ? ' · Paid' : truth.fee === 'free' ? ' · Free' : ''} ·{' '}
          {authorityLabel(focus.authority)}
        </p>
      )}
      {focus.condition !== 'unknown' && (
        <p class="small" style="margin:4px 0 0">
          {conditionLabel(focus.condition)}
        </p>
      )}

      <div style="margin-top:12px">
        <CautionList items={p.cautions} />
      </div>

      {p.requiresConfirmation && (
        <p class="small" style="margin-top:10px;font-weight:600;color:var(--caution)" role="note">
          Confirm before you rely on this — details will be re-checked when you tap {p.primaryCta}.
        </p>
      )}

      {result.go.selectedId && result.go.selectedId !== focus.id && (
        <p class="small muted" style="margin-top:10px">
          GO's current top pick nearby: <strong>{selName}</strong> ·{' '}
          {metersLabel(result.go.selectedDistanceMeters)}
        </p>
      )}

      <div class="stack" style="margin-top:14px">
        <button
          class="btn btn-primary"
          onClick={onNavigate}
          disabled={!p.navigationAllowed && !p.requiresConfirmation}
        >
          {p.primaryCta}
        </button>
        <a class="btn btn-secondary" href="/go">
          See the current top pick
        </a>
      </div>
    </section>
  );
}

/** Up to 3 alternatives, in the CORE's order. Not visually equal to a result. */
export function AltList({
  result,
  core,
  onPick,
}: {
  result: GoResult;
  core: ShauchmapCore;
  onPick: (alt: GoAlternativeJson) => void;
}) {
  // Don't repeat the focused facility here — it's already the main card.
  const focusId = result.focus?.id ?? null;
  const alts = result.go.alternatives.filter((a) => a.id !== focusId).slice(0, 3);
  if (!alts.length) return null;
  return (
    <section class="card" aria-label="Other nearby options">
      <h2 class="small muted" style="text-transform:uppercase;letter-spacing:0.04em">
        Other options
      </h2>
      {alts.map((a) => {
        const e = poolEntry(result.pool, a.id);
        const eTruth = e ? core.evaluateTruth(e.map) : null;
        const desc = e && eTruth ? secondaryDescriptor(e.map, eTruth) : null;
        return (
          <div class="alt" key={a.id}>
            <div class="spread">
              <span class="alt-name">{e ? nameFor(e.map) : a.id}</span>
              <span class="muted small" style="white-space:nowrap">
                {metersLabel(a.distanceMeters)}
              </span>
            </div>
            {desc && (
              <p class="small muted" style="margin:0 0 4px">
                {desc}
              </p>
            )}
            <div class="row" style="gap:6px;margin:2px 0 6px">
              <Pill kind="muted">{authorityLabel(a.authority)}</Pill>
              {a.condition !== 'unknown' && <Pill kind="muted">{conditionLabel(a.condition)}</Pill>}
              {a.requiresConfirmation && <Pill kind="warning">Needs confirmation</Pill>}
            </div>
            {a.cautions.length > 0 && (
              <p class="small" style="color:var(--caution);margin:0 0 6px">
                {a.cautions.map(cautionLabel).join(' · ')}
              </p>
            )}
            <button class="btn btn-secondary" onClick={() => onPick(a)}>
              Use this instead
            </button>
          </div>
        );
      })}
    </section>
  );
}
