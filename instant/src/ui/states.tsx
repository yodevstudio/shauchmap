// First-class failure states . None of these ever render a
// recommendation — a failure must never look like a result.

import type { LocationOutcome } from '../location/geolocation';
import { StateBlock } from './components';
import {
  IconPin, IconBlocked, IconLocationOff, IconClock, IconAlert, IconOffline,
  IconCloudOff, IconSearch, IconHelp,
} from './icons';

export function PermissionExplainer({ onContinue }: { onContinue: () => void }) {
  return (
    <StateBlock
      icon={IconPin}
      title="Share your location to find a toilet"
      body="ShauchMap Instant uses your current location for this search. It doesn't save your location to ShauchMap or build a location history."
      actions={
        <>
          <button class="btn btn-primary" onClick={onContinue}>
            Use my location
          </button>
          <a class="btn btn-ghost" href="/">
            Not now
          </a>
        </>
      }
    />
  );
}

export function PermissionDenied({ onRetry }: { onRetry: () => void }) {
  return (
    <StateBlock
      icon={IconBlocked}
      title="Location permission is blocked"
      body="ShauchMap Instant can't find nearby toilets without your location. Enable location for this site in your browser settings, then try again."
      actions={
        <button class="btn btn-secondary" onClick={onRetry}>
          Try again
        </button>
      }
    />
  );
}

export function LocationUnavailable({ onRetry, reason }: { onRetry: () => void; reason?: string }) {
  return (
    <StateBlock
      icon={IconLocationOff}
      title="Couldn't get a location fix"
      body={
        <>
          Your browser couldn't get a current location{reason ? ` (${reason})` : ''}. Check device
          location services or try again where positioning works better.
        </>
      }
      actions={
        <button class="btn btn-secondary" onClick={onRetry}>
          Try again
        </button>
      }
    />
  );
}

export function LocationTimeout({ onRetry }: { onRetry: () => void }) {
  return (
    <StateBlock
      icon={IconClock}
      title="Location took too long"
      body="Your browser couldn't get a current location in time. Check device location services or try again where positioning works better."
      actions={
        <button class="btn btn-secondary" onClick={onRetry}>
          Try again
        </button>
      }
    />
  );
}

export function StalePosition({ onRetry, ageSeconds }: { onRetry: () => void; ageSeconds: number }) {
  return (
    <StateBlock
      icon={IconClock}
      title="That location is out of date"
      body={
        <>
          The position we got is about {ageSeconds}s old — too stale to trust for a "go now"
          decision. We won't guess. Get a fresh fix and try again.
        </>
      }
      actions={
        <button class="btn btn-primary" onClick={onRetry}>
          Get a fresh location
        </button>
      }
    />
  );
}

export function ImpreciseLocation({ onRetry }: { onRetry: () => void }) {
  return (
    <StateBlock
      icon={IconLocationOff}
      title="Location isn't precise enough yet"
      body="Your browser found your location, but not accurately enough to choose a nearby toilet confidently. Try again, or move where your device can get a better location fix."
      actions={
        <button class="btn btn-secondary" onClick={onRetry}>
          Try again
        </button>
      }
    />
  );
}

export function FuturePosition({ onRetry }: { onRetry: () => void }) {
  return (
    <StateBlock
      icon={IconAlert}
      title="Your device clock looks wrong"
      body="The location came back with a timestamp in the future, so we can't tell how fresh it is. Check your device date & time, then try again."
      actions={
        <button class="btn btn-secondary" onClick={onRetry}>
          Try again
        </button>
      }
    />
  );
}

export function DataUnavailable({
  onRetry,
  kind,
}: {
  onRetry: () => void;
  kind: 'offline' | 'timeout' | 'partial' | 'backend';
}) {
  const body =
    kind === 'offline'
      ? "You're offline. ShauchMap Instant needs a connection to check current toilet status."
      : kind === 'timeout'
        ? 'Loading nearby toilets took too long. Check your connection and try again.'
        : kind === 'partial'
          ? "Some map regions didn't load. Showing a result now could hide a closer option, so we're not showing one."
          : "We couldn't load toilet data just now.";
  return (
    <StateBlock
      icon={kind === 'offline' ? IconOffline : IconCloudOff}
      title={kind === 'offline' ? "You're offline" : "Couldn't load toilet data"}
      body={body}
      actions={
        <button class="btn btn-secondary" onClick={onRetry}>
          Try again
        </button>
      }
    />
  );
}

export function OfflineShell({ onRetry }: { onRetry?: () => void }) {
  return (
    <StateBlock
      icon={IconOffline}
      title="You're offline"
      body="ShauchMap Instant needs a connection to refresh toilet status. Nothing here is cached as current — reconnect and try again."
      actions={
        onRetry ? (
          <button class="btn btn-secondary" onClick={onRetry}>
            Try again
          </button>
        ) : undefined
      }
    />
  );
}

export function NoToilets({ onRetry }: { onRetry: () => void }) {
  return (
    <StateBlock
      icon={IconSearch}
      title="No mapped toilets within 15 km"
      body="ShauchMap doesn't have a mapped toilet within 15 km of this location."
      actions={
        <button class="btn btn-secondary" onClick={onRetry}>
          Search again
        </button>
      }
    />
  );
}

export function NoConfidentOption({ onRetry }: { onRetry: () => void }) {
  return (
    <StateBlock
      icon={IconHelp}
      title="No confident recommendation"
      body="There are nearby records, but every one is flagged, unconfirmed, or a candidate. ShauchMap Instant won't recommend one as if it were reliable."
      actions={
        <button class="btn btn-secondary" onClick={onRetry}>
          Search again
        </button>
      }
    />
  );
}

// HintUnavailable removed — a linked facility that isn't an
// eligible current GO focus is NOT an error. The normal top pick is shown with a
// concise inline note (see GoCard `note` in go-screen.tsx). No dead-end button.

/** Route a LocationOutcome to the right failure state. */
export function LocationProblem({
  outcome,
  onRetry,
}: {
  outcome: Exclude<LocationOutcome, { status: 'ok' }>;
  onRetry: () => void;
}) {
  switch (outcome.status) {
    case 'denied':
      return <PermissionDenied onRetry={onRetry} />;
    case 'prompt':
      return <PermissionExplainer onContinue={onRetry} />;
    case 'timeout':
      return <LocationTimeout onRetry={onRetry} />;
    case 'future':
      return <FuturePosition onRetry={onRetry} />;
    case 'imprecise':
      return <ImpreciseLocation onRetry={onRetry} />;
    case 'stale':
      return <StalePosition onRetry={onRetry} ageSeconds={outcome.ageSeconds} />;
    case 'unavailable':
      return <LocationUnavailable onRetry={onRetry} reason={outcome.reason} />;
  }
}
