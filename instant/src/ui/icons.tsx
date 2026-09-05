// Tiny local SVG icon set . No external package. 24×24
// viewBox, 1.75 stroke, `currentColor`, rounded caps. Always decorative:
// rendered with aria-hidden and paired with visible text.

import type { JSX } from 'preact';

type P = { size?: number } & JSX.SVGAttributes<SVGSVGElement>;

function Svg({ size = 24, children, ...rest }: P & { children: preact.ComponentChildren }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      focusable="false"
      {...rest}
    >
      {children}
    </svg>
  );
}

export const IconPin = (p: P) => (
  <Svg {...p}>
    <path d="M12 21s-6.5-6-6.5-10.5A6.5 6.5 0 0 1 18.5 10.5C18.5 15 12 21 12 21Z" />
    <circle cx="12" cy="10.5" r="2.4" />
  </Svg>
);

export const IconBlocked = (p: P) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="m6.4 6.4 11.2 11.2" />
  </Svg>
);

export const IconLocationOff = (p: P) => (
  <Svg {...p}>
    <path d="M12 21s-6.5-6-6.5-10.5a6.5 6.5 0 0 1 2.1-4.8" />
    <path d="M9.6 4.6A6.5 6.5 0 0 1 18.5 10.5c0 2-1.3 4.2-2.8 6.1" />
    <path d="m4 4 16 16" />
  </Svg>
);

export const IconClock = (p: P) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 7.5V12l3 1.8" />
  </Svg>
);

export const IconAlert = (p: P) => (
  <Svg {...p}>
    <path d="M12 3.5 21 19H3l9-15.5Z" />
    <path d="M12 10v4" />
    <path d="M12 17h.01" />
  </Svg>
);

export const IconOffline = (p: P) => (
  <Svg {...p}>
    <path d="M2 8.8A15 15 0 0 1 8 5.6" />
    <path d="M22 8.8a15 15 0 0 0-6.5-3.4" />
    <path d="M5 12.5a10 10 0 0 1 3-1.9" />
    <path d="M19 12.5a10 10 0 0 0-3.5-2" />
    <path d="M8.5 16.2a5 5 0 0 1 7 0" />
    <path d="M12 20h.01" />
    <path d="m3 3 18 18" />
  </Svg>
);

export const IconCloudOff = (p: P) => (
  <Svg {...p}>
    <path d="M7 18a4 4 0 0 1-.6-7.95A6 6 0 0 1 16.5 7.5" />
    <path d="M18.5 9.2A4 4 0 0 1 18 18H10" />
    <path d="m3 3 18 18" />
  </Svg>
);

export const IconSearch = (p: P) => (
  <Svg {...p}>
    <circle cx="11" cy="11" r="6.5" />
    <path d="m20 20-4.3-4.3" />
  </Svg>
);

export const IconHelp = (p: P) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M9.6 9.4a2.5 2.5 0 0 1 4.8.9c0 1.7-2.4 2.2-2.4 3.7" />
    <path d="M12 17h.01" />
  </Svg>
);

export const IconError = (p: P) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 8v4.5" />
    <path d="M12 16h.01" />
  </Svg>
);

export const IconCompass = (p: P) => (
  <Svg {...p}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="m15.5 8.5-2 5-5 2 2-5 5-2Z" />
  </Svg>
);

export const IconCar = (p: P) => (
  <Svg {...p}>
    <path d="M4 13.5 5.6 8A2 2 0 0 1 7.5 6.5h9A2 2 0 0 1 18.4 8L20 13.5" />
    <path d="M3.5 13.5h17V17a1 1 0 0 1-1 1h-1.5a1 1 0 0 1-1-1v-1H7v1a1 1 0 0 1-1 1H4.5a1 1 0 0 1-1-1v-3.5Z" />
    <path d="M7 15h.01M17 15h.01" />
  </Svg>
);

export const IconScooter = (p: P) => (
  <Svg {...p}>
    <circle cx="6" cy="17.5" r="2.5" />
    <circle cx="18" cy="17.5" r="2.5" />
    <path d="M8.5 17.5h7l-2-9H11" />
    <path d="M15.5 8.5H18l1.5 6" />
    <path d="M6 17.5 9.5 10" />
  </Svg>
);

export const IconWalk = (p: P) => (
  <Svg {...p}>
    <circle cx="13" cy="4.5" r="1.6" />
    <path d="M12.5 8 10 10.5l1 4-2.5 5" />
    <path d="M11 14.5 15 16l1.5 4" />
    <path d="M12.7 8.4 16 10l-1.5 3" />
    <path d="M12 10.5 8.5 12" />
  </Svg>
);
