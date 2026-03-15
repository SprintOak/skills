# TypeScript Usage in React Projects

This document defines how TypeScript must be used in React projects. These rules exist to maximize type safety, prevent runtime errors, and ensure the codebase remains refactorable as it grows.

---

## Strict Mode — Non-Negotiable

Always enable strict mode in `tsconfig.json`. This activates the full suite of TypeScript's type checking capabilities.

```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "noImplicitReturns": true,
    "exactOptionalPropertyTypes": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    },
    "outDir": "dist"
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

`"strict": true` enables: `strictNullChecks`, `strictFunctionTypes`, `strictBindCallApply`, `strictPropertyInitialization`, `noImplicitAny`, `noImplicitThis`, `alwaysStrict`.

---

## Never Use `any`

`any` disables the type checker entirely for that value. It is the most dangerous TypeScript escape hatch.

```ts
// WRONG
function processData(data: any) {
  return data.value.trim(); // No type checking, runtime crash risk
}

// CORRECT — use unknown and narrow
function processData(data: unknown): string {
  if (typeof data === 'object' && data !== null && 'value' in data) {
    const value = (data as { value: unknown }).value;
    if (typeof value === 'string') return value.trim();
  }
  throw new Error('Invalid data shape');
}
```

```ts
// WRONG — any from JSON.parse
const parsed: any = JSON.parse(response);

// CORRECT — use a type guard or Zod schema
import { z } from 'zod';

const UserSchema = z.object({ id: z.string(), name: z.string() });
const parsed = UserSchema.parse(JSON.parse(response)); // throws on invalid shape
```

**DO NOT use `any` for:**
- API response types
- Event handler parameters
- Third-party library interop (find the `@types/` package instead)
- "I'll fix this later" placeholders

---

## Interface vs Type Alias

Use **`interface`** for:
- Object shapes (component props, API response shapes, class contracts)
- Anything that may be extended or implemented

Use **`type`** for:
- Union types
- Intersection types
- Primitive aliases
- Tuple types
- Mapped types
- Conditional types

```ts
// CORRECT — interface for object shapes
interface User {
  id: string;
  name: string;
  email: string;
  role: UserRole;
}

interface ButtonProps {
  label: string;
  variant?: 'primary' | 'secondary';
  onClick?: () => void;
}

// CORRECT — type for unions and intersections
type UserRole = 'admin' | 'editor' | 'viewer';
type Status = 'idle' | 'loading' | 'success' | 'error';
type AdminUser = User & { permissions: string[] };
type Nullable<T> = T | null;
```

---

## Component Props — Always Explicit

Every React component must have an explicitly defined props type. Inline prop types in the function signature are discouraged for non-trivial components.

```tsx
// WRONG — no prop types
function UserCard({ user, onClick }) {
  return <div onClick={onClick}>{user.name}</div>;
}

// CORRECT
interface UserCardProps {
  user: User;
  onClick: (userId: string) => void;
  isHighlighted?: boolean;
}

function UserCard({ user, onClick, isHighlighted = false }: UserCardProps) {
  return (
    <div
      className={isHighlighted ? 'highlighted' : ''}
      onClick={() => onClick(user.id)}
    >
      {user.name}
    </div>
  );
}
```

Export prop types from the component file so consumers can reference them:

```ts
// Button/Button.tsx
export interface ButtonProps { ... }
export function Button(props: ButtonProps) { ... }

// Button/index.ts
export { Button } from './Button';
export type { ButtonProps } from './Button';
```

---

## Event Types

Use the correct React event types — never use the raw DOM event types in React components.

```tsx
// Form events
function handleSubmit(event: React.FormEvent<HTMLFormElement>): void {
  event.preventDefault();
  // ...
}

// Input change events
function handleChange(event: React.ChangeEvent<HTMLInputElement>): void {
  setValue(event.target.value);
}

// Select change events
function handleSelectChange(event: React.ChangeEvent<HTMLSelectElement>): void {
  setSelected(event.target.value);
}

// Button click events
function handleClick(event: React.MouseEvent<HTMLButtonElement>): void {
  event.stopPropagation();
}

// Keyboard events
function handleKeyDown(event: React.KeyboardEvent<HTMLInputElement>): void {
  if (event.key === 'Enter') submitForm();
}

// Drag events
function handleDrop(event: React.DragEvent<HTMLDivElement>): void {
  const files = event.dataTransfer.files;
}
```

For reusable event handler props:

```ts
interface InputProps {
  onChange: React.ChangeEventHandler<HTMLInputElement>;
  onBlur: React.FocusEventHandler<HTMLInputElement>;
}
```

---

## Children Prop

Use `React.ReactNode` for children. Never use `React.FC` — it adds implicit children which causes issues and hides intent.

```tsx
// CORRECT
interface CardProps {
  title: string;
  children: React.ReactNode;
}

function Card({ title, children }: CardProps) {
  return (
    <div className="card">
      <h2>{title}</h2>
      <div>{children}</div>
    </div>
  );
}

// WRONG — React.FC adds implicit children type and other pitfalls
const Card: React.FC<CardProps> = ({ title, children }) => { ... };
```

For components that accept specific child types only, use more specific types:

```ts
interface TabsProps {
  children: React.ReactElement<TabProps> | React.ReactElement<TabProps>[];
}
```

---

## `useRef` Typing

Always provide the element type and initialize with `null`.

```tsx
// CORRECT
const inputRef = useRef<HTMLInputElement>(null);
const divRef = useRef<HTMLDivElement>(null);
const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

// Access the ref — always check for null
function focusInput() {
  inputRef.current?.focus();
}

// WRONG — untyped ref
const inputRef = useRef(null); // type is MutableRefObject<null>, current is always null
```

When using `useRef` for a mutable value (not a DOM element):

```ts
// For mutable values that don't trigger re-render
const countRef = useRef<number>(0);
countRef.current += 1; // no null check needed for non-DOM refs initialized with a value
```

---

## `useState` Typing

TypeScript can infer simple state types. Provide explicit types when the initial value is `null`, `undefined`, or an empty array.

```ts
// Inference is sufficient for primitive initial values
const [count, setCount] = useState(0);
const [name, setName] = useState('');
const [isOpen, setIsOpen] = useState(false);

// MUST provide explicit type when initial value is null/undefined
const [user, setUser] = useState<User | null>(null);
const [error, setError] = useState<Error | null>(null);

// MUST provide explicit type for empty arrays
const [users, setUsers] = useState<User[]>([]);
const [selectedIds, setSelectedIds] = useState<string[]>([]);

// Complex state with union
const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');
```

---

## Generic Components and Hooks

Write generic components and hooks when the logic is identical but the data type varies.

```tsx
// Generic component
interface ListProps<T> {
  items: T[];
  renderItem: (item: T, index: number) => React.ReactNode;
  keyExtractor: (item: T) => string;
  emptyMessage?: string;
}

function List<T>({ items, renderItem, keyExtractor, emptyMessage = 'No items' }: ListProps<T>) {
  if (items.length === 0) return <p>{emptyMessage}</p>;
  return (
    <ul>
      {items.map((item, index) => (
        <li key={keyExtractor(item)}>{renderItem(item, index)}</li>
      ))}
    </ul>
  );
}

// Usage
<List<User>
  items={users}
  renderItem={(user) => <UserCard user={user} />}
  keyExtractor={(user) => user.id}
/>
```

```ts
// Generic custom hook
function useLocalStorage<T>(key: string, initialValue: T): [T, (value: T) => void] {
  const [storedValue, setStoredValue] = useState<T>(() => {
    try {
      const item = localStorage.getItem(key);
      return item ? (JSON.parse(item) as T) : initialValue;
    } catch {
      return initialValue;
    }
  });

  const setValue = (value: T) => {
    setStoredValue(value);
    localStorage.setItem(key, JSON.stringify(value));
  };

  return [storedValue, setValue];
}
```

---

## Utility Types

Use TypeScript's built-in utility types to avoid redundant type definitions.

```ts
interface User {
  id: string;
  name: string;
  email: string;
  role: 'admin' | 'viewer';
  createdAt: string;
}

// Partial — all properties optional (useful for update payloads)
type UserUpdatePayload = Partial<User>;

// Required — all properties required (remove optionals)
type RequiredConfig = Required<AppConfig>;

// Pick — select specific properties
type UserSummary = Pick<User, 'id' | 'name'>;

// Omit — exclude specific properties
type CreateUserPayload = Omit<User, 'id' | 'createdAt'>;

// Record — key-value map
type RolePermissions = Record<User['role'], string[]>;

// Readonly — prevent mutation
type ImmutableUser = Readonly<User>;

// ReturnType — infer function return type
type AuthHookReturn = ReturnType<typeof useAuth>;

// Parameters — infer function parameter types
type FetchUsersParams = Parameters<typeof fetchUsers>[0];
```

---

## API Response Types

Define all API response shapes in `src/types/` or `features/<name>/types/`. Never use `any` for API data.

```ts
// types/api.types.ts
export interface ApiResponse<T> {
  data: T;
  message: string;
  success: boolean;
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    total: number;
    page: number;
    pageSize: number;
    totalPages: number;
  };
}

// features/users/types/user.types.ts
export interface User {
  id: string;
  name: string;
  email: string;
  role: UserRole;
  avatar: string | null;
  createdAt: string;
}

export type UserRole = 'admin' | 'editor' | 'viewer';

export interface CreateUserDto {
  name: string;
  email: string;
  role: UserRole;
}

export interface UpdateUserDto extends Partial<CreateUserDto> {}
```

---

## Enums — Prefer Union Types

Prefer string literal union types over TypeScript `enum`. Enums have several footguns (numeric enums are unsafe, string enums are verbose, `const enum` can cause issues with isolatedModules).

```ts
// WRONG — numeric enum (unsafe: Role.Admin === 0 is not self-documenting)
enum Role {
  Admin,
  Editor,
  Viewer,
}

// AVOID — regular string enum
enum Status {
  Idle = 'idle',
  Loading = 'loading',
  Success = 'success',
}

// CORRECT — union type (preferred)
type Status = 'idle' | 'loading' | 'success' | 'error';
type Role = 'admin' | 'editor' | 'viewer';

// CORRECT — const object when you need an enum-like value map
const STATUS = {
  IDLE: 'idle',
  LOADING: 'loading',
  SUCCESS: 'success',
  ERROR: 'error',
} as const;

type Status = (typeof STATUS)[keyof typeof STATUS]; // 'idle' | 'loading' | 'success' | 'error'
```

---

## Type Guards and Narrowing

Write explicit type guards for complex narrowing. Use `in`, `typeof`, `instanceof`, and custom type predicates.

```ts
// typeof narrowing
function processValue(value: string | number): string {
  if (typeof value === 'string') return value.toUpperCase();
  return value.toFixed(2);
}

// instanceof narrowing
function handleError(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === 'string') return error;
  return 'An unknown error occurred';
}

// in narrowing
interface Dog { bark(): void; }
interface Cat { meow(): void; }

function speak(animal: Dog | Cat): void {
  if ('bark' in animal) {
    animal.bark();
  } else {
    animal.meow();
  }
}

// Custom type predicate
function isUser(value: unknown): value is User {
  return (
    typeof value === 'object' &&
    value !== null &&
    'id' in value &&
    'email' in value &&
    typeof (value as User).email === 'string'
  );
}
```

---

## `as const` for Literal Types

Use `as const` to narrow inferred types to their literal values.

```ts
// Without as const — type is string[]
const SUPPORTED_LOCALES = ['en', 'es', 'fr'];

// With as const — type is readonly ['en', 'es', 'fr']
const SUPPORTED_LOCALES = ['en', 'es', 'fr'] as const;
type SupportedLocale = (typeof SUPPORTED_LOCALES)[number]; // 'en' | 'es' | 'fr'

// Object with as const
const ROUTES = {
  HOME: '/',
  DASHBOARD: '/dashboard',
} as const;

type Route = (typeof ROUTES)[keyof typeof ROUTES]; // '/' | '/dashboard'
```

---

## Function Return Type Annotations

Annotate return types explicitly for:
- Exported functions
- Non-trivial functions where the return type is not immediately obvious
- Functions returning `void` (to prevent accidental returns)
- Async functions

```ts
// Exported utility — always annotate
export function formatCurrency(amount: number, currency = 'USD'): string {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency }).format(amount);
}

// Async functions — always annotate
async function fetchUser(id: string): Promise<User> {
  const response = await httpClient.get<ApiResponse<User>>(`/users/${id}`);
  return response.data.data;
}

// Event handlers return void — annotate to prevent bugs
function handleSubmit(event: React.FormEvent<HTMLFormElement>): void {
  event.preventDefault();
  submitForm();
}

// Type inference is acceptable for simple, private, obvious cases
const double = (n: number) => n * 2; // return type inferred as number
```

---

## Async Function Return Types

```ts
// Correct async return types
async function getUsers(): Promise<User[]> { ... }
async function createUser(dto: CreateUserDto): Promise<User> { ... }
async function deleteUser(id: string): Promise<void> { ... }

// With ApiResponse wrapper
async function getUserById(id: string): Promise<ApiResponse<User>> {
  const response = await httpClient.get<ApiResponse<User>>(`/users/${id}`);
  return response.data;
}
```

---

## `@ts-ignore` vs `@ts-expect-error`

Never use `@ts-ignore`. It silently suppresses errors even if they no longer exist.

Use `@ts-expect-error` only as an absolute last resort, always with a comment explaining why.

```ts
// WRONG — silently ignores all errors, even if the error is fixed later
// @ts-ignore
const result = legacyFunction(value);

// CORRECT — fails if the error goes away (acts as a test), must include reason
// @ts-expect-error — third-party library missing types for overloaded signature, tracked in issue #123
const result = legacyFunction(value);
```

Before reaching for `@ts-expect-error`, try:
1. Finding or creating a `@types/` package
2. Writing a module declaration in `src/types/declarations.d.ts`
3. Casting through `unknown` if the types are structurally compatible

---

## Path Aliases Configuration

Configure path aliases to eliminate deep relative imports.

```json
// tsconfig.json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    }
  }
}
```

```ts
// vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
});
```

```ts
// WRONG — brittle relative paths
import { useAuth } from '../../../features/auth/hooks/useAuth';

// CORRECT — alias path
import { useAuth } from '@/features/auth';
import { Button } from '@/components/Button';
import { formatDate } from '@/utils/formatDate';
```
