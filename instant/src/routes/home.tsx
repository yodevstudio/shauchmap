import { useEffect, useState } from 'preact/hooks';
import { Shell } from '../ui/components';
import { checkPermission, type PermissionState } from '../location/geolocation';

/** Landing . Mobile-first; states the purpose immediately; explains
 *  before asking for location when permission is still 'prompt'/'unknown'. */
export function Home() {
  const [perm, setPerm] = useState<PermissionState>('unknown');
  useEffect(() => {
    void checkPermission().then(setPerm);
  }, []);

  const primaryLabel = perm === 'granted' ? 'Find a toilet' : 'Use my location';

  return (
    <Shell header={false}>
      <section class="hero stack">
        <img class="logo" src="/icons/icon.svg" alt="ShauchMap" width={72} height={72} />
        <h1>Find a nearby public toilet</h1>
        <p>
          ShauchMap checks nearby mapped toilets and recent condition evidence, then shows the best
          option it can support right now. If the condition is unknown, it says so. Open the result
          in Google Maps when you're ready.
        </p>
      </section>

      <div class="stack" style="margin-top:18px">
        <a class="btn btn-primary" href="/go">
          {primaryLabel}
        </a>
        {perm !== 'granted' && (
          <p class="small muted" style="text-align:center">
            We'll explain why before asking for location. ShauchMap Instant doesn't save your
            location or build a location history.
          </p>
        )}
      </div>

      <section class="card" style="margin-top:22px">
        <h2 class="small muted" style="text-transform:uppercase;letter-spacing:0.04em">
          What you'll get
        </h2>
        <ul class="small" style="margin:8px 0 0;padding-left:18px;color:var(--ink-2)">
          <li>One clear recommendation — where to go, how far, why.</li>
          <li>Honest labels: “unknown” stays unknown; ratings aren't treated as facts.</li>
          <li>Re-checked against your live location the moment you tap Navigate.</li>
          <li>No map to pan. No sign-in required.</li>
        </ul>
      </section>
    </Shell>
  );
}
