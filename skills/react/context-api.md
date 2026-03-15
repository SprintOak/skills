# React Context API

## Context vs Zustand — When to Use Each

Context and Zustand both solve the prop-drilling problem, but they serve different performance profiles and use cases.

| Criterion | Context API | Zustand |
|---|---|---|
| Update frequency | Low (theme, locale, auth) | Any (including high-frequency) |
| Re-render behavior | All consumers re-render on any change | Only selectors that consumed changed state |
| Boilerplate | Low | Low |
| DevTools | No (unless wrapped) | Yes (via middleware) |
| Best for | Static or slow-changing config | Application state that changes frequently |

**DO: Use Context for data that changes infrequently and is consumed broadly.**
- Authenticated user object (changes on login/logout, not on every action)
- Current locale/language
- Theme (light/dark)
- Feature flags
- Configuration/environment values

**DO: Use Zustand for state that changes frequently or requires fine-grained subscriptions.**
- UI state shared across many components
- Shopping cart contents
- Notification queue
- Any state that is updated in response to user interactions

**DON'T: Use Context for state that changes frequently.** Every component that consumes the context will re-render when any part of the context value changes, even if they only use one field.

---

## Context Creation Pattern

Always create context in its own file. Provide a sensible default value — this documents the shape and avoids `undefined` errors during tests.

```ts
// contexts/ThemeContext.ts
import { createContext } from 'react';

export type Theme = 'light' | 'dark';

export interface ThemeContextValue {
  theme: Theme;
  toggleTheme: () => void;
}

// Default value is used when a component is rendered outside a provider.
// For required contexts, set to null and validate in the custom hook.
export const ThemeContext = createContext<ThemeContextValue>({
  theme: 'light',
  toggleTheme: () => {},
});
```

---

## Always Export a Custom Hook, Never Raw useContext

**DO: Create and export a `useXxxContext` hook for every context.**

```ts
// contexts/ThemeContext.ts (continued)
import { useContext } from 'react';

export function useTheme(): ThemeContextValue {
  return useContext(ThemeContext);
}
```

This provides a single import point, allows you to add validation logic, and hides the implementation detail that it uses Context.

**DON'T: Call `useContext` directly in consuming components.**

```tsx
// BAD — exposes the context object to consumers
import { useContext } from 'react';
import { ThemeContext } from '@/contexts/ThemeContext';

function MyComponent() {
  const { theme } = useContext(ThemeContext); // don't do this
}
```

---

## Provider Component Pattern

The Provider component owns the state and logic. It wraps children and passes down the value.

```tsx
// contexts/ThemeContext.tsx
import { createContext, useContext, useState, useCallback } from 'react';

export type Theme = 'light' | 'dark';

interface ThemeContextValue {
  theme: Theme;
  toggleTheme: () => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>('light');

  const toggleTheme = useCallback(() => {
    setTheme(prev => (prev === 'light' ? 'dark' : 'light'));
  }, []);

  return (
    <ThemeContext.Provider value={{ theme, toggleTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme(): ThemeContextValue {
  const context = useContext(ThemeContext);
  if (context === null) {
    throw new Error('useTheme must be used within a ThemeProvider');
  }
  return context;
}
```

```tsx
// App.tsx — wrap the relevant subtree
import { ThemeProvider } from '@/contexts/ThemeContext';

function App() {
  return (
    <ThemeProvider>
      <Router />
    </ThemeProvider>
  );
}
```

---

## Never Call useContext Outside Its Provider

Always throw a descriptive error when the context is `null`. This catches developer mistakes early.

**DO: Validate context value in the custom hook.**

```ts
export function useTheme(): ThemeContextValue {
  const context = useContext(ThemeContext);
  if (context === null) {
    throw new Error(
      'useTheme was called outside of ThemeProvider. ' +
      'Wrap the component tree with <ThemeProvider>.',
    );
  }
  return context;
}
```

**DON'T: Return a fallback silently when context is missing.**

```ts
// BAD — hides a misconfiguration, causes subtle bugs
export function useTheme() {
  return useContext(ThemeContext) ?? { theme: 'light', toggleTheme: () => {} };
}
```

---

## Auth Context Pattern

The auth context is a common real-world example. It provides the current user, loading state, and auth actions.

```tsx
// contexts/AuthContext.tsx
import { createContext, useContext, useState, useEffect, useCallback } from 'react';
import { authService } from '@/services/authService';
import type { User } from '@/types';

interface AuthContextValue {
  user: User | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [isLoading, setIsLoading] = useState(true); // true on initial load

  useEffect(() => {
    // Attempt to restore session on mount
    authService
      .getSession()
      .then(setUser)
      .catch(() => setUser(null))
      .finally(() => setIsLoading(false));
  }, []);

  const login = useCallback(async (email: string, password: string) => {
    const user = await authService.login({ email, password });
    setUser(user);
  }, []);

  const logout = useCallback(async () => {
    await authService.logout();
    setUser(null);
  }, []);

  return (
    <AuthContext.Provider
      value={{
        user,
        isAuthenticated: user !== null,
        isLoading,
        login,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);
  if (context === null) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
```

Usage in a component:

```tsx
// components/UserMenu.tsx
import { useAuth } from '@/contexts/AuthContext';

export function UserMenu() {
  const { user, logout } = useAuth();

  return (
    <div>
      <span>Hello, {user?.name}</span>
      <button onClick={logout}>Logout</button>
    </div>
  );
}
```

---

## Theme Context Pattern

```tsx
// contexts/ThemeContext.tsx
import { createContext, useContext, useState, useEffect, useCallback } from 'react';

type Theme = 'light' | 'dark' | 'system';

interface ThemeContextValue {
  theme: Theme;
  resolvedTheme: 'light' | 'dark'; // actual applied theme after system preference
  setTheme: (theme: Theme) => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>(
    () => (localStorage.getItem('theme') as Theme) ?? 'system',
  );

  const resolvedTheme: 'light' | 'dark' =
    theme === 'system'
      ? window.matchMedia('(prefers-color-scheme: dark)').matches
        ? 'dark'
        : 'light'
      : theme;

  useEffect(() => {
    localStorage.setItem('theme', theme);
    document.documentElement.setAttribute('data-theme', resolvedTheme);
  }, [theme, resolvedTheme]);

  return (
    <ThemeContext.Provider value={{ theme, resolvedTheme, setTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme(): ThemeContextValue {
  const context = useContext(ThemeContext);
  if (context === null) {
    throw new Error('useTheme must be used within a ThemeProvider');
  }
  return context;
}
```

---

## Locale / i18n Context Pattern

```tsx
// contexts/LocaleContext.tsx
import { createContext, useContext, useState, useCallback } from 'react';

type Locale = 'en' | 'es' | 'fr' | 'de';

interface LocaleContextValue {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  t: (key: string) => string;
}

const LocaleContext = createContext<LocaleContextValue | null>(null);

export function LocaleProvider({ children }: { children: React.ReactNode }) {
  const [locale, setLocale] = useState<Locale>('en');

  const t = useCallback(
    (key: string): string => {
      // Replace with your actual i18n translation logic
      return translations[locale]?.[key] ?? key;
    },
    [locale],
  );

  return (
    <LocaleContext.Provider value={{ locale, setLocale, t }}>
      {children}
    </LocaleContext.Provider>
  );
}

export function useLocale(): LocaleContextValue {
  const context = useContext(LocaleContext);
  if (context === null) {
    throw new Error('useLocale must be used within a LocaleProvider');
  }
  return context;
}
```

---

## Split Read/Write Contexts for Performance

When a context value contains both frequently-read state and infrequently-called actions, split them into two contexts. Components that only call actions will not re-render when state changes.

```tsx
// contexts/CartContext.tsx
import { createContext, useContext, useReducer } from 'react';
import type { CartItem } from '@/types';

// --- State ---
interface CartState {
  items: CartItem[];
  total: number;
}

// --- Actions context (stable reference — never triggers re-render) ---
interface CartActions {
  addItem: (item: CartItem) => void;
  removeItem: (id: string) => void;
  clearCart: () => void;
}

const CartStateContext = createContext<CartState | null>(null);
const CartActionsContext = createContext<CartActions | null>(null);

// --- Reducer ---
type CartAction =
  | { type: 'ADD_ITEM'; payload: CartItem }
  | { type: 'REMOVE_ITEM'; payload: string }
  | { type: 'CLEAR' };

function cartReducer(state: CartState, action: CartAction): CartState {
  switch (action.type) {
    case 'ADD_ITEM':
      return {
        items: [...state.items, action.payload],
        total: state.total + action.payload.price,
      };
    case 'REMOVE_ITEM': {
      const item = state.items.find(i => i.id === action.payload);
      return {
        items: state.items.filter(i => i.id !== action.payload),
        total: state.total - (item?.price ?? 0),
      };
    }
    case 'CLEAR':
      return { items: [], total: 0 };
    default:
      return state;
  }
}

// --- Provider ---
export function CartProvider({ children }: { children: React.ReactNode }) {
  const [state, dispatch] = useReducer(cartReducer, { items: [], total: 0 });

  // Actions object is stable because dispatch is stable
  const actions: CartActions = {
    addItem: (item) => dispatch({ type: 'ADD_ITEM', payload: item }),
    removeItem: (id) => dispatch({ type: 'REMOVE_ITEM', payload: id }),
    clearCart: () => dispatch({ type: 'CLEAR' }),
  };

  return (
    <CartStateContext.Provider value={state}>
      <CartActionsContext.Provider value={actions}>
        {children}
      </CartActionsContext.Provider>
    </CartStateContext.Provider>
  );
}

// --- Hooks ---
export function useCartState(): CartState {
  const context = useContext(CartStateContext);
  if (context === null) throw new Error('useCartState must be used within CartProvider');
  return context;
}

export function useCartActions(): CartActions {
  const context = useContext(CartActionsContext);
  if (context === null) throw new Error('useCartActions must be used within CartProvider');
  return context;
}
```

The `AddToCartButton` component calls `useCartActions()` and will not re-render when the cart contents change. Only the `CartSummary` component, which calls `useCartState()`, re-renders on cart changes.

---

## Context Composition Pattern

Stack providers in `App.tsx` or a dedicated `Providers` component. Order matters — providers near the top are available to providers below them.

```tsx
// providers/AppProviders.tsx
import { ThemeProvider } from '@/contexts/ThemeContext';
import { LocaleProvider } from '@/contexts/LocaleContext';
import { AuthProvider } from '@/contexts/AuthContext';
import { CartProvider } from '@/contexts/CartContext';

export function AppProviders({ children }: { children: React.ReactNode }) {
  return (
    <ThemeProvider>
      <LocaleProvider>
        <AuthProvider>
          <CartProvider>
            {children}
          </CartProvider>
        </AuthProvider>
      </LocaleProvider>
    </ThemeProvider>
  );
}
```

```tsx
// main.tsx
import { AppProviders } from '@/providers/AppProviders';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <AppProviders>
        <App />
      </AppProviders>
    </QueryClientProvider>
  </StrictMode>,
);
```

---

## Context + useReducer for Complex State

When a context manages complex state with multiple transitions, use `useReducer` instead of multiple `useState` calls.

```tsx
// contexts/WizardContext.tsx
import { createContext, useContext, useReducer } from 'react';

interface WizardState {
  currentStep: number;
  totalSteps: number;
  data: Record<string, unknown>;
  isComplete: boolean;
}

type WizardAction =
  | { type: 'NEXT_STEP'; payload: Record<string, unknown> }
  | { type: 'PREV_STEP' }
  | { type: 'GO_TO_STEP'; payload: number }
  | { type: 'COMPLETE' }
  | { type: 'RESET' };

function wizardReducer(state: WizardState, action: WizardAction): WizardState {
  switch (action.type) {
    case 'NEXT_STEP':
      return {
        ...state,
        currentStep: Math.min(state.currentStep + 1, state.totalSteps - 1),
        data: { ...state.data, ...action.payload },
      };
    case 'PREV_STEP':
      return { ...state, currentStep: Math.max(state.currentStep - 1, 0) };
    case 'GO_TO_STEP':
      return { ...state, currentStep: action.payload };
    case 'COMPLETE':
      return { ...state, isComplete: true };
    case 'RESET':
      return { currentStep: 0, totalSteps: state.totalSteps, data: {}, isComplete: false };
    default:
      return state;
  }
}

const WizardContext = createContext<{
  state: WizardState;
  dispatch: React.Dispatch<WizardAction>;
} | null>(null);

export function WizardProvider({
  totalSteps,
  children,
}: {
  totalSteps: number;
  children: React.ReactNode;
}) {
  const [state, dispatch] = useReducer(wizardReducer, {
    currentStep: 0,
    totalSteps,
    data: {},
    isComplete: false,
  });

  return (
    <WizardContext.Provider value={{ state, dispatch }}>
      {children}
    </WizardContext.Provider>
  );
}

export function useWizard() {
  const context = useContext(WizardContext);
  if (context === null) throw new Error('useWizard must be used within a WizardProvider');
  return context;
}
```

---

## Split Context by Domain

**DON'T: Put unrelated state in a single "AppContext".**

```tsx
// BAD — mixing unrelated concerns in one context causes all consumers to re-render
const AppContext = createContext({
  user: null,
  theme: 'light',
  cartItems: [],
  locale: 'en',
  notifications: [],
});
```

**DO: Create one context per domain.**

```
contexts/
  AuthContext.tsx
  ThemeContext.tsx
  LocaleContext.tsx
  CartContext.tsx
  NotificationContext.tsx
```

---

## Testing Components That Use Context

Always wrap the component under test in the relevant provider. Prefer a reusable `renderWithProviders` utility.

```tsx
// test/utils.tsx
import { render } from '@testing-library/react';
import { ThemeProvider } from '@/contexts/ThemeContext';
import { AuthProvider } from '@/contexts/AuthContext';

export function renderWithProviders(ui: React.ReactElement) {
  return render(
    <ThemeProvider>
      <AuthProvider>
        {ui}
      </AuthProvider>
    </ThemeProvider>,
  );
}
```

```tsx
// UserMenu.test.tsx
import { renderWithProviders } from '@/test/utils';
import { UserMenu } from './UserMenu';

test('renders logout button when user is authenticated', () => {
  const { getByText } = renderWithProviders(<UserMenu />);
  expect(getByText('Logout')).toBeInTheDocument();
});
```

For tests that need to control context values, create a mock provider:

```tsx
// test/mocks/MockAuthProvider.tsx
import { AuthContext } from '@/contexts/AuthContext';

export function MockAuthProvider({
  user = null,
  isAuthenticated = false,
  children,
}: {
  user?: User | null;
  isAuthenticated?: boolean;
  children: React.ReactNode;
}) {
  return (
    <AuthContext.Provider
      value={{
        user,
        isAuthenticated,
        isLoading: false,
        login: async () => {},
        logout: async () => {},
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}
```
