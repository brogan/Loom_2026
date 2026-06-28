# Loom — Deferred Work

Items that are known, understood, and intentionally deferred. Each entry
records what needs doing, why it was deferred, and any known constraints
or dependencies. Pick up items from here when the triggering condition is
met rather than implementing ahead of need.

---

## Help Documentation

### PDF TOC — page numbers

**What:** The printed/PDF table of contents currently has no page numbers.
Dotted leaders trail to nothing.

**Why deferred:** Browser-based PDF export (Safari/Chrome print-to-PDF)
does not support the CSS `target-counter` property, which is the standard
mechanism for inserting destination page numbers in a hyperlinked TOC.
Page numbers require a proper CSS paged-media engine such as
[WeasyPrint](https://weasyprint.org) or
[Prince](https://www.princexml.com), or a JavaScript pre-processing step
that walks the DOM, resolves element positions to page numbers after a
layout pass, and injects them before printing.

**When to do:** When the help is sufficiently stable that a PDF with
permanent page references is genuinely useful — i.e. after the core
feature set is settled and the section structure stops changing
frequently.

**Approach options:**
- Adopt WeasyPrint or Prince as the PDF build step, replacing
  browser print. Enables full CSS paged-media including `target-counter`,
  running headers/footers, and proper `@page` control.
- Write a small JavaScript function that runs on `window.beforeprint`,
  walks every `.toc-entry a[href]`, resolves each target element's
  approximate page position (`offsetTop / pageHeightPx`), and injects
  the number into a `.toc-page` span at the end of each entry. Fragile
  but zero new tooling.
- Accept the absence of page numbers and add a cover note directing
  readers to use the clickable links.

---

### Help index

**What:** A comprehensive alphabetical index at the end of the help PDF,
mapping terms, feature names, and concepts to the sections that cover
them. Standard reference-manual feature; essential once the doc grows
beyond ~50 pages.

**Why deferred:** An index is most useful when the section structure is
stable. Maintaining an index during active feature development means
constant revision. Build it once, near the end of the active
development phase.

**Approach:** Write the index as a new `<section id="index">` at the end
of `help.html`, structured as a two-or-three-column alphabetical list of
`<a href="#anchor">term</a>` entries. Each term links to the most
relevant anchor in the document. The section gets an `@media print`
`page-break-before: always` rule. Nav entry added to the sidebar and TOC
at the same time.

---

## Engine

### Selective image loading

See note in `SPEC_cycle_name_driver_and_variant_images.md` (Feature 2,
Image loading section).

**What:** `LoomEngine.loadSVGImages` currently loads every file in
`svgs/sprites/` unconditionally at project open. As the folder grows this
increases startup time and idle memory.

**When to do:** When project-open time becomes noticeable, or when
`svgs/sprites/` grows past roughly 20–30 non-trivial images.

**Approach:** Build a reference set by scanning all `svgFilename`,
cycle-state image, and variant image fields before loading. Load only
filenames that appear in that set. This refactor belongs together with
any future per-variant image loading work — not as a separate patch.
