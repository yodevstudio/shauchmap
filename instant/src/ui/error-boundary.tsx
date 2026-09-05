import { Component, type ComponentChildren } from 'preact';
import { IconError } from './icons';
import { Shell, StateBlock } from './components';

interface Props {
  children: ComponentChildren;
}
interface State {
  error: Error | null;
}

/** App-level safety net. A thrown error (e.g. CoreVersionMismatchError) shows a
 *  plain "can't start" panel — never a blank screen, never a fake result. */
export class AppErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error) {
    console.error('[ShauchMap Instant] fatal:', error);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <Shell>
        <StateBlock
          icon={IconError}
          title="ShauchMap Instant can't start"
          body={this.state.error.message}
          actions={
            <button class="btn btn-secondary" onClick={() => location.reload()}>
              Reload
            </button>
          }
        />
      </Shell>
    );
  }
}
