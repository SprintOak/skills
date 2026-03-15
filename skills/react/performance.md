# React Performance

## React 18 Automatic Batching

React 18 automatically batches all state updates — including those inside `setTimeout`, `Promise` callbacks, and native event handlers — into a single re-render.

```tsx
// React 18: both setters cause only ONE re-render
setTimeout(() => {
  setCount(c => c + 1);
  setFlag(f => !f);
  // renders once, not twice
}, 1000);
```

DON'T: Wrap state updates in `unstable_batchedUpdates` — it is no longer necessary in React 18.
DO: Be aware that `flushSync` will opt out of batching when you need a synchronous DOM update (rare).

---

## useMemo

Use `useMemo` when:
1. The computation is genuinely expensive (sorting, filtering, transforming large arrays)
2. You need referential stability for an object/array that is a `useEffect` dependency

```tsx
// GOOD — expensive computation
const sortedItems = useMemo(
  () => [...items].sort((a, b) => a.name.localeCompare(b.name)),
  [items]
);

// GOOD — stable reference for useEffect
const config = useMemo(
  () => ({ endpoint: apiUrl, headers: { Authorization: `Bearer ${token}` } }),
  [apiUrl, token]
);
useEffect(() => {
  fetchData(config);
}, [config]);

// BAD — trivial computation, memo overhead exceeds benefit
const fullName = useMemo(() => `${first} ${last}`, [first, last]);
// Just write: const fullName = `${first} ${last}`;
```

DON'T: Memoize everything by default. Profile first; add `useMemo` only where measurements show a benefit.

---

## useCallback

Use `useCallback` when:
1. Passing a callback to a memoized child component (`React.memo`) to prevent unnecessary re-renders
2. A function is a `useEffect` dependency and you want to avoid infinite loops

```tsx
// GOOD — stable reference for memoized child
const handleDelete = useCallback(
  (id: string) => {
    deleteItem(id);
  },
  [deleteItem]
);

return <ItemList onDelete={handleDelete} />;

// GOOD — stable reference as useEffect dep
const fetchUser = useCallback(async () => {
  const data = await api.getUser(userId);
  setUser(data);
}, [userId]);

useEffect(() => {
  fetchUser();
}, [fetchUser]);

// BAD — child is not memoized, useCallback adds overhead with no benefit
function Parent() {
  const onClick = useCallback(() => console.log('click'), []); // pointless
  return <div onClick={onClick} />;
}
```

---

## React.memo

Use `React.memo` on pure functional components that:
- Receive the same props frequently while a parent re-renders for unrelated reasons
- Are expensive to render

```tsx
// GOOD — list item that re-renders with every parent keystroke otherwise
const ProductCard = React.memo(function ProductCard({ product, onAddToCart }: Props) {
  return (
    <div>
      <h3>{product.name}</h3>
      <p>{product.price}</p>
      <button onClick={() => onAddToCart(product.id)}>Add to cart</button>
    </div>
  );
});

// onAddToCart must be wrapped in useCallback in the parent, otherwise memo is useless
function ProductList({ products }: { products: Product[] }) {
  const handleAddToCart = useCallback((id: string) => {
    cartStore.add(id);
  }, []);

  return (
    <ul>
      {products.map(p => (
        <ProductCard key={p.id} product={p} onAddToCart={handleAddToCart} />
      ))}
    </ul>
  );
}
```

DON'T: Use `React.memo` on every component. It adds overhead and complexity. Profile first.
DON'T: Use `React.memo` when the component almost always receives different props.

---

## React DevTools Profiler

The React DevTools Profiler records component render times and identifies unnecessary renders.

Steps to identify bottlenecks:
1. Open React DevTools → Profiler tab
2. Click "Record", interact with the slow UI, stop recording
3. Use the flamegraph to identify components that render too often or take too long
4. Click a bar to see why the component rendered ("Props changed", "State changed", etc.)
5. Use the "Ranked" chart to find the slowest components by total render time

Look for:
- Components rendering when their props did not change (candidate for `React.memo`)
- Renders cascading deeply from a single state update (consider splitting state or context)

---

## Code Splitting with React.lazy + Suspense

Split large components or routes so they are loaded only when needed.

```tsx
import { lazy, Suspense } from 'react';

// Lazy import — bundle is fetched only when this component first renders
const HeavyChart = lazy(() => import('./components/HeavyChart'));

function Dashboard() {
  return (
    <Suspense fallback={<div>Loading chart…</div>}>
      <HeavyChart data={data} />
    </Suspense>
  );
}
```

DON'T: Use `lazy` inside a component body — the import must be at module level.
DON'T: Lazy-load small, frequently-visible components — the loading flash hurts UX.

---

## Route-Level Code Splitting

Split at the route level for the best initial bundle size reduction.

```tsx
// router.tsx
import { createBrowserRouter } from 'react-router-dom';
import { lazy, Suspense } from 'react';

const DashboardPage = lazy(() => import('./pages/DashboardPage'));
const SettingsPage = lazy(() => import('./pages/SettingsPage'));
const ReportsPage = lazy(() => import('./pages/ReportsPage'));

function PageLoader() {
  return <div aria-label="Loading page" role="status">Loading…</div>;
}

export const router = createBrowserRouter([
  {
    path: '/',
    element: <Layout />,
    children: [
      {
        path: 'dashboard',
        element: (
          <Suspense fallback={<PageLoader />}>
            <DashboardPage />
          </Suspense>
        ),
      },
      {
        path: 'settings',
        element: (
          <Suspense fallback={<PageLoader />}>
            <SettingsPage />
          </Suspense>
        ),
      },
    ],
  },
]);
```

---

## Image Optimization

```tsx
// GOOD — native lazy loading, explicit dimensions to prevent layout shift
<img
  src="/images/hero.webp"
  alt="Team collaborating at a whiteboard"
  width={1200}
  height={600}
  loading="lazy"           // browser defers off-screen images
  decoding="async"         // don't block main thread for decode
/>

// Above-the-fold critical image — don't lazy load
<img
  src="/images/logo.webp"
  alt="Acme Corp"
  width={160}
  height={40}
  loading="eager"
  fetchPriority="high"
/>
```

DO: Use WebP format with JPEG/PNG fallback via `<picture>`.
DO: Always specify `width` and `height` to prevent Cumulative Layout Shift (CLS).
DON'T: Lazy-load hero images above the fold — they will appear later and hurt LCP.

```tsx
// Responsive images with srcset
<img
  srcSet="/img/hero-400.webp 400w, /img/hero-800.webp 800w, /img/hero-1200.webp 1200w"
  sizes="(max-width: 600px) 400px, (max-width: 900px) 800px, 1200px"
  src="/img/hero-1200.webp"
  alt="Hero image"
  loading="lazy"
/>
```

---

## List Virtualization

Render only the visible portion of long lists (hundreds to thousands of items).

```tsx
// react-window for fixed-size lists
import { FixedSizeList } from 'react-window';

interface RowProps {
  index: number;
  style: React.CSSProperties;
  data: User[];
}

function Row({ index, style, data }: RowProps) {
  const user = data[index];
  return (
    <div style={style} key={user.id}>
      <UserRow user={user} />
    </div>
  );
}

function UserList({ users }: { users: User[] }) {
  return (
    <FixedSizeList
      height={600}
      itemCount={users.length}
      itemSize={72}
      width="100%"
      itemData={users}
    >
      {Row}
    </FixedSizeList>
  );
}
```

For variable-height items, use `react-window`'s `VariableSizeList` or TanStack Virtual (`@tanstack/react-virtual`).

DO: Virtualize any list with 100+ items that requires scrolling.
DON'T: Virtualize small static lists — the API overhead is not worth it.

---

## Avoid Creating Objects and Arrays in JSX

New object/array literals created during render have a new reference every time. This breaks memoization and triggers unnecessary effects.

```tsx
// BAD — new object reference every render
<Chart options={{ responsive: true, animations: false }} />

// GOOD — stable reference (defined outside component or memoized)
const CHART_OPTIONS = { responsive: true, animations: false };
<Chart options={CHART_OPTIONS} />

// Or memoize if it depends on props/state
const chartOptions = useMemo(
  () => ({ responsive: true, color: theme.primary }),
  [theme.primary]
);
<Chart options={chartOptions} />

// BAD — new array every render
<Select options={['A', 'B', 'C']} />

// GOOD
const OPTIONS = ['A', 'B', 'C'];
<Select options={OPTIONS} />
```

---

## Avoid Anonymous Functions in Dependency Arrays

```tsx
// BAD — new function reference every render, triggers effect every render
useEffect(() => {
  fetchData(() => console.log('done'));
}, [() => console.log('done')]); // ESLint will warn about this

// GOOD — stable reference
const handleDone = useCallback(() => console.log('done'), []);
useEffect(() => {
  fetchData(handleDone);
}, [handleDone]);
```

---

## Key Prop for List Stability

Always use a stable, unique identifier as the `key` prop. Never use the array index unless the list is static and never reordered.

```tsx
// BAD — index as key causes state bugs when list reorders or splices
{items.map((item, index) => <Item key={index} item={item} />)}

// GOOD — stable unique id
{items.map(item => <Item key={item.id} item={item} />)}
```

---

## CSS Transitions Over JS Animations

Use CSS transitions and animations whenever possible. They run on the compositor thread and don't block the main thread.

```tsx
// GOOD — CSS handles animation, React just toggles the class
<div className={`panel ${isOpen ? 'panel--open' : ''}`}>
  {children}
</div>
```

```css
.panel {
  transform: translateX(-100%);
  transition: transform 300ms ease-in-out;
}
.panel--open {
  transform: translateX(0);
}
```

DON'T: Animate `width`, `height`, `top`, `left`, or `margin` — these trigger layout recalculation. Animate `transform` and `opacity` instead.

---

## Avoid Layout Thrash

Layout thrash occurs when JavaScript alternates between reading and writing DOM properties, forcing multiple reflows.

```ts
// BAD — read/write interleaved causes multiple reflows
elements.forEach(el => {
  const height = el.offsetHeight; // READ — forces layout
  el.style.height = `${height * 2}px`; // WRITE — invalidates layout
});

// GOOD — batch reads, then batch writes
const heights = elements.map(el => el.offsetHeight); // all READs
elements.forEach((el, i) => {
  el.style.height = `${heights[i] * 2}px`; // all WRITEs
});
```

---

## Production Builds

DO: Always serve the production build to end users.
DON'T: Deploy development builds — they include React's warning infrastructure and are 3–10x slower.

```bash
# Build for production
npm run build

# Preview the production build locally
npm run preview
```

Check `process.env.NODE_ENV` is `"production"` in the build output.

---

## Bundle Analysis

```bash
npm install -D rollup-plugin-visualizer
```

```ts
// vite.config.ts
import { visualizer } from 'rollup-plugin-visualizer';

export default defineConfig({
  plugins: [
    react(),
    visualizer({
      filename: 'dist/stats.html',
      open: true,
      gzipSize: true,
      brotliSize: true,
    }),
  ],
});
```

Run `npm run build` and open `dist/stats.html`. Look for:
- Unexpectedly large dependencies (moment.js, lodash — use date-fns or lodash-es instead)
- Duplicated packages at different versions
- Test utilities or dev dependencies bundled into production

---

## Web Vitals Targets

| Metric | Good | Needs Improvement | Poor |
|--------|------|-------------------|------|
| LCP (Largest Contentful Paint) | ≤ 2.5s | 2.5–4s | > 4s |
| INP (Interaction to Next Paint) | ≤ 200ms | 200–500ms | > 500ms |
| CLS (Cumulative Layout Shift) | ≤ 0.1 | 0.1–0.25 | > 0.25 |

```tsx
// Measure Web Vitals in your app
import { onCLS, onINP, onLCP } from 'web-vitals';

function sendToAnalytics({ name, value, id }: Metric) {
  analytics.track('web_vital', { name, value, id });
}

onCLS(sendToAnalytics);
onINP(sendToAnalytics);
onLCP(sendToAnalytics);
```

Common LCP fixes: preload the hero image, use `fetchPriority="high"`, avoid lazy-loading above-fold content.
Common CLS fixes: reserve space for images (width/height attrs), avoid inserting content above existing content, use `font-display: optional`.

---

## Suspense for Data Fetching with TanStack Query

Use `suspense: true` to let TanStack Query integrate with React Suspense, simplifying loading state handling.

```tsx
// Enable per-query
const { data } = useSuspenseQuery({
  queryKey: ['user', userId],
  queryFn: () => api.getUser(userId),
});

// Wrap the consuming component in Suspense + ErrorBoundary
function UserProfilePage() {
  return (
    <ErrorBoundary fallback={<ErrorMessage />}>
      <Suspense fallback={<UserProfileSkeleton />}>
        <UserProfile userId={userId} />
      </Suspense>
    </ErrorBoundary>
  );
}

// Inside UserProfile — data is guaranteed to exist, no loading check needed
function UserProfile({ userId }: { userId: string }) {
  const { data: user } = useSuspenseQuery({
    queryKey: ['user', userId],
    queryFn: () => api.getUser(userId),
  });

  return <h1>{user.name}</h1>; // no user?.name needed
}
```

DO: Use `useSuspenseQuery` for a cleaner component tree without manual loading/error checks.
DON'T: Mix `useSuspenseQuery` and `useQuery` in the same Suspense boundary — it causes waterfall loading.
