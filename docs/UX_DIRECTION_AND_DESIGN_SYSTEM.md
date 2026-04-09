# Jott Notes UX Direction and Design System Kickoff

## 1) UX Direction

Design principle: calm productivity with soft personality.

- Minimalism: reduce visual noise, keep one clear primary action per screen.
- Cuteness: gentle corner radii, warm accent colors, soft contrast.
- Beauty: layered surfaces, consistent spacing rhythm, polished motion.

Product tone:
- Fast and focused first (capture in <3 seconds).
- Supportive feedback, never noisy.
- Information-dense only when users ask for it (lists, detail, search states).

## 2) Foundational System

### Color roles

Keep existing palette assets and treat them as semantic roles:

- `jott-bar`: primary input/container surface.
- `jott-border`: standard 1pt stroke for separation.
- `jott-input-text`: primary body text.
- `jott-placeholder`: secondary guidance text.
- `jott-cursor`: active input/caret/link emphasis.
- `jott-note-accent`: note actions and badges.
- `jott-reminder-accent`: reminder actions and badges.
- `jott-meeting-accent`: meeting actions and badges.
- `jott-detail-background`: detail screen base surface.
- `jott-link-text`, `jott-link-underline`: wiki link and inline link styling.

Implementation guidance:
- Avoid hard-coded `Color(red:...)` in views.
- Use only semantic asset names in UI files.
- Keep all new color assets additive and role-based (not feature-named).

### Typography scale

Use a compact, native-first scale:

- Display: `title2` semibold (screen titles).
- Heading: `headline` semibold (section headers).
- Body: `body` regular (default content).
- Support: `subheadline` regular (metadata).
- Caption: `caption` medium (timestamps, badges).

Implementation guidance:
- Prefer `.font(.system(..., design: .rounded))` only for expressive UI areas (badges/pills).
- Keep editor and long-form content in default readable text style.

### Spacing and radius scale

- Spacing: 4, 8, 12, 16, 20, 24.
- Radius: 8 (small controls), 12 (cards), 16 (primary capture surfaces), 20 (hero pills).
- Borders: 1pt only; avoid mixed border widths in same component family.

### Motion

- Overlay open: 150ms ease-out (already implemented).
- Overlay close: 100ms ease-in (already implemented).
- Badge/feedback transitions: 120-180ms spring with low bounce.
- No long or looping decorative animation in core capture flow.

## 3) Core Components

### Capture bar

Behavior goals:
- Keep input as strongest visual anchor.
- Badge, format tools, and feedback stay secondary.

Specs:
- Height baseline: 52-60pt depending on multiline content.
- Container radius: 16.
- Internal horizontal padding: 14-16.
- Use placeholder and border tokens consistently.

Primary files:
- `jott/Views/CaptureInputView.swift`
- `jott/Views/UnifiedJottView.swift`

### Type badge + feedback pill

Behavior goals:
- Distinguish note/reminder/meeting at a glance.
- Confirm save action within 1 second, then fade.

Specs:
- Shared capsule family (20 radius).
- Icon + label baseline-aligned.
- Content padding: 8 vertical, 12 horizontal.

Primary files:
- `jott/Views/OverlayView.swift`
- `jott/ViewModel/OverlayViewModel.swift`

### Lists (notes/reminders/meetings)

Behavior goals:
- Scannable rows, clear active/selected state, no visual clutter.

Specs:
- Row vertical padding: 10-12.
- Row radius: 12.
- Metadata in caption style with reduced contrast.
- Accent line/chip per item type.

Primary files:
- `jott/Views/LibraryView.swift`
- `jott/Views/RemindersListView.swift`
- `jott/Views/MeetingsListView.swift`

### Detail view

Behavior goals:
- Reading comfort first, editing controls discoverable but quiet.

Specs:
- Section gap: 16.
- Header actions grouped by intent (edit/share/info/destructive).
- Keep footers and system metadata in support/caption style.

Primary file:
- `jott/Views/DetailView.swift`

## 4) Design QA Checklist

Use this before shipping UI updates:

- No hard-coded color values introduced in views.
- Color role is semantically correct for context.
- Spacing follows 4/8-based scale.
- Border usage is 1pt and consistent.
- Body text remains readable at default macOS sizes.
- Keyboard-first flow unchanged (`Option+Space`, Enter, arrows, Escape).
- Feedback states visible but non-blocking.

## 5) Implementation Plan (Engineering Handoff)

1. Introduce style token wrappers for typography, spacing, radius in a single shared file.
2. Refactor capture bar + floating pills to consume tokens first.
3. Normalize list row spacing/radius/metadata hierarchy.
4. Normalize detail view spacing and action grouping.
5. Add a lightweight visual QA pass against the checklist above.

## 6) Out of Scope for Kickoff

- New visual themes.
- Dark mode redesign.
- New navigation structure.
- Animation-heavy effects.

This kickoff establishes a stable baseline; iterate from this system rather than one-off visual tweaks.
