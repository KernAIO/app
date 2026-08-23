# The Kern mark

The K and the accent tick, on an ink square.

```
assets/kern-mark.svg         ink square, paper K         the default
assets/kern-mark-dark.svg    paper square, ink K         on a dark ground
assets/kern-mark-mono.svg    one even-odd path           takes currentColor, any ground
assets/kern-lockup.svg       mark + "Kern"               425×144
assets/kern-lockup-dark.svg  mark + "Kern"               on a dark ground
```

## Geometry

Everything is drawn on a 144×144 grid.

| | value |
|---|---|
| square corner radius | 36 |
| K | Instrument Sans `wght` 600, `EM` = 76/1000 |
| K ink width | 47.88 |
| K cap height | 54.72 |
| K → tick | 9.5 |
| tick | 9 × 56, radius 4.5 |

The K and the tick are centred **as a group**: their combined width is 66.38, so the group starts
at 38.81 and the tick at 96.19. The K's cap box is centred on the tick's 56, which puts the
baseline at 99.36.

This is the part that was wrong for a long time. `<text>` centres a glyph's *advance box*, which
includes its side bearings, and the tick was then positioned against that — so the pair sat
visibly left of the square's centre at every size. Centre the measured ink, not the advance.

Colours are the design-system tokens, not separate brand values: ink `#1C1A17`, paper `#FBFAF7`,
accent `#B4661C`.

## The lockup

Cap height 84, gap 40, the wordmark's cap box centred on the mark. "Kern" is Instrument Sans
`wght` 700, kerned, tracked −0.025em.

## Why the letterforms are outlines

Both the K and the wordmark are paths, never `<text>`.

An SVG loaded as an `<img>` — a favicon, a README image, Starlight's `logo` option — cannot reach a
web font, and a `<text>` mark silently falls back to whatever the rasteriser happens to have.
sharp on CI has no Instrument Sans and renders Helvetica without complaint.

This is also why `RailLogo` draws an SVG rather than a styled `<span>`: a CSS-drawn mark is a
fourth thing to keep in sync, and it drifts.

## Changing it

Each surface generates its own icons from its own copy of the geometry, because the repositories
are independent and none of them can read this one at build time:

| | |
|---|---|
| `website/scripts/gen-assets.mjs` | `pnpm assets` — favicons, app icons, the social card |
| `app/scripts/gen-icons.mjs` | `pnpm icons` — favicon, app icons, maskable icons |
| `docs/public/`, `docs/src/assets/` | committed by hand; no generator |
| `kernel` `RailLogo.svelte` | inline SVG in the component |

Change the mark and you change all four, plus `assets/` here — which is what the org profile README
loads, by raw URL from `main`.
