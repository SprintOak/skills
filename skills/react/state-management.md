# React State Management

## State Type Classification

Every piece of state in a React application falls into one of five categories. Choosing the wrong storage mechanism for a given state type is one of the most common sources of bugs, performance issues, and unnecessary complexity.

| State Type | Where It Lives | Tool |
|---|---|---|
| Local UI state | Component | `useState` / `useReducer` |
| Server state | Remote + cache | TanStack Query |
| Global app state | In-memory store | Zustand |
| URL state | Browser URL | `useSearchParams` / route params |
| Form state | Form component | React Hook Form |

---

## Local UI State

Use `useState` for ephemeral UI state that is only relevant to one component or a small subtree. Do not hoist this state to a global store.

**DO: Use `useState` for simple toggles, input values, and UI-only state.**

```tsx
// TogglePanel.tsx
import { useState } from 'react';

export function TogglePanel({ title, children }: { title: string; children: React.ReactNode }) {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <div>
      <button onClick={() => setIsOpen(prev => !prev)}>{title}</button>
      {isOpen && <div>{children}</div>}
    </div>
  );
}
```

```tsx
// SearchInput.tsx
import { useState } from 'react';

export function SearchInput({ onSearch }: { onSearch: (query: string) => void }) {
  const [value, setValue] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSearch(value);
  };

  return (
    <form onSubmit={handleSubmit}>
      <input value={value} onChange={e => setValue(e.target.value)} placeholder="Search..." />
      <button type="submit">Search</button>
    </form>
  );
}
```

**DON'T: Move local UI state to Zustand or Context just because it is easier to access.**

```tsx
// BAD — isOpen is only used inside this component, global store is overkill
const useModalStore = create(set => ({
  isOpen: false,
  toggle: () => set(state => ({ isOpen: !state.isOpen })),
}));
```

---

## Server State — TanStack Query

All async data fetched from an API is server state. Do not duplicate it in a Zustand store or in `useState`.

TanStack Query handles caching, background refetching, deduplication, loading/error states, and stale data — building this manually with `useEffect` + `useState` is error-prone and should never be done.

**DO: Install and configure TanStack Query.**

```bash
npm install @tanstack/react-query @tanstack/react-query-devtools
```

**DO: Set up QueryClient in `main.tsx`.**

```tsx
// main.tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ReactQueryDevtools } from '@tanstack/react-query-devtools';
import { App } from './App';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5,      // 5 minutes — data is fresh for this long
      gcTime: 1000 * 60 * 10,        // 10 minutes — cache is kept for this long
      retry: 1,                       // retry failed requests once
      refetchOnWindowFocus: true,     // re-fetch when window regains focus
    },
  },
});

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <App />
      <ReactQueryDevtools initialIsOpen={false} />
    </QueryClientProvider>
  </StrictMode>,
);
```

### Query Key Factory Pattern

Define query keys as a factory object per domain. This ensures consistency and makes `invalidateQueries` easy.

```ts
// queries/userKeys.ts
export const userKeys = {
  all: ['users'] as const,
  lists: () => [...userKeys.all, 'list'] as const,
  list: (filters: UserFilters) => [...userKeys.lists(), filters] as const,
  details: () => [...userKeys.all, 'detail'] as const,
  detail: (id: string) => [...userKeys.details(), id] as const,
};
```

### useQuery — Fetching Data

```tsx
// hooks/useUsers.ts
import { useQuery } from '@tanstack/react-query';
import { userService } from '@/services/userService';
import { userKeys } from '@/queries/userKeys';
import type { UserFilters } from '@/types';

export function useUsers(filters: UserFilters) {
  return useQuery({
    queryKey: userKeys.list(filters),
    queryFn: () => userService.getUsers(filters),
    staleTime: 1000 * 60 * 2, // override default for this query
  });
}

export function useUser(id: string) {
  return useQuery({
    queryKey: userKeys.detail(id),
    queryFn: () => userService.getUser(id),
    enabled: !!id, // do not run if id is empty
  });
}
```

```tsx
// UserList.tsx
import { useUsers } from '@/hooks/useUsers';

export function UserList() {
  const { data: users, isLoading, isError, error } = useUsers({ role: 'admin' });

  if (isLoading) return <Spinner />;
  if (isError) return <ErrorMessage message={error.message} />;

  return (
    <ul>
      {users.map(user => (
        <li key={user.id}>{user.name}</li>
      ))}
    </ul>
  );
}
```

### useMutation — Modifying Data

```tsx
// hooks/useCreateUser.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { userService } from '@/services/userService';
import { userKeys } from '@/queries/userKeys';
import type { CreateUserPayload } from '@/types';

export function useCreateUser() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (payload: CreateUserPayload) => userService.createUser(payload),
    onSuccess: () => {
      // Invalidate all user list queries so they refetch
      queryClient.invalidateQueries({ queryKey: userKeys.lists() });
    },
    onError: (error) => {
      console.error('Failed to create user:', error);
    },
  });
}
```

```tsx
// CreateUserForm.tsx
import { useCreateUser } from '@/hooks/useCreateUser';

export function CreateUserForm() {
  const { mutate: createUser, isPending, isError } = useCreateUser();

  const handleSubmit = (data: CreateUserPayload) => {
    createUser(data, {
      onSuccess: () => {
        toast.success('User created');
      },
    });
  };

  return (
    <form onSubmit={handleSubmit}>
      {/* form fields */}
      <button type="submit" disabled={isPending}>
        {isPending ? 'Creating...' : 'Create User'}
      </button>
      {isError && <p>Something went wrong</p>}
    </form>
  );
}
```

### Optimistic Updates

```tsx
export function useUpdateUser() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: UpdateUserPayload }) =>
      userService.updateUser(id, data),
    onMutate: async ({ id, data }) => {
      // Cancel in-flight queries
      await queryClient.cancelQueries({ queryKey: userKeys.detail(id) });

      // Snapshot the previous value
      const previousUser = queryClient.getQueryData(userKeys.detail(id));

      // Optimistically update the cache
      queryClient.setQueryData(userKeys.detail(id), (old: User) => ({
        ...old,
        ...data,
      }));

      return { previousUser };
    },
    onError: (_err, { id }, context) => {
      // Roll back on error
      queryClient.setQueryData(userKeys.detail(id), context?.previousUser);
    },
    onSettled: (_data, _err, { id }) => {
      queryClient.invalidateQueries({ queryKey: userKeys.detail(id) });
    },
  });
}
```

**DON'T: Fetch data with `useEffect` + `useState`.**

```tsx
// BAD — manual fetch with useState/useEffect
const [users, setUsers] = useState([]);
const [loading, setLoading] = useState(true);

useEffect(() => {
  fetch('/api/users')
    .then(r => r.json())
    .then(data => {
      setUsers(data);
      setLoading(false);
    });
}, []);
```

**DON'T: Copy server data into a Zustand store.**

```ts
// BAD — storing server data in global state
const useUserStore = create(set => ({
  users: [],
  fetchUsers: async () => {
    const data = await userService.getUsers();
    set({ users: data });
  },
}));
```

---

## Global App State — Zustand

Use Zustand for client-side state that:
- Needs to be accessed by many unrelated components.
- Is not server data (not fetched from an API).
- Persists across route changes but does not need to be in the URL.

Common examples: current authenticated user, UI theme, global notification/toast queue, shopping cart.

**DO: Install Zustand.**

```bash
npm install zustand
```

### Store File Structure

One store per domain. Name files `useXxxStore.ts`. Place them in `store/`.

```
src/
  store/
    useAuthStore.ts
    useThemeStore.ts
    useNotificationStore.ts
```

### Defining State and Actions Together

```ts
// store/useAuthStore.ts
import { create } from 'zustand';
import { devtools, persist } from 'zustand/middleware';
import type { User } from '@/types';

interface AuthState {
  user: User | null;
  isAuthenticated: boolean;
  setUser: (user: User) => void;
  clearUser: () => void;
}

export const useAuthStore = create<AuthState>()(
  devtools(
    persist(
      (set) => ({
        user: null,
        isAuthenticated: false,
        setUser: (user) => set({ user, isAuthenticated: true }, false, 'auth/setUser'),
        clearUser: () => set({ user: null, isAuthenticated: false }, false, 'auth/clearUser'),
      }),
      {
        name: 'auth-storage',    // localStorage key
        partialize: (state) => ({ user: state.user, isAuthenticated: state.isAuthenticated }),
      },
    ),
    { name: 'AuthStore' },
  ),
);
```

### Selector Pattern — Avoiding Unnecessary Re-renders

**DO: Always select only the slice of state a component needs.**

```tsx
// GOOD — only re-renders when user.name changes
const userName = useAuthStore(state => state.user?.name);

// GOOD — selecting an action (actions are stable references)
const clearUser = useAuthStore(state => state.clearUser);
```

**DON'T: Subscribe to the entire store.**

```tsx
// BAD — component re-renders on every store change
const store = useAuthStore();
```

### Notifications Store Example

```ts
// store/useNotificationStore.ts
import { create } from 'zustand';
import { devtools } from 'zustand/middleware';

interface Notification {
  id: string;
  type: 'success' | 'error' | 'info' | 'warning';
  message: string;
}

interface NotificationState {
  notifications: Notification[];
  addNotification: (notification: Omit<Notification, 'id'>) => void;
  removeNotification: (id: string) => void;
}

export const useNotificationStore = create<NotificationState>()(
  devtools(
    (set) => ({
      notifications: [],
      addNotification: (notification) =>
        set(
          (state) => ({
            notifications: [
              ...state.notifications,
              { ...notification, id: crypto.randomUUID() },
            ],
          }),
          false,
          'notifications/add',
        ),
      removeNotification: (id) =>
        set(
          (state) => ({
            notifications: state.notifications.filter(n => n.id !== id),
          }),
          false,
          'notifications/remove',
        ),
    }),
    { name: 'NotificationStore' },
  ),
);
```

### Slices for Large Stores

When a store grows large, split it into slices and compose them.

```ts
// store/slices/cartSlice.ts
import type { StateCreator } from 'zustand';

export interface CartSlice {
  items: CartItem[];
  addItem: (item: CartItem) => void;
  removeItem: (id: string) => void;
  clearCart: () => void;
}

export const createCartSlice: StateCreator<CartSlice> = (set) => ({
  items: [],
  addItem: (item) =>
    set(state => ({ items: [...state.items, item] }), false, 'cart/addItem'),
  removeItem: (id) =>
    set(state => ({ items: state.items.filter(i => i.id !== id) }), false, 'cart/removeItem'),
  clearCart: () => set({ items: [] }, false, 'cart/clear'),
});

// store/useAppStore.ts
import { create } from 'zustand';
import { devtools } from 'zustand/middleware';
import { createCartSlice, type CartSlice } from './slices/cartSlice';
import { createCheckoutSlice, type CheckoutSlice } from './slices/checkoutSlice';

type AppStore = CartSlice & CheckoutSlice;

export const useAppStore = create<AppStore>()(
  devtools(
    (...args) => ({
      ...createCartSlice(...args),
      ...createCheckoutSlice(...args),
    }),
    { name: 'AppStore' },
  ),
);
```

---

## URL State

Filters, search queries, pagination, and sort order belong in the URL. This makes pages shareable and allows the browser back button to work correctly.

```tsx
// hooks/useProductFilters.ts
import { useSearchParams } from 'react-router-dom';

export function useProductFilters() {
  const [searchParams, setSearchParams] = useSearchParams();

  const filters = {
    category: searchParams.get('category') ?? '',
    page: Number(searchParams.get('page') ?? '1'),
    sortBy: (searchParams.get('sortBy') ?? 'name') as 'name' | 'price' | 'date',
  };

  const setFilter = (key: string, value: string) => {
    setSearchParams(prev => {
      const next = new URLSearchParams(prev);
      if (value) {
        next.set(key, value);
      } else {
        next.delete(key);
      }
      // Reset page when filter changes
      if (key !== 'page') next.set('page', '1');
      return next;
    });
  };

  return { filters, setFilter };
}
```

---

## Form State — React Hook Form

Use React Hook Form for all forms. Do not manage form field state with `useState`.

```tsx
// LoginForm.tsx
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

const loginSchema = z.object({
  email: z.string().email('Invalid email'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
});

type LoginFormData = z.infer<typeof loginSchema>;

export function LoginForm({ onSubmit }: { onSubmit: (data: LoginFormData) => void }) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<LoginFormData>({
    resolver: zodResolver(loginSchema),
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <div>
        <input {...register('email')} type="email" placeholder="Email" />
        {errors.email && <span>{errors.email.message}</span>}
      </div>
      <div>
        <input {...register('password')} type="password" placeholder="Password" />
        {errors.password && <span>{errors.password.message}</span>}
      </div>
      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Logging in...' : 'Login'}
      </button>
    </form>
  );
}
```

---

## When NOT to Use Global State

The majority of state in a well-structured application should be local or server state. Before reaching for Zustand, ask:

- Is this data from an API? → Use TanStack Query.
- Is this state only used in one component or a small subtree? → Use `useState`.
- Is this state that should be reflected in the URL? → Use `useSearchParams`.
- Is this form state? → Use React Hook Form.

Only use Zustand when state truly needs to be shared across unrelated parts of the tree and is not server data.

---

## State Colocation Principle

Keep state as close to where it is used as possible. This reduces complexity, improves readability, and prevents unnecessary re-renders.

1. **Local**: if only one component needs it, keep it in that component.
2. **Sibling**: if two sibling components need the same state, lift it to the nearest common parent.
3. **Subtree**: if a whole section of the tree needs it, store it at the root of that section.
4. **Global**: only promote to global store as a last resort.

**DO: Lift state up only as far as needed.**

```tsx
// GOOD — parent owns the state shared between two children
function ProductPage() {
  const [selectedVariantId, setSelectedVariantId] = useState<string | null>(null);

  return (
    <>
      <VariantSelector onSelect={setSelectedVariantId} />
      <AddToCartButton variantId={selectedVariantId} />
    </>
  );
}
```

**DON'T: Lift state to a global store to avoid passing props one or two levels.**

```ts
// BAD — selectedVariantId is page-specific, not app-global
const useProductStore = create(set => ({
  selectedVariantId: null,
  setSelectedVariantId: (id) => set({ selectedVariantId: id }),
}));
```
