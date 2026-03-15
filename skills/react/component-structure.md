# React Component Structure and Patterns

This document defines how React components must be written and organized. Following these conventions ensures consistency, readability, and predictable rendering behavior across the codebase.

---

## Functional Components Only

Never write class components. Functional components with hooks are the standard.

```tsx
// WRONG — class component
class UserCard extends React.Component<UserCardProps> {
  render() {
    return <div>{this.props.user.name}</div>;
  }
}

// CORRECT — functional component
function UserCard({ user }: UserCardProps) {
  return <div>{user.name}</div>;
}
```

---

## Component File Structure

Every component file must follow this order:

1. External imports (React, third-party libraries)
2. Internal imports (components, hooks, utils, types)
3. Type/interface definitions for this component
4. The component function
5. `export default` at the bottom (or named export — be consistent per project)

```tsx
// 1. External imports
import { useState, useCallback } from 'react';
import { Link } from 'react-router-dom';

// 2. Internal imports
import { Avatar } from '@/components/Avatar';
import { Badge } from '@/components/Badge';
import { useUserPermissions } from '@/features/auth';
import { formatDate } from '@/utils/formatDate';
import type { User } from '@/types';

// 3. Types/interfaces for this component
interface UserCardProps {
  user: User;
  showActions?: boolean;
  onEdit: (userId: string) => void;
  onDelete: (userId: string) => void;
}

// 4. Component function
function UserCard({ user, showActions = true, onEdit, onDelete }: UserCardProps) {
  const [isExpanded, setIsExpanded] = useState(false);
  const { canEdit, canDelete } = useUserPermissions(user.id);

  const handleEdit = useCallback(() => onEdit(user.id), [onEdit, user.id]);
  const handleDelete = useCallback(() => onDelete(user.id), [onDelete, user.id]);

  return (
    <div className="user-card">
      <Avatar src={user.avatar} alt={user.name} />
      <div className="user-card__info">
        <Link to={`/users/${user.id}`}>{user.name}</Link>
        <span>{formatDate(user.createdAt)}</span>
        <Badge label={user.role} />
      </div>
      {showActions && (
        <div className="user-card__actions">
          {canEdit && <button onClick={handleEdit}>Edit</button>}
          {canDelete && <button onClick={handleDelete}>Delete</button>}
        </div>
      )}
    </div>
  );
}

// 5. Export
export { UserCard };
export type { UserCardProps };
```

---

## Props Destructuring

Always destructure props in the function signature, not inside the function body.

```tsx
// WRONG — destructuring inside body
function Button(props: ButtonProps) {
  const { label, variant, onClick } = props;
  return <button onClick={onClick}>{label}</button>;
}

// CORRECT — destructuring in signature
function Button({ label, variant = 'primary', onClick }: ButtonProps) {
  return <button onClick={onClick}>{label}</button>;
}
```

---

## Default Props

Use default parameter values in the function signature. Never use the deprecated `defaultProps` static property.

```tsx
// WRONG — deprecated defaultProps
function Avatar({ src, size }: AvatarProps) {
  return <img src={src} width={size} height={size} />;
}
Avatar.defaultProps = { size: 40 };

// CORRECT — default values in signature
function Avatar({ src, size = 40, alt = '' }: AvatarProps) {
  return <img src={src} width={size} height={size} alt={alt} />;
}
```

---

## Single Responsibility and Size Limits

A component should do one thing. If it manages form state, validates inputs, fetches data, AND handles layout — it is doing too much.

**Maximum component size: 200 lines.** If a component exceeds this, it must be split.

```tsx
// Signal to split: one component doing too much
function UserManagementPage() {
  // 50 lines of filter state
  // 30 lines of pagination logic
  // 40 lines of table rendering
  // 30 lines of delete confirmation modal
  // 50 lines of edit form modal
  // Total: 200+ lines — SPLIT THIS
}

// After splitting
function UserManagementPage() {
  return (
    <div>
      <UserFilters />          // owns filter state
      <UserTable />            // owns table rendering
      <UserPagination />       // owns pagination
      <DeleteUserModal />      // owns delete confirmation
    </div>
  );
}
```

---

## Presentational vs Container Components

**Presentational components:**
- Render UI based on props
- Have no knowledge of the data source (API, store)
- Are easy to test and reuse

**Container components (or page-level components):**
- Fetch data and manage state
- Pass data down to presentational components
- Are not reusable — they are wired to a specific feature

```tsx
// Presentational — receives data via props, renders UI
interface UserTableProps {
  users: User[];
  isLoading: boolean;
  onEdit: (id: string) => void;
  onDelete: (id: string) => void;
}

function UserTable({ users, isLoading, onEdit, onDelete }: UserTableProps) {
  if (isLoading) return <Spinner />;
  return (
    <table>
      {users.map((user) => (
        <UserRow key={user.id} user={user} onEdit={onEdit} onDelete={onDelete} />
      ))}
    </table>
  );
}

// Container — fetches data, wires up actions
function UsersContainer() {
  const { users, isLoading } = useUsers();
  const { mutate: deleteUser } = useDeleteUser();
  const navigate = useNavigate();

  return (
    <UserTable
      users={users}
      isLoading={isLoading}
      onEdit={(id) => navigate(`/users/${id}/edit`)}
      onDelete={(id) => deleteUser(id)}
    />
  );
}
```

---

## Never Define Components Inside Other Components

Defining a component inside another component causes it to be re-created on every render, forcing React to remount (not re-render) it, which destroys its DOM node and resets state.

```tsx
// WRONG — Inner is redefined every time Outer renders
function Outer() {
  const Inner = () => <p>Hello</p>; // new function identity every render = remount
  return <Inner />;
}

// CORRECT — define at module level
function Inner() {
  return <p>Hello</p>;
}

function Outer() {
  return <Inner />;
}

// CORRECT — if Inner needs Outer's data, pass it as props
function Inner({ message }: { message: string }) {
  return <p>{message}</p>;
}

function Outer() {
  const [message] = useState('Hello');
  return <Inner message={message} />;
}
```

---

## Compound Component Pattern

Use compound components when a component has multiple related sub-components that share implicit state.

```tsx
// Card compound component
interface CardContextValue {
  isCollapsed: boolean;
  toggleCollapse: () => void;
}

const CardContext = createContext<CardContextValue | null>(null);

function useCardContext(): CardContextValue {
  const ctx = useContext(CardContext);
  if (!ctx) throw new Error('Card sub-components must be used within <Card>');
  return ctx;
}

function Card({ children }: { children: React.ReactNode }) {
  const [isCollapsed, setIsCollapsed] = useState(false);
  const toggleCollapse = () => setIsCollapsed((prev) => !prev);
  return (
    <CardContext.Provider value={{ isCollapsed, toggleCollapse }}>
      <div className="card">{children}</div>
    </CardContext.Provider>
  );
}

function CardHeader({ children }: { children: React.ReactNode }) {
  const { toggleCollapse } = useCardContext();
  return (
    <div className="card__header" onClick={toggleCollapse}>
      {children}
    </div>
  );
}

function CardBody({ children }: { children: React.ReactNode }) {
  const { isCollapsed } = useCardContext();
  if (isCollapsed) return null;
  return <div className="card__body">{children}</div>;
}

Card.Header = CardHeader;
Card.Body = CardBody;

// Usage
<Card>
  <Card.Header>Title</Card.Header>
  <Card.Body>Content</Card.Body>
</Card>
```

---

## Controlled vs Uncontrolled Components

**Controlled:** React state is the single source of truth. Always prefer this.

```tsx
function ControlledInput({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <input
      value={value}
      onChange={(e) => onChange(e.target.value)}
    />
  );
}
```

**Uncontrolled:** The DOM holds state. Use only when integrating with non-React libraries or when performance demands it (e.g., file inputs).

```tsx
function FileUpload({ onFileSelect }: { onFileSelect: (file: File) => void }) {
  const inputRef = useRef<HTMLInputElement>(null);

  const handleChange = () => {
    const file = inputRef.current?.files?.[0];
    if (file) onFileSelect(file);
  };

  return <input ref={inputRef} type="file" onChange={handleChange} />;
}
```

---

## `forwardRef` Pattern

Use `React.forwardRef` when a component needs to expose a DOM ref to its parent. Common for form elements and modals.

```tsx
interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label: string;
  error?: string;
}

const Input = React.forwardRef<HTMLInputElement, InputProps>(
  function Input({ label, error, ...rest }, ref) {
    const id = useId();
    return (
      <div className="input-wrapper">
        <label htmlFor={id}>{label}</label>
        <input ref={ref} id={id} aria-invalid={!!error} {...rest} />
        {error && <span className="input-error">{error}</span>}
      </div>
    );
  },
);

Input.displayName = 'Input';

// Usage — parent can focus the input
function LoginForm() {
  const emailRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    emailRef.current?.focus();
  }, []);

  return <Input ref={emailRef} label="Email" type="email" />;
}
```

Always set `displayName` on forwardRef components for clear DevTools debugging.

---

## `React.memo` — When to Use and When NOT To

`React.memo` prevents a component from re-rendering if its props have not changed (shallow comparison).

**Use React.memo when:**
- The component renders frequently due to parent re-renders
- The component is expensive to render (large lists, complex calculations)
- The props are stable (primitives or memoized objects/functions)

**Do NOT use React.memo when:**
- Props change on almost every render anyway (memoization adds overhead)
- The component is fast/cheap to render (premature optimization)
- Props are objects or functions that are not memoized (memo will never bail out)

```tsx
// CORRECT — memo makes sense: UserRow is in a large list and renders frequently
const UserRow = React.memo(function UserRow({ user, onEdit, onDelete }: UserRowProps) {
  return (
    <tr>
      <td>{user.name}</td>
      <td><button onClick={() => onEdit(user.id)}>Edit</button></td>
      <td><button onClick={() => onDelete(user.id)}>Delete</button></td>
    </tr>
  );
});

// Parent must pass stable callbacks for memo to actually help
function UserTable({ users }: { users: User[] }) {
  const handleEdit = useCallback((id: string) => navigate(`/users/${id}/edit`), [navigate]);
  const handleDelete = useCallback((id: string) => deleteUser(id), [deleteUser]);

  return (
    <table>
      {users.map((user) => (
        <UserRow key={user.id} user={user} onEdit={handleEdit} onDelete={handleDelete} />
      ))}
    </table>
  );
}
```

---

## `key` Prop Rules

The `key` prop helps React identify which items have changed in a list. Use stable, unique identifiers.

```tsx
// WRONG — index as key: causes state bugs when items are added/removed/reordered
{users.map((user, index) => (
  <UserCard key={index} user={user} />
))}

// WRONG — unstable key: generates new key every render, forces remount
{users.map((user) => (
  <UserCard key={Math.random()} user={user} />
))}

// CORRECT — stable unique ID from data
{users.map((user) => (
  <UserCard key={user.id} user={user} />
))}

// Index is acceptable ONLY for static, non-reorderable lists
{STATIC_MENU_ITEMS.map((item, index) => (
  <MenuItem key={index} item={item} /> // OK — list never changes
))}
```

---

## Fragments

Use shorthand `<>` for fragments that do not need keys. Use `<React.Fragment key={}>` when a key is required (e.g., in a map).

```tsx
// CORRECT — shorthand fragment
function UserInfo({ user }: { user: User }) {
  return (
    <>
      <dt>Name</dt>
      <dd>{user.name}</dd>
    </>
  );
}

// CORRECT — keyed fragment in a list
function DefinitionList({ items }: { items: Array<{ term: string; definition: string }> }) {
  return (
    <dl>
      {items.map((item) => (
        <React.Fragment key={item.term}>
          <dt>{item.term}</dt>
          <dd>{item.definition}</dd>
        </React.Fragment>
      ))}
    </dl>
  );
}
```

---

## Conditional Rendering Patterns

```tsx
// Short-circuit (&&) — renders right side when left is truthy
// WARNING: if left side is 0 or NaN, it renders that number in the DOM
{users.length > 0 && <UserList users={users} />}

// SAFER short-circuit with explicit boolean
{users.length > 0 && <UserList users={users} />}  // Fine: number > 0 is boolean
{!!users.length && <UserList users={users} />}     // Also fine

// Ternary — for if/else
{isLoading ? <Spinner /> : <UserList users={users} />}

// Early return — preferred for guard clauses
function UserPage({ userId }: { userId: string | null }) {
  if (!userId) return <p>No user selected</p>;
  if (isLoading) return <Spinner />;
  if (error) return <ErrorMessage error={error} />;

  return <UserDetails user={user} />;
}

// Extracted variable — for complex conditions
function Dashboard() {
  const mainContent = (() => {
    if (isLoading) return <Spinner />;
    if (error) return <ErrorMessage error={error} />;
    if (!data) return <EmptyState />;
    return <DataGrid data={data} />;
  })();

  return (
    <div>
      <Header />
      {mainContent}
    </div>
  );
}
```

---

## Event Handler Naming Convention

All event handler functions must be named `handleXxx`:
- `handleClick`
- `handleSubmit`
- `handleChange`
- `handleKeyDown`
- `handleDelete`

Props that accept event handlers must be named `onXxx`:
- `onClick`
- `onSubmit`
- `onChange`
- `onDelete`

```tsx
interface UserCardProps {
  onEdit: (id: string) => void;   // prop name: onEdit
  onDelete: (id: string) => void; // prop name: onDelete
}

function UserCard({ user, onEdit, onDelete }: UserCardProps) {
  // handler name: handleEdit
  const handleEdit = () => onEdit(user.id);
  const handleDelete = () => onDelete(user.id);

  return (
    <div>
      <button onClick={handleEdit}>Edit</button>
      <button onClick={handleDelete}>Delete</button>
    </div>
  );
}
```

---

## Avoid Inline Functions in JSX for Frequently Rendered Components

Inline arrow functions in JSX create new function references on every render. In a large list, this forces every row to re-render even with `React.memo`.

```tsx
// WRONG — new function reference on every render
{users.map((user) => (
  <UserRow
    key={user.id}
    user={user}
    onDelete={() => handleDelete(user.id)} // new reference each render
  />
))}

// CORRECT — stable callback + pass the id separately, or use useCallback
const handleDelete = useCallback((id: string) => { deleteUser(id); }, [deleteUser]);

{users.map((user) => (
  <UserRow
    key={user.id}
    user={user}
    onDelete={handleDelete} // stable reference; UserRow calls it with user.id
  />
))}
```

For simple, non-memoized components rendering small lists, inline functions are acceptable — avoid premature optimization.

---

## Error Boundaries

Class components are acceptable for Error Boundaries (it is the one case where class components are still required). Wrap error boundaries at appropriate granularity — not around every component.

```tsx
// components/ErrorBoundary/ErrorBoundary.tsx
interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
}

interface ErrorBoundaryProps {
  children: React.ReactNode;
  fallback?: React.ReactNode | ((error: Error) => React.ReactNode);
}

class ErrorBoundary extends React.Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo): void {
    console.error('ErrorBoundary caught:', error, info.componentStack);
    // Send to error monitoring service (e.g., Sentry)
  }

  render() {
    if (this.state.hasError && this.state.error) {
      const { fallback } = this.props;
      if (typeof fallback === 'function') return fallback(this.state.error);
      if (fallback) return fallback;
      return (
        <div role="alert">
          <h2>Something went wrong.</h2>
          <details>{this.state.error.message}</details>
        </div>
      );
    }
    return this.props.children;
  }
}

// Usage — wrap at feature level, not every component
function DashboardPage() {
  return (
    <ErrorBoundary fallback={<p>Dashboard failed to load. Please refresh.</p>}>
      <DashboardMetrics />
      <DashboardCharts />
    </ErrorBoundary>
  );
}
```

Alternatively, use a library like `react-error-boundary` for a hook-friendly API.
