# React Testing

## Stack

- **Vitest** — test runner (fast, Vite-native, Jest-compatible API)
- **React Testing Library (RTL)** — component rendering and querying
- **@testing-library/user-event** — realistic user interaction simulation
- **MSW (Mock Service Worker)** — API mocking at the network level
- **@testing-library/jest-dom** — extended DOM matchers

```bash
npm install -D vitest @testing-library/react @testing-library/user-event @testing-library/jest-dom msw
```

---

## Philosophy: Test Behavior, Not Implementation

Tests exist to give you confidence that the application works for users. Write tests that interact with the UI the same way a user would.

DO: Test what the user sees and does.
DON'T: Test internal state, private methods, or implementation details.

```tsx
// BAD — tests implementation detail (internal state)
it('should set isLoading to true', () => {
  const { result } = renderHook(() => useMyHook());
  expect(result.current.isLoading).toBe(true); // who cares about the name of the variable
});

// GOOD — tests observable behavior
it('should show a loading spinner while fetching', async () => {
  render(<UserProfile userId="1" />);
  expect(screen.getByRole('progressbar')).toBeInTheDocument();
  await waitForElementToBeRemoved(() => screen.queryByRole('progressbar'));
});
```

---

## What to Test

DO test:
- User interactions (clicks, typing, form submissions)
- Rendered output based on props
- Conditional rendering (loading states, error states, empty states)
- Async operations (data fetching, form submission responses)
- Accessibility attributes and roles

DON'T test:
- Internal component state
- Method calls or function invocations (unless via observable side effects)
- Implementation details of third-party libraries
- Styling details (CSS class names, inline styles)

---

## Vitest Configuration

```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    coverage: {
      provider: 'v8',
      exclude: [
        '**/*.stories.{ts,tsx}',
        '**/*.types.ts',
        '**/index.ts',
        '**/test/**',
        '**/mocks/**',
      ],
    },
  },
});
```

```ts
// src/test/setup.ts
import '@testing-library/jest-dom';
import { server } from './server';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

---

## Custom Render with Providers

Always wrap renders with your application providers. Do this once in a shared utility.

```tsx
// src/test/utils.tsx
import { ReactElement } from 'react';
import { render, RenderOptions } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { ThemeProvider } from '../context/ThemeContext';

function createTestQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,       // don't retry in tests — fail fast
        gcTime: Infinity,
      },
    },
  });
}

interface WrapperProps {
  children: React.ReactNode;
  initialEntries?: string[];
}

function AllProviders({ children, initialEntries = ['/'] }: WrapperProps) {
  const queryClient = createTestQueryClient();
  return (
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={initialEntries}>
        <ThemeProvider>
          {children}
        </ThemeProvider>
      </MemoryRouter>
    </QueryClientProvider>
  );
}

function customRender(
  ui: ReactElement,
  options?: Omit<RenderOptions, 'wrapper'> & { initialEntries?: string[] }
) {
  const { initialEntries, ...renderOptions } = options ?? {};
  return render(ui, {
    wrapper: ({ children }) => (
      <AllProviders initialEntries={initialEntries}>{children}</AllProviders>
    ),
    ...renderOptions,
  });
}

// Re-export everything from RTL so tests only import from this file
export * from '@testing-library/react';
export { customRender as render };
```

```tsx
// Usage in a test
import { render, screen } from '../test/utils';

it('should render user profile', () => {
  render(<UserProfile userId="1" />);
  // ...
});
```

---

## Query Priority

Use queries in this order of preference. Higher-priority queries reflect how users and assistive technologies interact with the page.

1. `getByRole` — semantic role (button, heading, textbox, checkbox, etc.)
2. `getByLabelText` — form inputs associated with a label
3. `getByPlaceholderText` — inputs with placeholder text
4. `getByText` — visible text content
5. `getByDisplayValue` — current value of form inputs
6. `getByAltText` — images with alt text
7. `getByTitle` — title attribute
8. `getByTestId` — last resort only

```tsx
// PREFER this
screen.getByRole('button', { name: /submit/i });
screen.getByRole('heading', { name: /user profile/i });
screen.getByLabelText(/email address/i);

// AVOID this unless no semantic alternative exists
screen.getByTestId('submit-button');
```

DO: Add `data-testid` only when there is genuinely no accessible alternative (e.g., a custom canvas element).
DON'T: Add `data-testid` to elements that already have a semantic role or label.

---

## userEvent vs fireEvent

Always use `userEvent` for user interactions. It simulates realistic browser events (pointerdown, mousedown, focus, click, pointerup, mouseup) rather than dispatching a single synthetic event.

```tsx
import userEvent from '@testing-library/user-event';

// GOOD — realistic interaction
it('should submit the form', async () => {
  const user = userEvent.setup();
  render(<LoginForm onSubmit={mockSubmit} />);

  await user.type(screen.getByLabelText(/email/i), 'user@example.com');
  await user.type(screen.getByLabelText(/password/i), 'secret123');
  await user.click(screen.getByRole('button', { name: /log in/i }));

  expect(mockSubmit).toHaveBeenCalledWith({
    email: 'user@example.com',
    password: 'secret123',
  });
});

// BAD — fires only a single synthetic event, misses focus/blur side effects
fireEvent.click(screen.getByRole('button', { name: /log in/i }));
```

Use `fireEvent` only in rare cases where `userEvent` cannot simulate the event (e.g., native drag-and-drop).

---

## Async Testing

```tsx
import { render, screen, waitFor } from '../test/utils';

// waitFor — poll until assertion passes or timeout
it('should show error message on failed login', async () => {
  render(<LoginForm />);
  await user.click(screen.getByRole('button', { name: /log in/i }));

  await waitFor(() => {
    expect(screen.getByRole('alert')).toHaveTextContent(/invalid credentials/i);
  });
});

// findBy* — shorthand for waitFor + getBy (returns a promise)
it('should display fetched user name', async () => {
  render(<UserProfile userId="1" />);
  const heading = await screen.findByRole('heading', { name: /jane doe/i });
  expect(heading).toBeInTheDocument();
});

// waitForElementToBeRemoved — wait for something to disappear
it('should hide the spinner after loading', async () => {
  render(<DataTable />);
  await waitForElementToBeRemoved(() => screen.queryByRole('progressbar'));
  expect(screen.getByRole('table')).toBeInTheDocument();
});
```

---

## MSW Setup

MSW intercepts requests at the network layer. Define handlers per endpoint, set up a server, and reset between tests.

```ts
// src/test/handlers.ts
import { http, HttpResponse } from 'msw';

export const handlers = [
  http.get('/api/users/:id', ({ params }) => {
    return HttpResponse.json({
      id: params.id,
      name: 'Jane Doe',
      email: 'jane@example.com',
    });
  }),

  http.post('/api/auth/login', async ({ request }) => {
    const body = await request.json() as { email: string; password: string };
    if (body.password === 'wrong') {
      return HttpResponse.json(
        { message: 'Invalid credentials' },
        { status: 401 }
      );
    }
    return HttpResponse.json({ token: 'abc123' });
  }),
];
```

```ts
// src/test/server.ts
import { setupServer } from 'msw/node';
import { handlers } from './handlers';

export const server = setupServer(...handlers);
```

Override handlers in specific tests to test error states:

```tsx
import { http, HttpResponse } from 'msw';
import { server } from '../test/server';

it('should show error state when API fails', async () => {
  server.use(
    http.get('/api/users/:id', () => {
      return HttpResponse.json({ message: 'Server error' }, { status: 500 });
    })
  );

  render(<UserProfile userId="1" />);
  const error = await screen.findByRole('alert');
  expect(error).toHaveTextContent(/something went wrong/i);
});
```

---

## Testing Custom Hooks

Use `renderHook` from `@testing-library/react` to test hooks in isolation.

```tsx
import { renderHook, act } from '@testing-library/react';
import { useCounter } from './useCounter';

it('should increment the counter', () => {
  const { result } = renderHook(() => useCounter(0));

  act(() => {
    result.current.increment();
  });

  expect(result.current.count).toBe(1);
});

// For hooks that need providers
it('should fetch user data', async () => {
  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={createTestQueryClient()}>
      {children}
    </QueryClientProvider>
  );

  const { result } = renderHook(() => useUser('1'), { wrapper });

  await waitFor(() => {
    expect(result.current.isSuccess).toBe(true);
  });

  expect(result.current.data?.name).toBe('Jane Doe');
});
```

---

## Testing Forms

```tsx
it('should validate required fields and display errors', async () => {
  const user = userEvent.setup();
  const onSubmit = vi.fn();
  render(<RegistrationForm onSubmit={onSubmit} />);

  // Submit without filling fields
  await user.click(screen.getByRole('button', { name: /register/i }));

  expect(await screen.findByText(/email is required/i)).toBeInTheDocument();
  expect(screen.getByText(/password is required/i)).toBeInTheDocument();
  expect(onSubmit).not.toHaveBeenCalled();
});

it('should submit valid form data', async () => {
  const user = userEvent.setup();
  const onSubmit = vi.fn();
  render(<RegistrationForm onSubmit={onSubmit} />);

  await user.type(screen.getByLabelText(/email/i), 'user@example.com');
  await user.type(screen.getByLabelText(/password/i), 'SecurePass1!');
  await user.click(screen.getByRole('button', { name: /register/i }));

  await waitFor(() => {
    expect(onSubmit).toHaveBeenCalledWith({
      email: 'user@example.com',
      password: 'SecurePass1!',
    });
  });
});
```

---

## Testing with TanStack Query

Always disable retries and set `gcTime: Infinity` in test QueryClient instances to prevent flaky tests.

```tsx
// Already covered in custom render utility.
// For tests that need to pre-populate the cache:

it('should display cached user data', async () => {
  const queryClient = createTestQueryClient();
  queryClient.setQueryData(['user', '1'], {
    id: '1',
    name: 'Jane Doe',
  });

  render(
    <QueryClientProvider client={queryClient}>
      <UserProfile userId="1" />
    </QueryClientProvider>
  );

  expect(screen.getByRole('heading', { name: /jane doe/i })).toBeInTheDocument();
});
```

---

## Mocking Modules

```tsx
// Mock an entire module
vi.mock('../services/analytics', () => ({
  trackEvent: vi.fn(),
}));

// Mock with factory for named exports
vi.mock('../hooks/useAuth', () => ({
  useAuth: vi.fn(() => ({
    user: { id: '1', name: 'Jane' },
    isAuthenticated: true,
  })),
}));

// Reset mocks between tests
afterEach(() => {
  vi.clearAllMocks();
});

// Change mock implementation per test
import { useAuth } from '../hooks/useAuth';
it('should redirect unauthenticated users', () => {
  vi.mocked(useAuth).mockReturnValue({ user: null, isAuthenticated: false });
  render(<ProtectedRoute />);
  expect(screen.getByText(/please log in/i)).toBeInTheDocument();
});
```

---

## Snapshot Testing

Use sparingly. Snapshots break on any UI change — intentional or not — and create maintenance burden.

DO use snapshots for:
- Pure, stable UI components that rarely change
- Components where you want to detect unintended visual regressions

DON'T use snapshots for:
- Components with complex logic
- Components that embed dates, IDs, or random values
- As a substitute for behavioral assertions

```tsx
// Acceptable snapshot test
it('should match snapshot for Badge component', () => {
  const { container } = render(<Badge variant="success">Active</Badge>);
  expect(container.firstChild).toMatchSnapshot();
});
```

Prefer inline snapshots (`toMatchInlineSnapshot`) so the expected value is visible in the test file.

---

## Test File Location

Co-locate test files with the component they test.

```
src/
  components/
    UserProfile/
      UserProfile.tsx
      UserProfile.test.tsx      <- co-located
      UserProfile.stories.tsx
      index.ts
  hooks/
    useCounter.ts
    useCounter.test.ts          <- co-located
```

---

## Test Naming

Use `describe` + `it('should...')` pattern for clarity.

```tsx
describe('LoginForm', () => {
  it('should render email and password fields', () => { ... });
  it('should show validation errors when submitted empty', async () => { ... });
  it('should call onSuccess when credentials are valid', async () => { ... });
  it('should disable the submit button while submitting', async () => { ... });
});
```

---

## Coverage Configuration

```ts
// vitest.config.ts — coverage section
coverage: {
  provider: 'v8',
  reporter: ['text', 'lcov', 'html'],
  thresholds: {
    lines: 80,
    functions: 80,
    branches: 80,
  },
  exclude: [
    '**/*.stories.{ts,tsx}',
    '**/*.types.{ts,tsx}',
    '**/index.ts',
    '**/index.tsx',
    'src/test/**',
    'src/mocks/**',
    '**/*.d.ts',
    'vite.config.ts',
    'vitest.config.ts',
  ],
},
```
