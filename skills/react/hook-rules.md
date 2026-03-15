# React Hooks — Rules and Patterns

This document defines how hooks must be written and used in React projects. Following these rules prevents subtle bugs, improves testability, and keeps component logic composable.

---

## Rules of Hooks

These are enforced by the `react-hooks/rules-of-hooks` ESLint rule and must never be violated.

**1. Only call hooks at the top level.**

Never call hooks inside loops, conditions, or nested functions. React relies on the call order of hooks being identical on every render.

```tsx
// WRONG — conditional hook call
function UserProfile({ userId }: { userId: string | null }) {
  if (!userId) return <p>No user</p>; // early return before hooks

  const user = useUser(userId); // Hook called after conditional return — ERROR
  return <div>{user.name}</div>;
}

// CORRECT — hook called unconditionally at top level
function UserProfile({ userId }: { userId: string | null }) {
  const user = useUser(userId ?? ''); // always called, handle null inside hook

  if (!userId) return <p>No user</p>;
  if (!user) return <p>Loading...</p>;
  return <div>{user.name}</div>;
}
```

```tsx
// WRONG — hook inside a loop
function ItemList({ ids }: { ids: string[] }) {
  return ids.map((id) => {
    const item = useItem(id); // NEVER call hooks in loops
    return <div key={id}>{item.name}</div>;
  });
}

// CORRECT — move the item into a separate component
function ItemList({ ids }: { ids: string[] }) {
  return ids.map((id) => <Item key={id} id={id} />);
}

function Item({ id }: { id: string }) {
  const item = useItem(id); // hook at top level of component
  return <div>{item?.name}</div>;
}
```

**2. Only call hooks from React functions.**

Call hooks only from React function components or custom hooks — never from plain JavaScript functions, class methods, or event handlers.

---

## Custom Hook Naming and File Conventions

- Always prefix custom hook names with `use`: `useAuth`, `useUsers`, `useLocalStorage`.
- File name must match the hook name: `useAuth.ts`, `useLocalStorage.ts`.
- Use `.ts` extension unless the hook returns JSX, in which case use `.tsx`.

```ts
// CORRECT file names
useAuth.ts
useDebounce.ts
useLocalStorage.ts
useClickOutside.ts   // returns nothing, just wires up an event listener

// CORRECT — .tsx only when JSX is returned
useRenderTooltip.tsx  // returns <Tooltip> element
```

---

## Single Responsibility

Each custom hook should do one thing. If a hook is managing loading state, error state, fetching data, AND updating the URL — it is doing too much.

```ts
// WRONG — too many responsibilities in one hook
function useUserPage(userId: string) {
  const [user, setUser] = useState<User | null>(null);
  const [posts, setPosts] = useState<Post[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');

  useEffect(() => { /* fetch user */ }, [userId]);
  useEffect(() => { /* fetch posts */ }, [userId]);

  const filteredPosts = posts.filter(p => p.title.includes(searchQuery));
  // ...
}

// CORRECT — composed from focused hooks
function UserPage({ userId }: { userId: string }) {
  const { user, isLoading: userLoading } = useUser(userId);
  const { posts, isLoading: postsLoading } = useUserPosts(userId);
  const [searchQuery, setSearchQuery] = useState('');
  const filteredPosts = useFilteredPosts(posts, searchQuery);
  // ...
}
```

---

## Standard Custom Hook Patterns

### `useLocalStorage` — Sync state with localStorage

```ts
// hooks/useLocalStorage.ts
import { useState, useCallback } from 'react';

function useLocalStorage<T>(key: string, initialValue: T): [T, (value: T | ((prev: T) => T)) => void, () => void] {
  const [storedValue, setStoredValue] = useState<T>(() => {
    try {
      const item = window.localStorage.getItem(key);
      return item ? (JSON.parse(item) as T) : initialValue;
    } catch {
      return initialValue;
    }
  });

  const setValue = useCallback(
    (value: T | ((prev: T) => T)) => {
      try {
        const valueToStore = value instanceof Function ? value(storedValue) : value;
        setStoredValue(valueToStore);
        window.localStorage.setItem(key, JSON.stringify(valueToStore));
      } catch (error) {
        console.error(`useLocalStorage: failed to set key "${key}"`, error);
      }
    },
    [key, storedValue],
  );

  const removeValue = useCallback(() => {
    setStoredValue(initialValue);
    window.localStorage.removeItem(key);
  }, [key, initialValue]);

  return [storedValue, setValue, removeValue];
}

export { useLocalStorage };
```

### `useDebounce` — Debounce a rapidly changing value

```ts
// hooks/useDebounce.ts
import { useState, useEffect } from 'react';

function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay);
    return () => clearTimeout(timer); // cleanup on every value/delay change
  }, [value, delay]);

  return debouncedValue;
}

export { useDebounce };

// Usage
function SearchInput() {
  const [query, setQuery] = useState('');
  const debouncedQuery = useDebounce(query, 300);

  useEffect(() => {
    if (debouncedQuery) performSearch(debouncedQuery);
  }, [debouncedQuery]);
}
```

### `useAsync` — Async operation with loading/error/data state

```ts
// hooks/useAsync.ts
import { useState, useCallback, useRef } from 'react';

interface AsyncState<T> {
  data: T | null;
  error: Error | null;
  isLoading: boolean;
}

function useAsync<T, Args extends unknown[]>(
  asyncFn: (...args: Args) => Promise<T>,
): AsyncState<T> & { execute: (...args: Args) => Promise<void> } {
  const [state, setState] = useState<AsyncState<T>>({
    data: null,
    error: null,
    isLoading: false,
  });

  const isMountedRef = useRef(true);

  const execute = useCallback(
    async (...args: Args): Promise<void> => {
      setState({ data: null, error: null, isLoading: true });
      try {
        const data = await asyncFn(...args);
        if (isMountedRef.current) setState({ data, error: null, isLoading: false });
      } catch (error) {
        if (isMountedRef.current) {
          setState({ data: null, error: error instanceof Error ? error : new Error(String(error)), isLoading: false });
        }
      }
    },
    [asyncFn],
  );

  return { ...state, execute };
}

export { useAsync };
```

### `usePrevious` — Get the previous value of a prop or state

```ts
// hooks/usePrevious.ts
import { useRef, useEffect } from 'react';

function usePrevious<T>(value: T): T | undefined {
  const ref = useRef<T | undefined>(undefined);

  useEffect(() => {
    ref.current = value;
  }, [value]); // runs after render, so ref still holds previous value during render

  return ref.current;
}

export { usePrevious };
```

### `useClickOutside` — Detect clicks outside a ref'd element

```ts
// hooks/useClickOutside.ts
import { useEffect, RefObject } from 'react';

function useClickOutside<T extends HTMLElement>(
  ref: RefObject<T>,
  handler: (event: MouseEvent | TouchEvent) => void,
): void {
  useEffect(() => {
    const listener = (event: MouseEvent | TouchEvent) => {
      if (!ref.current || ref.current.contains(event.target as Node)) return;
      handler(event);
    };

    document.addEventListener('mousedown', listener);
    document.addEventListener('touchstart', listener);

    return () => {
      document.removeEventListener('mousedown', listener);
      document.removeEventListener('touchstart', listener);
    };
  }, [ref, handler]); // handler should be stable (wrapped in useCallback by the caller)
}

export { useClickOutside };
```

### `useMediaQuery` — Responsive breakpoints

```ts
// hooks/useMediaQuery.ts
import { useState, useEffect } from 'react';

function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState<boolean>(() => {
    if (typeof window === 'undefined') return false;
    return window.matchMedia(query).matches;
  });

  useEffect(() => {
    const mediaQuery = window.matchMedia(query);
    const handler = (event: MediaQueryListEvent) => setMatches(event.matches);

    mediaQuery.addEventListener('change', handler);
    return () => mediaQuery.removeEventListener('change', handler);
  }, [query]);

  return matches;
}

// Convenience wrappers
export function useIsMobile(): boolean {
  return useMediaQuery('(max-width: 767px)');
}

export function useIsTablet(): boolean {
  return useMediaQuery('(min-width: 768px) and (max-width: 1023px)');
}

export { useMediaQuery };
```

### `useIntersectionObserver` — Infinite scroll and lazy loading

```ts
// hooks/useIntersectionObserver.ts
import { useEffect, useRef, useState } from 'react';

interface IntersectionObserverOptions {
  threshold?: number;
  rootMargin?: string;
  root?: Element | null;
}

function useIntersectionObserver<T extends HTMLElement>(
  options: IntersectionObserverOptions = {},
): [React.RefCallback<T>, boolean] {
  const { threshold = 0, rootMargin = '0px', root = null } = options;
  const [isIntersecting, setIsIntersecting] = useState(false);
  const observerRef = useRef<IntersectionObserver | null>(null);

  const ref: React.RefCallback<T> = (node) => {
    if (observerRef.current) observerRef.current.disconnect();

    if (node) {
      observerRef.current = new IntersectionObserver(
        ([entry]) => setIsIntersecting(entry.isIntersecting),
        { threshold, rootMargin, root },
      );
      observerRef.current.observe(node);
    }
  };

  return [ref, isIntersecting];
}

export { useIntersectionObserver };

// Usage for infinite scroll
function PostList() {
  const { fetchNextPage, hasNextPage } = useInfiniteQuery(...);
  const [sentinelRef, isVisible] = useIntersectionObserver<HTMLDivElement>({ threshold: 0.5 });

  useEffect(() => {
    if (isVisible && hasNextPage) fetchNextPage();
  }, [isVisible, hasNextPage, fetchNextPage]);

  return (
    <div>
      {/* render posts */}
      <div ref={sentinelRef} style={{ height: 1 }} />
    </div>
  );
}
```

---

## When to Extract a Custom Hook

Extract logic into a custom hook when:

1. **Used in 2 or more components** — deduplication of state logic.
2. **Logic is complex** — a useEffect with multiple side effects, cleanup, and conditions is hard to read inline.
3. **The logic has no visual output** — pure behavior (timers, subscriptions, localStorage sync) belongs in hooks.
4. **The hook can be independently tested** — hooks with clear inputs/outputs are easier to unit test.

```tsx
// Signal to extract: 10+ lines of state/effect logic in a component
function UserSearch() {
  // These 15 lines should become a custom hook
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<User[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const debouncedQuery = useDebounce(query, 300);

  useEffect(() => {
    if (!debouncedQuery) return;
    setIsLoading(true);
    searchUsers(debouncedQuery)
      .then(setResults)
      .catch(setError)
      .finally(() => setIsLoading(false));
  }, [debouncedQuery]);

  // Extract to: useUserSearch(query) → { results, isLoading, error }
}
```

---

## `useEffect` Rules

**Always specify the dependency array.** Missing dependencies cause stale closures. Extra dependencies cause unnecessary re-runs. ESLint's `react-hooks/exhaustive-deps` rule catches both.

```ts
// WRONG — no dependency array (runs after every render)
useEffect(() => {
  fetchData();
});

// WRONG — empty array but uses fetchData (stale closure)
useEffect(() => {
  fetchData(); // fetchData might close over stale state
}, []);

// CORRECT — all dependencies listed
useEffect(() => {
  fetchData(userId);
}, [userId, fetchData]); // fetchData should be stable (defined outside or wrapped in useCallback)
```

**Never lie about dependencies.** If a value is used inside useEffect, it belongs in the dependency array. If adding it causes an infinite loop, the real fix is to stabilize the value (useCallback, useMemo, moving it outside the component), not to omit it from the array.

---

## `useEffect` Cleanup

Always return a cleanup function for subscriptions, timers, and event listeners.

```ts
// Timer cleanup
useEffect(() => {
  const timerId = setInterval(() => tick(), 1000);
  return () => clearInterval(timerId);
}, []);

// Event listener cleanup
useEffect(() => {
  const handler = () => setIsOnline(navigator.onLine);
  window.addEventListener('online', handler);
  window.addEventListener('offline', handler);
  return () => {
    window.removeEventListener('online', handler);
    window.removeEventListener('offline', handler);
  };
}, []);

// Async fetch with abort controller (prevents state updates on unmounted component)
useEffect(() => {
  const controller = new AbortController();

  async function fetchData() {
    try {
      const data = await fetch(`/api/users/${userId}`, { signal: controller.signal });
      setUser(await data.json());
    } catch (error) {
      if (error instanceof Error && error.name !== 'AbortError') setError(error);
    }
  }

  fetchData();
  return () => controller.abort();
}, [userId]);
```

---

## Avoid `useEffect` for Derived State

If a value can be computed from existing state or props during render, do not use useEffect + setState to compute it. This causes an extra render cycle.

```ts
// WRONG — useEffect to compute derived state
const [firstName, setFirstName] = useState('Jane');
const [lastName, setLastName] = useState('Doe');
const [fullName, setFullName] = useState('');

useEffect(() => {
  setFullName(`${firstName} ${lastName}`); // extra render every time
}, [firstName, lastName]);

// CORRECT — compute during render (no extra render)
const [firstName, setFirstName] = useState('Jane');
const [lastName, setLastName] = useState('Doe');
const fullName = `${firstName} ${lastName}`; // derived inline
```

---

## `useMemo` vs `useCallback`

Use these only when there is a measurable performance problem. Premature memoization adds complexity without benefit.

**`useMemo`** memoizes a computed value:

```ts
// Use when: computation is expensive AND inputs change infrequently
const sortedUsers = useMemo(
  () => [...users].sort((a, b) => a.name.localeCompare(b.name)),
  [users], // only re-sort when users array changes
);

// NOT needed for simple computations
const upperName = useMemo(() => name.toUpperCase(), [name]); // WRONG — trivial
const upperName = name.toUpperCase(); // CORRECT
```

**`useCallback`** memoizes a function reference:

```ts
// Use when: passing callbacks to memoized child components (React.memo)
// or when a function is a dependency of useEffect/useMemo
const handleDelete = useCallback(
  (userId: string) => {
    deleteUser(userId);
  },
  [deleteUser],
);

// Use in useEffect dependencies to avoid infinite loops
const fetchData = useCallback(async () => {
  const data = await getUsers();
  setUsers(data);
}, []); // no deps — function never changes

useEffect(() => {
  fetchData();
}, [fetchData]); // safe because fetchData is stable
```

---

## `useReducer` for Complex State

Use `useReducer` when:
- Multiple state values that update together
- Next state depends on the previous state in complex ways
- State transitions have multiple named actions

```ts
type CartAction =
  | { type: 'ADD_ITEM'; payload: CartItem }
  | { type: 'REMOVE_ITEM'; payload: string }
  | { type: 'UPDATE_QUANTITY'; payload: { id: string; quantity: number } }
  | { type: 'CLEAR_CART' };

interface CartState {
  items: CartItem[];
  total: number;
}

function cartReducer(state: CartState, action: CartAction): CartState {
  switch (action.type) {
    case 'ADD_ITEM':
      return { ...state, items: [...state.items, action.payload] };
    case 'REMOVE_ITEM':
      return { ...state, items: state.items.filter((i) => i.id !== action.payload) };
    case 'CLEAR_CART':
      return { items: [], total: 0 };
    default:
      return state;
  }
}

function Cart() {
  const [state, dispatch] = useReducer(cartReducer, { items: [], total: 0 });

  const handleRemove = (id: string) => dispatch({ type: 'REMOVE_ITEM', payload: id });
}
```

---

## `useContext` Without Performance Issues

Every component that calls `useContext` re-renders when the context value changes. Split contexts by update frequency.

```tsx
// WRONG — one context with everything
const AppContext = createContext<{
  user: User;
  theme: Theme;
  notifications: Notification[];
  updateUser: (u: User) => void;
}>(null!);
// Any update to ANY of these causes ALL consumers to re-render

// CORRECT — split by concern and update frequency
const UserContext = createContext<User | null>(null); // changes rarely
const ThemeContext = createContext<Theme>('light');    // changes on toggle
const NotificationsContext = createContext<Notification[]>([]); // changes often
```

---

## `useId` for Accessibility

Use `useId` to generate stable, unique IDs for form elements and their labels. Never hardcode IDs in reusable components.

```tsx
// WRONG — hardcoded ID breaks when component renders multiple times
function Input({ label }: { label: string }) {
  return (
    <>
      <label htmlFor="my-input">{label}</label>
      <input id="my-input" />
    </>
  );
}

// CORRECT — stable unique ID per instance
function Input({ label }: { label: string }) {
  const id = useId();
  return (
    <>
      <label htmlFor={id}>{label}</label>
      <input id={id} />
    </>
  );
}
```
