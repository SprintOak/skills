# React + TypeScript Project Folder Structure

This document defines the canonical folder structure for React + TypeScript projects. Follow this layout consistently across all projects to ensure predictability, maintainability, and clear ownership of code.

---

## Top-Level Structure

```
project-root/
├── public/
│   ├── index.html
│   ├── favicon.ico
│   └── robots.txt
├── src/
│   ├── assets/
│   ├── components/
│   ├── config/
│   ├── constants/
│   ├── contexts/
│   ├── features/
│   ├── hooks/
│   ├── pages/
│   ├── router/
│   ├── services/
│   ├── store/
│   ├── styles/
│   ├── types/
│   ├── utils/
│   ├── App.tsx
│   └── main.tsx
├── .env
├── .env.example
├── tsconfig.json
├── vite.config.ts
└── package.json
```

---

## Directory Breakdown

### `src/assets/`

Static assets that are imported directly into components.

```
assets/
├── fonts/
│   └── inter.woff2
├── icons/
│   ├── chevron-down.svg
│   └── close.svg
└── images/
    ├── hero-bg.jpg
    └── logo.png
```

- Store only source-controlled static files here.
- For SVGs used as React components, use a tool like `vite-plugin-svgr` and keep the SVG files in `assets/icons/`.
- Do NOT store generated files or build artifacts here.

---

### `src/components/`

Shared, reusable UI components that are not tied to any specific feature or page.

```
components/
├── Button/
│   ├── index.ts
│   ├── Button.tsx
│   ├── Button.test.tsx
│   └── Button.module.css
├── Modal/
│   ├── index.ts
│   ├── Modal.tsx
│   ├── Modal.test.tsx
│   └── Modal.module.css
├── Input/
│   ├── index.ts
│   ├── Input.tsx
│   ├── Input.test.tsx
│   └── Input.module.css
└── index.ts
```

**Rules:**
- Every component lives in its own folder named with PascalCase.
- Each folder contains: `ComponentName.tsx` (implementation), `index.ts` (barrel export), `ComponentName.test.tsx` (unit tests), and `ComponentName.module.css` (scoped styles).
- The `index.ts` barrel re-exports only what consumers need.

```ts
// components/Button/index.ts
export { Button } from './Button';
export type { ButtonProps } from './Button';
```

```tsx
// components/Button/Button.tsx
import styles from './Button.module.css';

export interface ButtonProps {
  label: string;
  variant?: 'primary' | 'secondary' | 'ghost';
  disabled?: boolean;
  onClick?: React.MouseEventHandler<HTMLButtonElement>;
}

export function Button({ label, variant = 'primary', disabled = false, onClick }: ButtonProps) {
  return (
    <button
      className={`${styles.button} ${styles[variant]}`}
      disabled={disabled}
      onClick={onClick}
    >
      {label}
    </button>
  );
}
```

---

### `src/pages/`

Route-level components. One file (or folder) per route, mirroring the URL structure.

```
pages/
├── Home/
│   ├── index.ts
│   ├── HomePage.tsx
│   └── HomePage.test.tsx
├── Dashboard/
│   ├── index.ts
│   ├── DashboardPage.tsx
│   └── DashboardPage.test.tsx
├── Users/
│   ├── index.ts
│   ├── UsersPage.tsx
│   └── UsersPage.test.tsx
└── NotFound/
    ├── index.ts
    └── NotFoundPage.tsx
```

**Rules:**
- Page components are responsible for layout composition and data fetching orchestration only.
- Pages should NOT contain business logic — delegate to feature components or hooks.
- Name page components with the `Page` suffix: `DashboardPage`, `UsersPage`.
- Pages do NOT get their own CSS modules unless they have truly unique layout styles. Prefer feature or shared components for styling.

---

### `src/features/`

Feature-based modules. Each feature encapsulates everything related to a single domain concept.

```
features/
├── auth/
│   ├── components/
│   │   ├── LoginForm/
│   │   │   ├── LoginForm.tsx
│   │   │   ├── LoginForm.test.tsx
│   │   │   ├── LoginForm.module.css
│   │   │   └── index.ts
│   │   └── index.ts
│   ├── hooks/
│   │   ├── useAuth.ts
│   │   ├── useLoginForm.ts
│   │   └── index.ts
│   ├── api/
│   │   ├── authApi.ts
│   │   └── index.ts
│   ├── types/
│   │   ├── auth.types.ts
│   │   └── index.ts
│   ├── store/
│   │   ├── authStore.ts
│   │   └── index.ts
│   └── index.ts
├── users/
│   ├── components/
│   ├── hooks/
│   ├── api/
│   ├── types/
│   ├── store/
│   └── index.ts
└── dashboard/
    ├── components/
    ├── hooks/
    ├── api/
    ├── types/
    └── index.ts
```

**Rules:**
- Each feature folder is self-contained. It should be theoretically possible to delete a feature folder and have the rest of the app compile.
- Cross-feature imports are allowed but should go through the feature's `index.ts` barrel — never deep-import from another feature's internals.
- A feature's `index.ts` defines its public API.

```ts
// features/auth/index.ts — public API of the auth feature
export { LoginForm } from './components';
export { useAuth, useLoginForm } from './hooks';
export type { AuthUser, LoginPayload } from './types';
```

```ts
// CORRECT: import from a feature's public API
import { useAuth } from '@/features/auth';

// WRONG: deep import into another feature's internals
import { useAuth } from '@/features/auth/hooks/useAuth';
```

---

### `src/hooks/`

Global custom hooks not tied to any specific feature.

```
hooks/
├── useDebounce.ts
├── useLocalStorage.ts
├── useMediaQuery.ts
├── useClickOutside.ts
├── useIntersectionObserver.ts
└── index.ts
```

- Only place hooks here that are used by 2 or more features or are truly domain-agnostic.
- Feature-specific hooks belong in `features/<name>/hooks/`.

---

### `src/contexts/`

React context definitions. Keep context files small — one concern per context.

```
contexts/
├── ThemeContext.tsx
├── ToastContext.tsx
└── index.ts
```

```tsx
// contexts/ThemeContext.tsx
import { createContext, useContext, useState } from 'react';

type Theme = 'light' | 'dark';

interface ThemeContextValue {
  theme: Theme;
  toggleTheme: () => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>('light');
  const toggleTheme = () => setTheme((t) => (t === 'light' ? 'dark' : 'light'));
  return <ThemeContext.Provider value={{ theme, toggleTheme }}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error('useTheme must be used within ThemeProvider');
  return ctx;
}
```

---

### `src/store/`

Global state management using Zustand. Only for truly global state (auth session, UI preferences, notifications).

```
store/
├── uiStore.ts
├── notificationStore.ts
└── index.ts
```

- Feature-scoped state lives in `features/<name>/store/`.
- Do NOT put server state (API data) in Zustand — use React Query or SWR for that.

---

### `src/services/`

API service functions using axios. Services are plain functions, not classes.

```
services/
├── httpClient.ts
├── authService.ts
├── usersService.ts
└── index.ts
```

```ts
// services/httpClient.ts
import axios from 'axios';
import { API_BASE_URL } from '@/config';

export const httpClient = axios.create({
  baseURL: API_BASE_URL,
  timeout: 10_000,
  headers: { 'Content-Type': 'application/json' },
});

httpClient.interceptors.request.use((config) => {
  const token = localStorage.getItem('auth_token');
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});
```

- Feature-specific API calls belong in `features/<name>/api/`.
- Global or cross-cutting API logic (interceptors, base client) lives in `services/`.

---

### `src/types/`

Global TypeScript types and interfaces shared across the entire application.

```
types/
├── api.types.ts
├── common.types.ts
└── index.ts
```

```ts
// types/api.types.ts
export interface ApiResponse<T> {
  data: T;
  message: string;
  success: boolean;
}

export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  pageSize: number;
}

export interface ApiError {
  message: string;
  statusCode: number;
  errors?: Record<string, string[]>;
}
```

- Feature-specific types belong in `features/<name>/types/`.
- Do NOT put component prop types here — those stay co-located with their component.

---

### `src/utils/`

Pure utility functions with no side effects and no React dependencies.

```
utils/
├── formatDate.ts
├── formatCurrency.ts
├── validators.ts
├── cn.ts
└── index.ts
```

```ts
// utils/formatDate.ts
export function formatDate(date: Date | string, locale = 'en-US'): string {
  return new Intl.DateTimeFormat(locale, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(new Date(date));
}
```

- Utility functions must be pure (no side effects, same input always produces same output).
- Each utility file should contain functions of one logical domain (date formatting, string manipulation, validation).
- Always write unit tests for utility functions.

---

### `src/constants/`

Application-wide constants and enums.

```
constants/
├── routes.ts
├── queryKeys.ts
├── breakpoints.ts
└── index.ts
```

```ts
// constants/routes.ts
export const ROUTES = {
  HOME: '/',
  DASHBOARD: '/dashboard',
  USERS: '/users',
  USER_DETAIL: (id: string) => `/users/${id}`,
  SETTINGS: '/settings',
} as const;

// constants/queryKeys.ts
export const QUERY_KEYS = {
  users: {
    all: ['users'] as const,
    list: (filters: Record<string, unknown>) => ['users', 'list', filters] as const,
    detail: (id: string) => ['users', 'detail', id] as const,
  },
} as const;
```

---

### `src/config/`

Environment configuration and API settings.

```
config/
├── env.ts
└── index.ts
```

```ts
// config/env.ts
export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL as string;
export const APP_ENV = import.meta.env.MODE;
export const IS_PRODUCTION = APP_ENV === 'production';

if (!API_BASE_URL) {
  throw new Error('VITE_API_BASE_URL environment variable is not set');
}
```

- Validate required environment variables at startup — fail fast rather than produce confusing runtime errors.
- Never hardcode URLs or secrets directly in component or service files.

---

### `src/router/`

Route definitions, guards, and lazy-loading configuration.

```
router/
├── index.tsx
├── ProtectedRoute.tsx
└── routes.tsx
```

```tsx
// router/index.tsx
import { createBrowserRouter } from 'react-router-dom';
import { lazy, Suspense } from 'react';
import { ProtectedRoute } from './ProtectedRoute';

const DashboardPage = lazy(() => import('@/pages/Dashboard'));
const UsersPage = lazy(() => import('@/pages/Users'));

export const router = createBrowserRouter([
  {
    path: '/',
    element: <ProtectedRoute />,
    children: [
      { path: 'dashboard', element: <Suspense fallback={<div>Loading...</div>}><DashboardPage /></Suspense> },
      { path: 'users', element: <Suspense fallback={<div>Loading...</div>}><UsersPage /></Suspense> },
    ],
  },
]);
```

---

### `src/styles/`

Global styles, CSS custom properties (design tokens), and theme configuration.

```
styles/
├── global.css
├── variables.css
├── reset.css
└── typography.css
```

- Component-specific styles use CSS Modules co-located with the component file.
- Only truly global styles (resets, font imports, CSS variables) belong here.

---

## Naming Conventions

| Artifact | Convention | Example |
|---|---|---|
| Components / Pages | PascalCase | `UserCard.tsx`, `DashboardPage.tsx` |
| Custom Hooks | camelCase with `use` prefix | `useAuth.ts`, `useDebounce.ts` |
| Services | camelCase with `Service` suffix | `authService.ts`, `usersService.ts` |
| Utilities | camelCase | `formatDate.ts`, `validators.ts` |
| CSS Modules | camelCase | `Button.module.css` |
| Zustand stores | camelCase with `Store` suffix | `authStore.ts`, `uiStore.ts` |
| Type files | camelCase with `.types.ts` suffix | `auth.types.ts` |
| Constants files | camelCase | `routes.ts`, `queryKeys.ts` |
| Folders | kebab-case (for features) | `user-profile/`, `order-management/` |

---

## Barrel Exports (index.ts) — Usage and Pitfalls

### DO use barrel exports to define a public API:

```ts
// components/index.ts
export { Button } from './Button';
export { Modal } from './Modal';
export { Input } from './Input';
```

### DON'T create deeply nested barrel chains that import everything:

```ts
// WRONG: mega-barrel that imports the entire app
export * from './components';
export * from './hooks';
export * from './utils';
// This causes circular dependency risks and hurts tree-shaking
```

### Pitfalls to avoid:
- Circular dependencies: if `features/auth` imports from `features/users` and vice versa through barrels, the bundler will produce a circular dependency error.
- Over-exporting: only export what external consumers need. Internal implementation files should not be re-exported.
- Barrel files in large apps can slow down TypeScript's language server. If you notice sluggishness, consider reducing barrel depth.

---

## Feature-First vs Layer-First Architecture

This project uses **feature-first** architecture as the primary organizing principle.

### Feature-First (recommended):
```
features/
├── auth/       ← all auth-related code together
├── users/      ← all users-related code together
└── billing/    ← all billing-related code together
```

**Benefits:** High cohesion, easy to understand and delete features, clear ownership.

### Layer-First (avoid for large apps):
```
components/    ← all components from all features
hooks/         ← all hooks from all features
services/      ← all services from all features
```

**Problem:** As the app grows, these folders become grab-bags with hundreds of files.

### Hybrid approach used in this project:
- Feature-first for domain logic (`features/`)
- Layer-first for truly shared infrastructure (`components/`, `hooks/`, `utils/`, `services/`)

---

## When to Move a Component from Feature to Shared

Move a component from `features/<name>/components/` to `src/components/` when:

1. It is used in 2 or more separate features.
2. It has no dependency on any single feature's state, types, or API.
3. It is purely presentational (no business logic).
4. It would make sense in a design system or component library.

Keep a component in a feature when:
- It uses that feature's Zustand store or React Query hooks.
- It renders data shapes specific to that feature's API response types.
- It would not make sense outside the context of that feature.
