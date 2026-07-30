# Circle Logo and Colophon Regression Design

## Goal

Fix the circle-logo and colophon regressions reported from the device build without adding preview or PDF runtime work:

- Accept the supplied `logo.svg` and `title.svg`.
- Remove the monochrome recommendation copy.
- Hide author and circle controls and output rows while a circle logo is actively used.
- Preserve work-specific colophon settings when common settings are applied.
- Left-align the website URL with other colophon values and center the QR code over that URL.

## Confirmed Root Causes

### Percentage-sized SVG files are rejected before rendering

Both supplied SVG files use `width="100%"` and `height="100%"` with a valid `viewBox`. `CircleLogoSVGSizeParser` currently treats an explicit unsupported length as fatal, so it returns before using the valid `viewBox`.

The supplied intrinsic sizes are:

- `logo.svg`: `viewBox="0 0 1024 1024"`
- `title.svg`: `viewBox="0 0 2400 1000"`

### Common settings replace work-specific colophon state

`DocumentStore.resolveUserDefaultSettingsReview` currently assigns the complete validated common `EditorSettings` to the work. The common colophon screen does not expose the work-specific `isEnabled` option, so its stored `false` value disables a colophon that the work had enabled.

### Horizontal QR layout centers the URL block

`drawHorizontalColophonHPEntry` currently centers a combined QR-and-URL block in the value column. This shifts the URL right instead of starting it at the same value position as the other colophon rows.

## Design

### SVG import

Keep the existing upload-time WebKit conversion and PNG storage. No SVG parsing or rendering is added to preview or PDF generation.

The size parser will classify root dimensions as either:

- absolute supported lengths, such as unitless values, `px`, `pt`, `pc`, `in`, `cm`, `mm`, or `q`; or
- relative/unspecified dimensions, such as percentages.

Absolute width and height continue to determine the source size. A missing or relative dimension falls back to the corresponding ratio from a valid `viewBox`. When both dimensions are relative, the complete `viewBox` size is used. Import remains an error when no positive finite size can be derived.

The renderer keeps its current 2048-pixel maximum long edge and transparent PNG output. Raster imports continue to preserve their original bytes.

### Settings UI and colophon entries

Remove `CircleLogoImportCopy.monochromeRecommendation` and its `Text` view.

Use `ColophonSettings.hasCreatorImage` as the single active-logo condition. It is true only when:

- `usesCircleImageForCreator` is enabled; and
- `circleImageData` exists.

While that condition is true:

- hide the author visibility toggle and author text field;
- hide the circle visibility toggle and circle text field;
- omit the author and circle entries from preview and PDF pagination.

The author and circle strings and their visibility flags remain stored unchanged. Disabling or deleting the logo makes the controls and entries available again with their prior values.

### Applying common settings

Common settings still replace all non-colophon work settings as before.

Colophon settings are merged instead of replaced. Begin with the work's current colophon and copy the common publisher information through the existing `applyingPublisherInfo(from:)` boundary.

Preserve these work-specific fields:

- `isEnabled`
- `workTitle`
- `showsPublicationDate`
- `showsPrinterName`
- `publicationDate`
- `printerName`

Apply these common publisher fields:

- publisher, author, and circle names;
- author and circle image data;
- active circle-logo selection;
- publisher, author, circle, website, and QR visibility flags;
- website, X, pixiv, contact, and notes values.

The formatting decision is calculated from the resulting merged settings. The work body is formatted only when the resulting auto-format setting is enabled.

### QR and URL layout

For horizontal colophon output:

- keep the `HP` label at the existing label origin;
- draw a visible URL from the same `valueX` used by all other values;
- position the QR code so its horizontal center matches the visible URL layout's horizontal center;
- when the URL is hidden and only the QR code is shown, center the QR code in the complete value column.

The vertical colophon path already begins the URL at its shared `valueX` and centers the QR code from the URL width. Regression coverage will ensure it continues to follow the same rule.

Extract the horizontal coordinate calculation into a small value-type layout helper so alignment can be tested without inspecting private Core Graphics drawing state.

## Error Handling

- File-picker cancellation remains silent and preserves the previous logo.
- A valid `viewBox` makes percentage root dimensions acceptable.
- Invalid XML, a non-SVG root, or SVG content with no derivable positive finite size returns the existing specific SVG import error.
- A WebKit snapshot or PNG validation failure returns the existing conversion error.
- A failed replacement never clears the previous logo.

## Performance

SVG conversion runs once when the user uploads the file. The stored result remains PNG data consumed by the existing `UIImage` and PDF paths.

The UI and colophon-entry changes use an existing computed property and simple filtering. The common-settings merge is a value copy performed only when the user chooses to apply settings. The QR layout helper performs constant-time arithmetic. None of these changes adds pagination or preview regeneration work.

## Test Strategy

Use red-green TDD for each behavior:

1. Add importer tests for percentage width and height with a valid `viewBox`, including square and wide aspect ratios.
2. Add an importer test proving percentage-only dimensions without a `viewBox` remain invalid.
3. Add presentation-copy coverage proving the monochrome recommendation is absent.
4. Add colophon-entry tests proving an active logo omits author and circle entries while stored values remain unchanged, and that disabling the logo restores the entries.
5. Change the common-settings review test to prove all common groups are applied while work-specific colophon fields remain intact.
6. Add coordinate-helper tests proving the URL starts at `valueX`, the QR is centered over the visible URL, and QR-only output is centered in the value column.
7. Run the supplied `logo.svg` and `title.svg` through the importer as local integration inputs.
8. Run the complete XCTest suite and Debug, Staging, and Release builds.
9. Build and reinstall the resulting Debug app on the connected device.

## Acceptance Criteria

- Both supplied SVG files upload successfully and produce PNG data with the expected aspect ratio.
- The monochrome recommendation is not visible.
- An active circle logo hides author and circle controls and output rows without deleting their values.
- Removing or disabling the logo restores the prior author and circle values and visibility choices.
- Applying changed common settings cannot disable an already enabled work colophon or overwrite its publication date or printer information.
- A visible URL starts at the shared value origin, and its QR code is centered over the URL.
- No new SVG work occurs during preview or PDF generation.
