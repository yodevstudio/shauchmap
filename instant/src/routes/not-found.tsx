import { Shell, StateBlock } from '../ui/components';
import { IconCompass } from '../ui/icons';

export function NotFound() {
  return (
    <Shell>
      <StateBlock
        icon={IconCompass}
        title="Page not found"
        body="That link doesn't point anywhere in ShauchMap Instant."
        actions={
          <a class="btn btn-primary" href="/go">
            Find a toilet
          </a>
        }
      />
    </Shell>
  );
}
