# Manual Print Font Size Rendering Design

**Date:** 2026-07-31

## Problem

When manual print typography is enabled, font sizes from 12.5pt through 20pt
are stored and displayed in settings but are not reflected in preview or PDF
output. `LayoutCalculator` silently reduces the requested size to a
geometry-derived maximum. With the default A6 density, that maximum is about
12pt, so every larger selection renders at effectively the same size.

## Intended Behavior

- A manually selected print font size from 7pt through 20pt is used as the
  rendered body font size in preview and PDF output.
- Manual character-count and line-count settings remain unchanged. Users may
  reduce them when a larger font needs more space.
- Recommended typography continues to choose a readable combination of font
  size, characters per line, and lines per page before layout.
- Existing validation continues to round print font sizes to 0.5pt and clamp
  them to the supported 7pt through 20pt range.

## Design

`LayoutCalculator` will stop applying a second, hidden font-size ceiling based
on `lineAdvance` and `characterAdvance`. It will pass the already validated
`EditorSettings.fontSize` directly into `PageLayout`.

This keeps responsibilities separate:

- `EditorSettings.validated` owns supported-range validation and half-point
  rounding.
- `RecommendedPrintSettings` owns automatic readable-density decisions.
- `LayoutCalculator` converts accepted settings into page geometry without
  rewriting a manual font-size choice.

No settings UI, persistence format, pagination rules, or recommendation
presets will change.

## Verification

Add a regression test against the real `LayoutCalculator` behavior. With A6
manual settings and the default 38 characters by 16 lines, the test will verify
that both 12.5pt and 20pt remain unchanged in the resulting `PageLayout`.
Before the production change, this test must fail because both values are
reduced to about 12pt.

After the fix:

1. Run the focused layout regression test.
2. Run existing recommendation tests to confirm readable automatic settings
   remain valid.
3. Run the full Honkumi test suite and relevant build verification.
