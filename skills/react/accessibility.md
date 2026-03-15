# React Accessibility

## Semantic HTML First

The most important accessibility rule: use the correct HTML element for the job. Native elements come with built-in keyboard support, ARIA roles, and browser accessibility APIs at no cost.

```tsx
// BAD — div cannot be focused by keyboard, has no implicit role
<div onClick={handleDelete} className="delete-btn">Delete</div>

// GOOD — button is focusable, activates on Enter/Space, has role="button"
<button type="button" onClick={handleDelete}>Delete</button>

// BAD — span used as a link
<span onClick={() => navigate('/about')} className="link">About</span>

// GOOD — anchor with proper href
<a href="/about">About</a>
```

### Semantic Landmark Elements

Use these to give screen reader users navigation landmarks:

```tsx
<header>     {/* Site header, logo, primary nav */}
<nav>        {/* Navigation menus */}
<main>       {/* Main page content — only ONE per page */}
<aside>      {/* Supplementary content, sidebars */}
<footer>     {/* Site footer */}
<section>    {/* Thematic content group — should have a heading */}
<article>    {/* Self-contained content: blog post, comment, card */}
```

```tsx
// Correct page structure
function AppLayout() {
  return (
    <>
      <header>
        <nav aria-label="Main navigation">
          <a href="/">Home</a>
          <a href="/products">Products</a>
        </nav>
      </header>
      <main>
        <h1>Products</h1>
        {/* page content */}
      </main>
      <footer>
        <p>© 2024 Acme Corp</p>
      </footer>
    </>
  );
}
```

DON'T: Use `<div>` or `<span>` when a semantic element exists.
DON'T: Skip heading levels (e.g., go from `<h1>` to `<h3>`).

---

## ARIA Roles

Use ARIA only when semantic HTML is insufficient. ARIA supplements but never replaces semantic HTML.

```tsx
// ONLY add role when the element has no implicit semantic role
// and there is no appropriate HTML element for the purpose

// Custom progress indicator (no native element for this)
<div
  role="progressbar"
  aria-valuenow={progress}
  aria-valuemin={0}
  aria-valuemax={100}
  aria-label="Upload progress"
>
  <div style={{ width: `${progress}%` }} />
</div>

// BAD — redundant ARIA (button already has role="button")
<button role="button">Click me</button>

// BAD — misused ARIA (don't override native semantics)
<h2 role="button" onClick={toggle}>Section</h2>
// Use: <button> inside the heading, or a disclosure pattern
```

First rule of ARIA: if you can use a native HTML element with the semantics you need, do that instead.

---

## Accessible Names

Every interactive element and every landmark region must have an accessible name.

```tsx
// aria-label — use when visible text label is absent or insufficient
<button aria-label="Close dialog" onClick={onClose}>
  <XIcon aria-hidden="true" />
</button>

// aria-labelledby — reference another element's text
<section aria-labelledby="orders-heading">
  <h2 id="orders-heading">Recent Orders</h2>
  {/* content */}
</section>

// Multiple navs on a page — each needs a distinct label
<nav aria-label="Main navigation">...</nav>
<nav aria-label="Breadcrumb">...</nav>
<nav aria-label="Pagination">...</nav>

// Icon buttons must always have a label
<button aria-label="Delete item">
  <TrashIcon aria-hidden="true" />
</button>
```

DON'T: Leave interactive elements without accessible names — screen readers will announce them as "button" with no context.
DON'T: Use `aria-label` to hide meaningful visible text — if text is visible, use it as the label.

---

## Images

```tsx
// Meaningful image — describe what it conveys
<img src="/team-photo.jpg" alt="Five team members gathered around a conference table" />

// Decorative image — empty alt so screen readers skip it
<img src="/decorative-divider.svg" alt="" role="presentation" />

// Inline SVG icons — hide from screen readers when used decoratively
<svg aria-hidden="true" focusable="false">
  <use href="#icon-search" />
</svg>

// Standalone SVG icon with meaning — provide a title
<svg role="img" aria-labelledby="icon-title">
  <title id="icon-title">Search</title>
  <use href="#icon-search" />
</svg>
```

DON'T: Use `alt="image"`, `alt="photo"`, or `alt="logo"` — these add no value.
DON'T: Omit the `alt` attribute — this is different from `alt=""`. Omitting it causes screen readers to read the file name instead.

---

## Form Accessibility

Every form input must have a visible label associated with it.

```tsx
// GOOD — explicit association via htmlFor / id
<div>
  <label htmlFor="email">Email address</label>
  <input
    id="email"
    type="email"
    autoComplete="email"
    aria-required="true"
    aria-invalid={!!errors.email}
    aria-describedby={errors.email ? 'email-error' : 'email-hint'}
  />
  <p id="email-hint">We'll send your receipt here.</p>
  {errors.email && (
    <p id="email-error" role="alert">{errors.email.message}</p>
  )}
</div>

// BAD — placeholder only (disappears on input, fails contrast requirements)
<input type="email" placeholder="Email address" />

// BAD — visually hidden label makes the form unusable for sighted users
// who use screen magnification or have cognitive disabilities
```

Key attributes:
- `htmlFor` on `<label>` must exactly match `id` on `<input>`
- `aria-invalid="true"` when the field has a validation error
- `aria-describedby` pointing to the error element id
- `aria-required="true"` for required fields (in addition to visual indicator)
- `role="alert"` on error messages so they are announced immediately

```tsx
// Required field indicator — never rely on color alone
<label htmlFor="name">
  Full name <span aria-hidden="true">*</span>
  <span className="sr-only">(required)</span>
</label>
```

---

## Focus Management

Keyboard users navigate entirely via focus. Every interactive element must be reachable and clearly indicated.

```tsx
// GOOD — visible focus indicator in CSS
// Ensure :focus-visible has a visible outline. Never do this:
// button:focus { outline: none; } — removes focus visibility without replacement

// Custom focus style
button:focus-visible {
  outline: 2px solid #005fcc;
  outline-offset: 2px;
  border-radius: 4px;
}
```

### Focus Trap in Modals

When a modal is open, keyboard focus must stay within it until it is closed.

```tsx
import { useEffect, useRef } from 'react';

function Modal({ isOpen, onClose, children }: ModalProps) {
  const modalRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!isOpen) return;

    // Move focus into the modal when it opens
    const firstFocusable = modalRef.current?.querySelector<HTMLElement>(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    );
    firstFocusable?.focus();

    // Trap focus inside
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onClose();
        return;
      }
      if (e.key !== 'Tab') return;

      const focusable = modalRef.current?.querySelectorAll<HTMLElement>(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      );
      if (!focusable?.length) return;

      const first = focusable[0];
      const last = focusable[focusable.length - 1];

      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  return (
    <div
      ref={modalRef}
      role="dialog"
      aria-modal="true"
      aria-labelledby="modal-title"
    >
      <h2 id="modal-title">Confirm deletion</h2>
      {children}
      <button onClick={onClose}>Cancel</button>
    </div>
  );
}
```

Alternatively, use the native `<dialog>` element which handles focus trapping automatically in modern browsers.

```tsx
// Native dialog element — recommended for new projects
<dialog ref={dialogRef} aria-labelledby="dialog-title">
  <h2 id="dialog-title">Confirm deletion</h2>
  <p>This action cannot be undone.</p>
  <button onClick={() => dialogRef.current?.close()}>Cancel</button>
  <button onClick={handleConfirm}>Delete</button>
</dialog>
```

---

## Keyboard Navigation

All interactive elements must be operable with a keyboard. Test with Tab, Shift+Tab, Enter, Space, Escape, and arrow keys.

```tsx
// Keyboard interaction patterns by role:
// button — activated by Enter and Space
// link — activated by Enter
// checkbox — toggled by Space
// radio — navigated by arrow keys within group
// dialog — closed by Escape
// menu — navigated by arrow keys, closed by Escape

// Custom interactive component must replicate native keyboard behavior
function Disclosure({ label, children }: DisclosureProps) {
  const [open, setOpen] = useState(false);

  return (
    <div>
      <button
        type="button"
        aria-expanded={open}
        aria-controls="disclosure-content"
        onClick={() => setOpen(o => !o)}
      >
        {label}
        <span aria-hidden="true">{open ? '▲' : '▼'}</span>
      </button>
      <div id="disclosure-content" hidden={!open}>
        {children}
      </div>
    </div>
  );
}
```

DON'T: Add `onClick` to non-interactive elements (`div`, `span`, `p`) without also adding `role`, `tabIndex`, and keyboard event handlers (`onKeyDown`).

---

## Color Contrast

- Normal text (< 18pt / < 14pt bold): minimum contrast ratio 4.5:1
- Large text (≥ 18pt / ≥ 14pt bold): minimum contrast ratio 3:1
- UI components and graphical objects: minimum 3:1 against adjacent colors

Tools: WebAIM Contrast Checker, browser DevTools accessibility panel, axe browser extension.

```tsx
// BAD — light gray text on white background fails contrast
<p style={{ color: '#aaaaaa' }}>This text is not readable</p>

// GOOD
<p style={{ color: '#595959' }}>This text passes WCAG AA</p>
```

DON'T: Rely on color alone to convey information (error states, required fields, status indicators).

```tsx
// BAD — red color is the only indicator of error
<input style={{ border: errors.email ? '1px solid red' : '1px solid gray' }} />

// GOOD — color + icon + text
{errors.email && (
  <p role="alert">
    <ErrorIcon aria-hidden="true" />
    {errors.email.message}
  </p>
)}
<input
  aria-invalid={!!errors.email}
  style={{ border: errors.email ? '2px solid #d32f2f' : '1px solid #757575' }}
/>
```

---

## Screen Reader Testing

Always verify accessibility with a real screen reader before release.

**macOS — VoiceOver:**
- Enable: `Cmd + F5` (or System Settings → Accessibility → VoiceOver)
- Navigate: `Tab` for interactive elements, `VO + arrows` for all elements
- `VO` key is `Ctrl + Option` by default
- Use the Web Rotor: `VO + U` to browse headings, links, landmarks

**Windows — NVDA (free):**
- Download: nvaccess.org
- Navigate: `Tab` for interactive, `H` for headings, `L` for lists, `F` for form fields
- Browse mode vs focus mode: `NVDA + Space` to toggle

Testing checklist:
- Page has a logical reading order
- All images have appropriate alt text
- Form inputs are announced with their label
- Error messages are announced when they appear
- Modal focus is trapped when open
- Dynamic content changes are announced

---

## Role, Name, Value Triangle

Every interactive component must expose three pieces of information to assistive technology:

1. **Role** — what type of thing is it? (button, checkbox, textbox)
2. **Name** — what is it called? (visible label or aria-label)
3. **Value** — what is its current state? (checked, expanded, selected, current value)

```tsx
// Custom toggle button — all three properties exposed
<button
  type="button"
  aria-pressed={isActive}           // value: current pressed state
  aria-label="Toggle dark mode"    // name: what it does
  // role="button" is implicit      // role: from native element
  onClick={() => setIsActive(a => !a)}
>
  <MoonIcon aria-hidden="true" />
</button>

// Custom select/combobox — must expose role, label, and selected value
<div
  role="combobox"
  aria-haspopup="listbox"
  aria-expanded={isOpen}
  aria-labelledby="country-label"
  aria-activedescendant={selectedOptionId}
  tabIndex={0}
>
  {selectedOption?.label ?? 'Select a country'}
</div>
```

---

## Live Regions

Use `aria-live` to announce dynamic content changes (toasts, status messages, search result counts) to screen readers.

```tsx
// Polite — announces after current speech finishes (use for most notifications)
<div aria-live="polite" aria-atomic="true">
  {statusMessage}
</div>

// Assertive — interrupts current speech (use only for critical errors)
<div aria-live="assertive" role="alert">
  {criticalError}
</div>

// Search results count — update after debounce
function SearchResults({ count, query }: SearchResultsProps) {
  return (
    <>
      <div aria-live="polite" className="sr-only">
        {count} results for "{query}"
      </div>
      {/* visible results */}
    </>
  );
}

// Toast notification component
function Toast({ message, type }: ToastProps) {
  return (
    <div
      role="status"
      aria-live={type === 'error' ? 'assertive' : 'polite'}
      aria-atomic="true"
      className={`toast toast--${type}`}
    >
      {message}
    </div>
  );
}
```

DON'T: Overuse `aria-live="assertive"` — it interrupts the user's current context and causes frustration.

---

## Modal / Dialog Accessibility

```tsx
// Full accessible dialog pattern
function ConfirmDialog({
  isOpen,
  title,
  description,
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  const titleId = useId();
  const descId = useId();
  const cancelRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (isOpen) {
      cancelRef.current?.focus(); // focus cancel button by default (safer default action)
    }
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div className="overlay" onClick={onCancel}>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={descId}
        className="dialog"
        onClick={e => e.stopPropagation()} // prevent overlay click closing via bubbling
      >
        <h2 id={titleId}>{title}</h2>
        <p id={descId}>{description}</p>
        <div className="dialog__actions">
          <button ref={cancelRef} type="button" onClick={onCancel}>
            Cancel
          </button>
          <button type="button" onClick={onConfirm}>
            Confirm
          </button>
        </div>
      </div>
    </div>
  );
}
```

Required for dialogs:
- `role="dialog"` on the dialog container
- `aria-modal="true"` to tell screen readers content outside is inert
- `aria-labelledby` pointing to the dialog title
- `aria-describedby` pointing to the dialog description
- Focus moves into the dialog when it opens
- Focus returns to the triggering element when the dialog closes
- `Escape` key closes the dialog

---

## ESLint Plugin

```bash
npm install -D eslint-plugin-jsx-a11y
```

```js
// eslint.config.js
import jsxA11y from 'eslint-plugin-jsx-a11y';

export default [
  {
    plugins: { 'jsx-a11y': jsxA11y },
    rules: {
      ...jsxA11y.configs.recommended.rules,
      // Upgrade warnings to errors for critical rules
      'jsx-a11y/alt-text': 'error',
      'jsx-a11y/anchor-is-valid': 'error',
      'jsx-a11y/aria-props': 'error',
      'jsx-a11y/aria-role': 'error',
      'jsx-a11y/interactive-supports-focus': 'error',
      'jsx-a11y/label-has-associated-control': 'error',
      'jsx-a11y/no-noninteractive-element-interactions': 'warn',
      'jsx-a11y/no-static-element-interactions': 'error',
    },
  },
];
```

---

## Automated Accessibility Testing with axe-core

```bash
npm install -D @axe-core/react vitest-axe
```

```tsx
// src/test/setup.ts — extend matchers
import 'vitest-axe/extend-expect';

// In a test
import { render } from '../test/utils';
import { axe } from 'vitest-axe';

it('should have no accessibility violations', async () => {
  const { container } = render(<LoginForm />);
  const results = await axe(container);
  expect(results).toHaveNoViolations();
});
```

Automated testing catches approximately 30–40% of accessibility issues. It does not replace manual testing with a screen reader and keyboard navigation.

```tsx
// Development-only axe overlay (shows violations in browser console)
// main.tsx
if (import.meta.env.DEV) {
  import('@axe-core/react').then(({ default: axe }) => {
    axe(React, ReactDOM, 1000);
  });
}
```

---

## Screen-Reader-Only Utility Class

Visually hide content that should only be available to screen readers (status messages, skip links, supplementary labels).

```css
/* globals.css */
.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border-width: 0;
}
```

```tsx
// Skip link — allows keyboard users to bypass navigation
function SkipLink() {
  return (
    <a href="#main-content" className="skip-link">
      Skip to main content
    </a>
  );
}

// Place at very top of document
<body>
  <SkipLink />
  <header>...</header>
  <main id="main-content">...</main>
</body>
```

```css
/* Skip link — visible only on focus */
.skip-link {
  position: absolute;
  top: -100%;
  left: 0;
  z-index: 9999;
  padding: 8px 16px;
  background: #000;
  color: #fff;
}
.skip-link:focus {
  top: 0;
}
```

DO: Add a skip link to every page — it is one of the most impactful accessibility improvements for keyboard users.
