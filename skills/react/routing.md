# React Routing

## Router Setup — React Router v6+

Use `createBrowserRouter` (the Data API router) instead of the legacy `<BrowserRouter>` component. It supports loaders, actions, and error boundaries at the route level.

```bash
npm install react-router-dom
```

**DO: Use `createBrowserRouter`.**

```tsx
// router/index.tsx
import { createBrowserRouter } from 'react-router-dom';

export const router = createBrowserRouter([
  // route definitions
]);
```

**DON'T: Use the legacy `<BrowserRouter>` + `<Routes>` JSX approach for new projects.**

```tsx
// AVOID for new projects — use createBrowserRouter instead
function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Home />} />
      </Routes>
    </BrowserRouter>
  );
}
```

---

## Route Constants

Define all paths as constants. Never write path strings inline in components.

```ts
// router/routes.ts
export const ROUTES = {
  HOME: '/',
  LOGIN: '/login',
  REGISTER: '/register',

  DASHBOARD: '/dashboard',

  USERS: {
    ROOT: '/users',
    LIST: '/users',
    DETAIL: (id: string) => `/users/${id}`,
    CREATE: '/users/new',
    EDIT: (id: string) => `/users/${id}/edit`,
  },

  PRODUCTS: {
    ROOT: '/products',
    LIST: '/products',
    DETAIL: (id: string) => `/products/${id}`,
    CREATE: '/products/new',
  },

  SETTINGS: {
    ROOT: '/settings',
    PROFILE: '/settings/profile',
    SECURITY: '/settings/security',
    BILLING: '/settings/billing',
  },

  NOT_FOUND: '/404',
} as const;
```

Usage in components:

```tsx
import { Link } from 'react-router-dom';
import { ROUTES } from '@/router/routes';

<Link to={ROUTES.USERS.DETAIL(user.id)}>View User</Link>
<Link to={ROUTES.USERS.CREATE}>Add User</Link>
```

---

## Full Router Definition

```tsx
// router/index.tsx
import { createBrowserRouter, Navigate } from 'react-router-dom';
import { lazy, Suspense } from 'react';
import { RootLayout } from '@/layouts/RootLayout';
import { AuthLayout } from '@/layouts/AuthLayout';
import { DashboardLayout } from '@/layouts/DashboardLayout';
import { PrivateRoute } from './PrivateRoute';
import { RoleGuard } from './RoleGuard';
import { Spinner } from '@/components/ui/Spinner';
import { ROUTES } from './routes';

// Lazy-loaded page components
const LoginPage = lazy(() => import('@/pages/auth/LoginPage'));
const RegisterPage = lazy(() => import('@/pages/auth/RegisterPage'));
const DashboardPage = lazy(() => import('@/pages/dashboard/DashboardPage'));
const UsersListPage = lazy(() => import('@/pages/users/UsersListPage'));
const UserDetailPage = lazy(() => import('@/pages/users/UserDetailPage'));
const UserCreatePage = lazy(() => import('@/pages/users/UserCreatePage'));
const UserEditPage = lazy(() => import('@/pages/users/UserEditPage'));
const ProductsListPage = lazy(() => import('@/pages/products/ProductsListPage'));
const SettingsProfilePage = lazy(() => import('@/pages/settings/SettingsProfilePage'));
const SettingsSecurityPage = lazy(() => import('@/pages/settings/SettingsSecurityPage'));
const NotFoundPage = lazy(() => import('@/pages/NotFoundPage'));

const withSuspense = (element: React.ReactNode) => (
  <Suspense fallback={<Spinner fullPage />}>{element}</Suspense>
);

export const router = createBrowserRouter([
  {
    element: <RootLayout />,
    children: [
      // --- Public routes ---
      {
        element: <AuthLayout />,
        children: [
          { path: ROUTES.LOGIN, element: withSuspense(<LoginPage />) },
          { path: ROUTES.REGISTER, element: withSuspense(<RegisterPage />) },
        ],
      },

      // --- Protected routes ---
      {
        element: <PrivateRoute />,
        children: [
          {
            element: <DashboardLayout />,
            children: [
              // Redirect root to dashboard
              { index: true, element: <Navigate to={ROUTES.DASHBOARD} replace /> },

              { path: ROUTES.DASHBOARD, element: withSuspense(<DashboardPage />) },

              // Users — admin only
              {
                element: <RoleGuard allowedRoles={['admin']} />,
                children: [
                  { path: ROUTES.USERS.LIST, element: withSuspense(<UsersListPage />) },
                  { path: ROUTES.USERS.CREATE, element: withSuspense(<UserCreatePage />) },
                  { path: `${ROUTES.USERS.ROOT}/:id`, element: withSuspense(<UserDetailPage />) },
                  { path: `${ROUTES.USERS.ROOT}/:id/edit`, element: withSuspense(<UserEditPage />) },
                ],
              },

              // Products
              { path: ROUTES.PRODUCTS.LIST, element: withSuspense(<ProductsListPage />) },

              // Settings — nested routes
              {
                path: ROUTES.SETTINGS.ROOT,
                element: withSuspense(<SettingsProfilePage />),
                children: [
                  { index: true, element: <Navigate to={ROUTES.SETTINGS.PROFILE} replace /> },
                  { path: 'profile', element: withSuspense(<SettingsProfilePage />) },
                  { path: 'security', element: withSuspense(<SettingsSecurityPage />) },
                ],
              },
            ],
          },
        ],
      },

      // --- 404 catch-all ---
      { path: '*', element: withSuspense(<NotFoundPage />) },
    ],
  },
]);
```

```tsx
// main.tsx
import { RouterProvider } from 'react-router-dom';
import { router } from '@/router';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <AppProviders>
        <RouterProvider router={router} />
      </AppProviders>
    </QueryClientProvider>
  </StrictMode>,
);
```

---

## Protected Route Component

The `PrivateRoute` component checks authentication and redirects unauthenticated users to login.

```tsx
// router/PrivateRoute.tsx
import { Navigate, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { Spinner } from '@/components/ui/Spinner';
import { ROUTES } from './routes';

export function PrivateRoute() {
  const { isAuthenticated, isLoading } = useAuth();
  const location = useLocation();

  // Wait for auth state to be resolved before redirecting
  if (isLoading) {
    return <Spinner fullPage />;
  }

  if (!isAuthenticated) {
    // Preserve the attempted URL so we can redirect back after login
    return <Navigate to={ROUTES.LOGIN} state={{ from: location }} replace />;
  }

  return <Outlet />;
}
```

Redirect back after login:

```tsx
// pages/auth/LoginPage.tsx
import { useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { ROUTES } from '@/router/routes';

export default function LoginPage() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const from = (location.state as { from?: Location })?.from?.pathname ?? ROUTES.DASHBOARD;

  const handleLogin = async (data: LoginFormData) => {
    await login(data.email, data.password);
    navigate(from, { replace: true }); // go back to where the user came from
  };

  return <LoginForm onSubmit={handleLogin} />;
}
```

---

## Role-Based Route Guard

```tsx
// router/RoleGuard.tsx
import { Navigate, Outlet } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { ROUTES } from './routes';
import type { UserRole } from '@/types';

interface RoleGuardProps {
  allowedRoles: UserRole[];
}

export function RoleGuard({ allowedRoles }: RoleGuardProps) {
  const { user } = useAuth();

  if (!user || !allowedRoles.includes(user.role)) {
    return <Navigate to={ROUTES.DASHBOARD} replace />;
  }

  return <Outlet />;
}
```

---

## Layout Routes

Layout components use `<Outlet />` to render child routes in their content area.

```tsx
// layouts/RootLayout.tsx
import { Outlet } from 'react-router-dom';

export function RootLayout() {
  return (
    <div id="root-layout">
      <Outlet />
    </div>
  );
}
```

```tsx
// layouts/DashboardLayout.tsx
import { Outlet } from 'react-router-dom';
import { Sidebar } from '@/components/navigation/Sidebar';
import { TopBar } from '@/components/navigation/TopBar';

export function DashboardLayout() {
  return (
    <div className="dashboard-layout">
      <Sidebar />
      <div className="dashboard-main">
        <TopBar />
        <main className="dashboard-content">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
```

```tsx
// layouts/AuthLayout.tsx
import { Outlet } from 'react-router-dom';

export function AuthLayout() {
  return (
    <div className="auth-layout">
      <div className="auth-card">
        <Outlet />
      </div>
    </div>
  );
}
```

---

## Lazy Loading with React.lazy + Suspense

Every page component should be lazy-loaded to reduce the initial bundle size.

**DO: Lazy-load all page-level components.**

```tsx
// router/index.tsx
import { lazy, Suspense } from 'react';

const DashboardPage = lazy(() => import('@/pages/dashboard/DashboardPage'));
```

**DO: Wrap lazy components in `<Suspense>` with a fallback.**

```tsx
<Suspense fallback={<Spinner fullPage />}>
  <DashboardPage />
</Suspense>
```

**DON'T: Lazy-load small shared UI components** (buttons, inputs, etc.). Only lazy-load at the page or large feature level.

---

## Route Parameters — useParams with TypeScript

```tsx
// pages/users/UserDetailPage.tsx
import { useParams } from 'react-router-dom';
import { useUser } from '@/hooks/queries/useUsers';

interface UserDetailParams {
  id: string;
}

export default function UserDetailPage() {
  const { id } = useParams<UserDetailParams>();

  if (!id) {
    return <div>Invalid user ID</div>;
  }

  const { data: user, isLoading } = useUser(id);

  if (isLoading) return <Spinner />;
  if (!user) return <NotFound />;

  return (
    <div>
      <h1>{user.name}</h1>
      <p>{user.email}</p>
    </div>
  );
}
```

---

## Query Parameters — useSearchParams

Use `useSearchParams` for filter, search, and pagination state in the URL. This makes the page shareable and supports the browser back button.

```tsx
// pages/users/UsersListPage.tsx
import { useSearchParams } from 'react-router-dom';
import { useUsers } from '@/hooks/queries/useUsers';

export default function UsersListPage() {
  const [searchParams, setSearchParams] = useSearchParams();

  const filters = {
    search: searchParams.get('search') ?? '',
    role: (searchParams.get('role') ?? '') as UserRole | '',
    page: Number(searchParams.get('page') ?? '1'),
  };

  const { data, isLoading } = useUsers(filters);

  const updateFilter = (key: string, value: string) => {
    setSearchParams(prev => {
      const next = new URLSearchParams(prev);
      if (value) {
        next.set(key, value);
      } else {
        next.delete(key);
      }
      if (key !== 'page') next.set('page', '1'); // reset page on filter change
      return next;
    });
  };

  return (
    <div>
      <input
        value={filters.search}
        onChange={e => updateFilter('search', e.target.value)}
        placeholder="Search users..."
      />
      <select
        value={filters.role}
        onChange={e => updateFilter('role', e.target.value)}
      >
        <option value="">All roles</option>
        <option value="admin">Admin</option>
        <option value="editor">Editor</option>
        <option value="viewer">Viewer</option>
      </select>
      {isLoading ? <Spinner /> : <UserTable users={data?.data ?? []} />}
      <Pagination
        page={filters.page}
        totalPages={data?.meta.totalPages ?? 1}
        onPageChange={p => updateFilter('page', String(p))}
      />
    </div>
  );
}
```

---

## Programmatic Navigation — useNavigate

```tsx
// After a successful form submission
import { useNavigate } from 'react-router-dom';
import { ROUTES } from '@/router/routes';

export function UserCreatePage() {
  const navigate = useNavigate();
  const { mutate: createUser } = useCreateUser();

  const handleSubmit = (data: CreateUserPayload) => {
    createUser(data, {
      onSuccess: (newUser) => {
        navigate(ROUTES.USERS.DETAIL(newUser.id));
      },
    });
  };

  return <UserForm onSubmit={handleSubmit} />;
}
```

**DO: Use `navigate(-1)` to go back instead of hardcoding a previous path.**

```tsx
<button onClick={() => navigate(-1)}>Back</button>
```

**DO: Use `replace: true` for redirects that should not add to the history stack** (e.g., after login, after delete).

```tsx
navigate(ROUTES.USERS.LIST, { replace: true });
```

---

## Nested Routes with Outlet

```tsx
// router/index.tsx — settings section with nested tabs
{
  path: ROUTES.SETTINGS.ROOT,
  element: <SettingsLayout />,
  children: [
    { index: true, element: <Navigate to="profile" replace /> },
    { path: 'profile', element: withSuspense(<SettingsProfilePage />) },
    { path: 'security', element: withSuspense(<SettingsSecurityPage />) },
    { path: 'billing', element: withSuspense(<SettingsBillingPage />) },
  ],
}
```

```tsx
// layouts/SettingsLayout.tsx
import { Outlet, NavLink } from 'react-router-dom';
import { ROUTES } from '@/router/routes';

export function SettingsLayout() {
  return (
    <div className="settings-layout">
      <nav className="settings-nav">
        <NavLink to={ROUTES.SETTINGS.PROFILE}
          className={({ isActive }) => isActive ? 'nav-item active' : 'nav-item'}
        >
          Profile
        </NavLink>
        <NavLink to={ROUTES.SETTINGS.SECURITY}
          className={({ isActive }) => isActive ? 'nav-item active' : 'nav-item'}
        >
          Security
        </NavLink>
        <NavLink to={ROUTES.SETTINGS.BILLING}
          className={({ isActive }) => isActive ? 'nav-item active' : 'nav-item'}
        >
          Billing
        </NavLink>
      </nav>
      <div className="settings-content">
        <Outlet />
      </div>
    </div>
  );
}
```

---

## Redirect Patterns

```tsx
// Redirect index route to a default child
{ index: true, element: <Navigate to={ROUTES.DASHBOARD} replace /> }

// Conditional redirect based on auth
{ path: ROUTES.LOGIN, element: <PublicOnlyRoute><LoginPage /></PublicOnlyRoute> }
```

```tsx
// router/PublicOnlyRoute.tsx — redirect authenticated users away from login/register
import { Navigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { ROUTES } from './routes';

export function PublicOnlyRoute({ children }: { children: React.ReactNode }) {
  const { isAuthenticated } = useAuth();
  return isAuthenticated ? <Navigate to={ROUTES.DASHBOARD} replace /> : <>{children}</>;
}
```

---

## Breadcrumb Generation

Derive breadcrumbs from the current route using `useMatches`.

```tsx
// components/navigation/Breadcrumbs.tsx
import { useMatches, Link } from 'react-router-dom';

interface RouteHandle {
  breadcrumb?: (params: Record<string, string | undefined>) => string;
}

export function Breadcrumbs() {
  const matches = useMatches();

  const crumbs = matches
    .filter(match => (match.handle as RouteHandle)?.breadcrumb)
    .map(match => ({
      label: (match.handle as RouteHandle).breadcrumb!(match.params as Record<string, string | undefined>),
      to: match.pathname,
    }));

  if (crumbs.length <= 1) return null;

  return (
    <nav aria-label="Breadcrumb">
      <ol>
        {crumbs.map((crumb, index) => (
          <li key={crumb.to}>
            {index < crumbs.length - 1 ? (
              <Link to={crumb.to}>{crumb.label}</Link>
            ) : (
              <span aria-current="page">{crumb.label}</span>
            )}
          </li>
        ))}
      </ol>
    </nav>
  );
}
```

Attach breadcrumb metadata to route definitions:

```tsx
// router/index.tsx
{
  path: ROUTES.USERS.LIST,
  element: withSuspense(<UsersListPage />),
  handle: { breadcrumb: () => 'Users' },
},
{
  path: `${ROUTES.USERS.ROOT}/:id`,
  element: withSuspense(<UserDetailPage />),
  handle: { breadcrumb: (params) => `User ${params.id}` },
},
```

---

## 404 Catch-All Route

```tsx
// pages/NotFoundPage.tsx
import { Link } from 'react-router-dom';
import { ROUTES } from '@/router/routes';

export default function NotFoundPage() {
  return (
    <div className="not-found">
      <h1>404 — Page Not Found</h1>
      <p>The page you are looking for does not exist.</p>
      <Link to={ROUTES.HOME}>Go home</Link>
    </div>
  );
}
```

```tsx
// In router/index.tsx
{ path: '*', element: withSuspense(<NotFoundPage />) }
```

---

## URL State for Filters — Preserve on Browser Back

When a user navigates away from a filtered list and presses back, the filters should be restored. Since filters live in the URL via `useSearchParams`, this happens automatically.

**DO: Always put list filters, search queries, and pagination in the URL via `useSearchParams`.**

**DON'T: Store filters in `useState` or in a Zustand store.** They will be lost on navigation.

```tsx
// GOOD — filters survive navigation because they live in the URL
const [searchParams] = useSearchParams();
const page = Number(searchParams.get('page') ?? '1');
const search = searchParams.get('search') ?? '';

// BAD — filters reset on navigation
const [page, setPage] = useState(1);
const [search, setSearch] = useState('');
```
