import { useState } from 'preact/hooks';
import { Shell, Spinner } from './components';
import {
  DataUnavailable,
  NoConfidentOption,
  NoToilets,
  OfflineShell,
  PermissionExplainer,
  LocationProblem,
} from './states';
import { GoCard, FocusCard, AltList } from './go-card';
import { TravelSheet, ConfirmDialog, ModalSheet } from './travel-sheet';
import { useGoFlow } from './use-go-flow';
import { poolEntry, primaryTargetId } from '../domain/resolve-go';
import { freshTargetMeta } from '../domain/nav-target';
import { mapsDirectionsUrl, type TravelMode } from '../domain/travel-mode';

function offline(): boolean {
  return typeof navigator !== 'undefined' && navigator.onLine === false;
}

export function GoScreen({
  hintId = null,
  campaignId = null,
}: {
  hintId?: string | null;
  campaignId?: string | null;
}) {
  const flow = useGoFlow({ hintId });
  const [travelFor, setTravelFor] = useState<string | null>(null);

  // campaignId is V1 route/session metadata only — no analytics, no writes.
  if (campaignId && typeof sessionStorage !== 'undefined') {
    try {
      sessionStorage.setItem('shauchmap.instant.campaign', campaignId);
    } catch {
      /* ignore */
    }
  }

  const openMaps = (targetId: string | null, mode: TravelMode) => {
    const r = flow.result;
    const id = targetId ?? (r ? primaryTargetId(r) : null);
    const entry = r ? poolEntry(r.pool, id) : null;
    if (entry) {
      window.open(mapsDirectionsUrl({ lat: entry.lat, lng: entry.lng }, mode), '_blank', 'noopener');
    }
    setTravelFor(null);
    flow.dismissNav();
  };

  let body;
  if (flow.phase === 'need-permission') {
    body = <PermissionExplainer onContinue={flow.start} />;
  } else if (flow.phase === 'booting' || flow.phase === 'locating') {
    body = <Spinner label="Getting your location…" />;
  } else if (flow.phase === 'location-problem' && flow.locationProblem) {
    body = <LocationProblem outcome={flow.locationProblem} onRetry={flow.retry} />;
  } else if (flow.phase === 'loading') {
    body = <Spinner label="Finding nearby toilets…" />;
  } else if (flow.phase === 'data-problem') {
    body =
      flow.dataProblem === 'offline' || offline() ? (
        <OfflineShell onRetry={flow.retry} />
      ) : (
        <DataUnavailable kind={flow.dataProblem ?? 'backend'} onRetry={flow.retry} />
      );
  } else if (flow.phase === 'ready' && flow.result && flow.core) {
    const r = flow.result;
    if (r.pool.entries.length === 0) {
      body = <NoToilets onRetry={flow.retry} />;
    } else if (r.go.selectedId == null) {
      body = <NoConfidentOption onRetry={flow.retry} />;
    } else {
      const refreshed = flow.nav.phase === 'refreshed' && (
        <p class="card tone-neutral small" role="status">
          The recommendation was re-checked with your current location and updated. Review it, then
          tap Navigate again.
        </p>
      );
      const footer = (
        <p class="small muted" style="text-align:center">
          {r.pool.entries.length} toilet{r.pool.entries.length === 1 ? '' : 's'} within 15 km ·
          straight-line distances
        </p>
      );

      if (r.focus) {
        body = (
          <div class="stack">
            {refreshed}
            <FocusCard
              result={r}
              core={flow.core}
              onNavigate={() => flow.beginNavigate(r.focus!.id)}
            />
            <AltList result={r} core={flow.core} onPick={(a) => flow.beginNavigate(a.id)} />
            {footer}
          </div>
        );
      } else {
        body = (
          <div class="stack">
            {refreshed}
            <GoCard
              result={r}
              core={flow.core}
              onNavigate={() => flow.beginNavigate(primaryTargetId(r))}
              note={
                r.hintIneligible
                  ? "The facility from this link isn't an eligible current option. Showing ShauchMap's current top pick instead."
                  : undefined
              }
            />
            <AltList result={r} core={flow.core} onPick={(a) => flow.beginNavigate(a.id)} />
            {footer}
          </div>
        );
      }
    }
  } else {
    body = <Spinner label="Loading…" />;
  }

  // FRESH metadata for the confirm / travel sheet — from the (already updated)
  // fresh result, keyed on the actual target, not the GO-selected toilet.
  const targetMeta =
    flow.result && flow.nav.reval?.kind === 'resolved'
      ? freshTargetMeta(flow.result, flow.nav.targetId)
      : { name: 'the facility', distanceMeters: flow.result?.go.selectedDistanceMeters ?? null };

  return (
    <Shell>
      {body}

      {flow.nav.phase === 'revalidating' && (
        <ModalSheet labelledBy="reval-title" onClose={() => undefined}>
          <h2 id="reval-title" class="small muted" style="text-align:center">
            Re-checking your location
          </h2>
          <Spinner label="Re-checking with your current location…" />
        </ModalSheet>
      )}

      {flow.nav.phase === 'nav-problem' && flow.nav.reval?.kind === 'location-problem' && (
        <ModalSheet labelledBy="navprob-title" onClose={flow.dismissNav}>
          <span id="navprob-title" hidden>
            Navigation blocked
          </span>
          <LocationProblem
            outcome={flow.nav.reval.outcome as never}
            onRetry={() => flow.beginNavigate(flow.nav.targetId)}
          />
        </ModalSheet>
      )}

      {flow.nav.phase === 'nav-problem' && flow.nav.reval?.kind === 'data-problem' && (
        <ModalSheet labelledBy="navdata-title" onClose={flow.dismissNav}>
          <span id="navdata-title" hidden>
            Couldn't re-check toilet data
          </span>
          <DataUnavailable kind="backend" onRetry={() => flow.beginNavigate(flow.nav.targetId)} />
        </ModalSheet>
      )}

      {flow.nav.phase === 'confirm' && flow.nav.reval?.kind === 'resolved' && (
        <ConfirmDialog
          title="Confirm before navigating"
          body={
            <>
              This option needs confirmation. Re-checked just now with your current location —{' '}
              <strong>{targetMeta.name}</strong>,{' '}
              {targetMeta.distanceMeters != null
                ? `${Math.round(targetMeta.distanceMeters)} m away`
                : 'distance unknown'}
              . Continue to choose a travel mode and open Google Maps?
            </>
          }
          confirmLabel="Continue"
          onConfirm={() => {
            flow.confirmNavigate();
            setTravelFor(flow.nav.targetId);
          }}
          onClose={flow.dismissNav}
        />
      )}

      {(flow.nav.phase === 'launched' || travelFor !== null) && flow.result && (
        <TravelSheet
          distanceMeters={targetMeta.distanceMeters}
          onPick={(mode) => openMaps(flow.nav.targetId ?? travelFor, mode)}
          onClose={() => {
            setTravelFor(null);
            flow.dismissNav();
          }}
        />
      )}
    </Shell>
  );
}
