import { describe, it, expect, afterEach } from 'vitest';
import { render } from 'preact';
import { act } from 'preact/test-utils';
import { ModalSheet } from '../src/ui/travel-sheet';

let host: HTMLDivElement;
afterEach(() => {
  if (host) act(() => render(null, host));
  document.body.classList.remove('modal-open');
});
function mount(vnode: any): HTMLDivElement {
  host = document.createElement('div');
  document.body.appendChild(host);
  act(() => render(vnode, host));
  return host;
}

describe('ModalSheet a11y ', () => {
  it('is a labelled modal dialog', () => {
    const el = mount(
      <ModalSheet labelledBy="t" onClose={() => {}}>
        <h2 id="t">Title</h2>
        <button>Go</button>
      </ModalSheet>,
    );
    const dlg = el.querySelector('.sheet')!;
    expect(dlg.getAttribute('role')).toBe('dialog');
    expect(dlg.getAttribute('aria-modal')).toBe('true');
    expect(dlg.getAttribute('aria-labelledby')).toBe('t');
    expect(dlg.getAttribute('tabindex')).toBe('-1');
  });

  it('locks body scroll while open and unlocks on close', () => {
    expect(document.body.classList.contains('modal-open')).toBe(false);
    const el = mount(
      <ModalSheet labelledBy="t" onClose={() => {}}>
        <h2 id="t">T</h2>
      </ModalSheet>,
    );
    expect(document.body.classList.contains('modal-open')).toBe(true);
    act(() => render(null, el));
    expect(document.body.classList.contains('modal-open')).toBe(false);
  });

  it('Escape triggers onClose', () => {
    let closed = 0;
    mount(
      <ModalSheet labelledBy="t" onClose={() => closed++}>
        <h2 id="t">T</h2>
      </ModalSheet>,
    );
    act(() => {
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    });
    expect(closed).toBe(1);
  });

  it('restores focus to the element that opened it', () => {
    const opener = document.createElement('button');
    opener.textContent = 'open';
    document.body.appendChild(opener);
    opener.focus();
    expect(document.activeElement).toBe(opener);

    const el = mount(
      <ModalSheet labelledBy="t" onClose={() => {}}>
        <h2 id="t">T</h2>
        <button>inside</button>
      </ModalSheet>,
    );
    expect(el.contains(document.activeElement)).toBe(true);
    act(() => render(null, el));
    expect(document.activeElement).toBe(opener);
    opener.remove();
  });

  it('Tab from the last focusable wraps to the first (focus trap)', () => {
    const el = mount(
      <ModalSheet labelledBy="t" onClose={() => {}}>
        <h2 id="t">T</h2>
        <button id="a">A</button>
        <button id="b">B</button>
      </ModalSheet>,
    );
    const a = el.querySelector('#a') as HTMLButtonElement;
    const b = el.querySelector('#b') as HTMLButtonElement;
    b.focus();
    act(() => {
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Tab', bubbles: true }));
    });
    expect(document.activeElement).toBe(a);
  });
});
