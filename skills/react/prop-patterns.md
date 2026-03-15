# React Prop Patterns

## The Prop Drilling Problem

Prop drilling occurs when a prop is passed through intermediate components that do not use it, solely to deliver it to a deeply nested child. Passing props 3 or more levels deep is a code smell and should trigger a refactoring decision.

```tsx
// BAD — theme is passed through every level but only used at the bottom
function App() {
  const [theme, setTheme] = useState('light');
  return <Dashboard theme={theme} />;
}

function Dashboard({ theme }) {
  return <Sidebar theme={theme} />;
}

function Sidebar({ theme }) {
  return <SidebarItem theme={theme} />;
}

function SidebarItem({ theme }) {
  return <div className={theme}>Item</div>; // only level that uses it
}
```

### Solutions — Ranked by Preference

1. **Component composition** — restructure the component tree to avoid passing the prop through intermediaries.
2. **Context API** — for static or slow-changing values (theme, locale, auth).
3. **Zustand** — for dynamic global state.
4. **URL state** — for filters, pagination, and navigation-related state.

---

## Component Composition to Eliminate Drilling

The most powerful and underused technique. Pass components as children or as props instead of data.

**DO: Use `children` to avoid passing data through intermediaries.**

```tsx
// GOOD — Dashboard does not need to know what Sidebar renders
function App() {
  const theme = useTheme();
  return (
    <Dashboard>
      <Sidebar>
        <SidebarItem theme={theme} />
      </Sidebar>
    </Dashboard>
  );
}

function Dashboard({ children }: { children: React.ReactNode }) {
  return <div className="dashboard">{children}</div>;
}

function Sidebar({ children }: { children: React.ReactNode }) {
  return <nav className="sidebar">{children}</nav>;
}
```

### Slot Pattern

Use named prop slots to inject content into specific positions of a layout component.

```tsx
interface PageLayoutProps {
  header: React.ReactNode;
  sidebar: React.ReactNode;
  footer?: React.ReactNode;
  children: React.ReactNode;
}

function PageLayout({ header, sidebar, footer, children }: PageLayoutProps) {
  return (
    <div className="layout">
      <header>{header}</header>
      <aside>{sidebar}</aside>
      <main>{children}</main>
      {footer && <footer>{footer}</footer>}
    </div>
  );
}

// Usage — caller decides what goes in each slot, no drilling needed
function DashboardPage() {
  return (
    <PageLayout
      header={<DashboardHeader />}
      sidebar={<DashboardNav />}
      footer={<Footer />}
    >
      <DashboardContent />
    </PageLayout>
  );
}
```

---

## Render Props Pattern

Pass a function as a prop that returns JSX. Useful when a parent component controls state that its children need to render against.

```tsx
interface DataLoaderProps<T> {
  url: string;
  render: (data: T, isLoading: boolean) => React.ReactNode;
}

function DataLoader<T>({ url, render }: DataLoaderProps<T>) {
  const { data, isLoading } = useQuery({ queryKey: [url], queryFn: () => fetch(url).then(r => r.json()) });
  return <>{render(data as T, isLoading)}</>;
}

// Usage
<DataLoader<User[]>
  url="/api/users"
  render={(users, isLoading) =>
    isLoading ? <Spinner /> : <UserList users={users} />
  }
/>
```

Render props are less common since hooks became available, but remain valid for compound components and library-style APIs.

---

## Prop Naming Conventions

### Boolean Props — Use `is`, `has`, or `can` Prefix

```tsx
interface ButtonProps {
  isLoading: boolean;     // not: loading
  isDisabled: boolean;    // not: disabled (though native HTML uses disabled)
  hasError: boolean;      // not: error
  canEdit: boolean;       // not: editable
}
```

**DON'T: Use ambiguous names that could be boolean or string.**

```tsx
// BAD — is 'error' a boolean flag or an error message string?
interface InputProps {
  error?: boolean | string;
}

// GOOD — separate concerns
interface InputProps {
  hasError?: boolean;
  errorMessage?: string;
}
```

### Handler Props — Use `on` Prefix

```tsx
interface TableRowProps {
  onSelect: (id: string) => void;
  onDelete: (id: string) => void;
  onEdit: (id: string) => void;
}
```

**DON'T: Name handlers with verbs or inconsistent prefixes.**

```tsx
// BAD
interface TableRowProps {
  selectRow: (id: string) => void;      // should be onSelectRow
  handleDelete: (id: string) => void;   // should be onDelete
}
```

### Render Prop Naming — Use `render` or `renderXxx` Prefix

```tsx
interface ListProps<T> {
  items: T[];
  renderItem: (item: T) => React.ReactNode;
  renderEmpty?: () => React.ReactNode;
}
```

---

## Required vs Optional Props

Use TypeScript to enforce required props. Never use PropTypes in TypeScript projects.

```tsx
interface CardProps {
  // Required — no default, must be provided
  title: string;
  children: React.ReactNode;

  // Optional — has a default value
  variant?: 'default' | 'outlined' | 'elevated';
  isFullWidth?: boolean;
  onClose?: () => void;
}

function Card({
  title,
  children,
  variant = 'default',
  isFullWidth = false,
  onClose,
}: CardProps) {
  return (
    <div className={`card card--${variant} ${isFullWidth ? 'card--full-width' : ''}`}>
      <div className="card__header">
        <h2>{title}</h2>
        {onClose && <button onClick={onClose}>×</button>}
      </div>
      <div className="card__body">{children}</div>
    </div>
  );
}
```

**DON'T: Use PropTypes in a TypeScript codebase.**

```tsx
// BAD — redundant when TypeScript is used
Card.propTypes = {
  title: PropTypes.string.isRequired,
  variant: PropTypes.oneOf(['default', 'outlined', 'elevated']),
};
```

---

## Avoid Too Many Props

When a component has more than 7-8 props, it is a signal that:
1. The component is doing too much and should be split.
2. Related props should be grouped into an object prop.

**DO: Group related props into a typed object.**

```tsx
// BAD — 10 individual props
interface UserCardProps {
  firstName: string;
  lastName: string;
  email: string;
  avatarUrl: string;
  role: string;
  department: string;
  isActive: boolean;
  joinDate: string;
  onEdit: (id: string) => void;
  onDeactivate: (id: string) => void;
}

// GOOD — grouped into a user object
interface UserCardProps {
  user: {
    id: string;
    firstName: string;
    lastName: string;
    email: string;
    avatarUrl: string;
    role: string;
    department: string;
    isActive: boolean;
    joinDate: string;
  };
  onEdit: (id: string) => void;
  onDeactivate: (id: string) => void;
}
```

---

## Avoid Passing Entire Objects When Only One Field Is Needed

If a component only uses one or two fields from an object, pass those fields individually. This improves reusability and testability.

```tsx
// BAD — Badge is tightly coupled to the User type
function UserBadge({ user }: { user: User }) {
  return <span className={`badge badge--${user.role}`}>{user.name}</span>;
}

// GOOD — Badge is generic and reusable
function Badge({ label, variant }: { label: string; variant: string }) {
  return <span className={`badge badge--${variant}`}>{label}</span>;
}

// Caller maps User to Badge props
<Badge label={user.name} variant={user.role} />
```

---

## Prop Spreading Rules

**DO: Spread rest props onto native HTML elements in wrapper components.** This is the standard pattern for flexible utility components.

```tsx
interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  isLoading?: boolean;
  variant?: 'primary' | 'secondary' | 'ghost';
}

function Button({ isLoading, variant = 'primary', children, className, ...rest }: ButtonProps) {
  return (
    <button
      className={`btn btn--${variant} ${className ?? ''}`}
      disabled={isLoading || rest.disabled}
      {...rest}
    >
      {isLoading ? <Spinner size="sm" /> : children}
    </button>
  );
}
```

**DON'T: Spread props onto custom components without documenting what is expected.** Spreading onto a component that has many props makes it impossible to know what is accepted.

```tsx
// BAD — unclear which props UserCard accepts from ...rest
function UserCard({ user, ...rest }: UserCardProps) {
  return <ComplexComponent user={user} {...rest} />; // what does rest contain?
}
```

### Forwarding Props with Rest/Spread

```tsx
interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label: string;
  hasError?: boolean;
  errorMessage?: string;
}

function Input({ label, hasError, errorMessage, id, className, ...inputProps }: InputProps) {
  const inputId = id ?? label.toLowerCase().replace(/\s+/g, '-');

  return (
    <div className="input-group">
      <label htmlFor={inputId}>{label}</label>
      <input
        id={inputId}
        className={`input ${hasError ? 'input--error' : ''} ${className ?? ''}`}
        aria-invalid={hasError}
        aria-describedby={hasError ? `${inputId}-error` : undefined}
        {...inputProps}
      />
      {hasError && errorMessage && (
        <span id={`${inputId}-error`} role="alert">
          {errorMessage}
        </span>
      )}
    </div>
  );
}
```

---

## Callback Prop Performance

Wrap callback props in `useCallback` when passing them to memoized child components. Without this, the child re-renders every time the parent renders, even if the callback logic has not changed.

**DO: Use `useCallback` for handlers passed to `React.memo` children.**

```tsx
function ProductList({ categoryId }: { categoryId: string }) {
  const [selectedId, setSelectedId] = useState<string | null>(null);

  // Stable reference — ProductCard will not re-render unless selectedId or categoryId changes
  const handleSelect = useCallback((id: string) => {
    setSelectedId(id);
  }, []); // no dependencies — setSelectedId is always stable

  const handleAddToCart = useCallback(
    (id: string) => {
      cartService.add(id, categoryId);
    },
    [categoryId], // re-create when categoryId changes
  );

  return (
    <div>
      {products.map(product => (
        <ProductCard
          key={product.id}
          product={product}
          isSelected={product.id === selectedId}
          onSelect={handleSelect}
          onAddToCart={handleAddToCart}
        />
      ))}
    </div>
  );
}

const ProductCard = React.memo(function ProductCard({
  product,
  isSelected,
  onSelect,
  onAddToCart,
}: ProductCardProps) {
  return (
    <div onClick={() => onSelect(product.id)}>
      <h3>{product.name}</h3>
      <button onClick={() => onAddToCart(product.id)}>Add to cart</button>
    </div>
  );
});
```

**DON'T: Wrap every callback in `useCallback` indiscriminately.** Only do it when the callback is passed to a memoized component or used in a `useEffect` dependency array.

---

## Interface Segregation for Props

Shared components should not accept props they do not use. If a component only needs some fields from a large type, define a minimal interface.

```tsx
// BAD — Button accepts the entire User type but only needs the name
interface ActionButtonProps {
  user: User; // User has 15 fields
  onClick: () => void;
}

// GOOD — define only what is needed
interface ActionButtonProps {
  label: string;
  onClick: () => void;
  isDisabled?: boolean;
}
```

For components that accept a data object, use TypeScript's `Pick` utility to be explicit about what is required.

```tsx
type UserAvatarProps = Pick<User, 'name' | 'avatarUrl'> & {
  size?: 'sm' | 'md' | 'lg';
};

function UserAvatar({ name, avatarUrl, size = 'md' }: UserAvatarProps) {
  return (
    <img
      src={avatarUrl}
      alt={`${name}'s avatar`}
      className={`avatar avatar--${size}`}
    />
  );
}
```

---

## Default Prop Values

Always define defaults in the destructuring signature, not using `defaultProps` (which is deprecated for function components).

```tsx
// GOOD
function Alert({
  type = 'info',
  isDismissible = false,
  title,
  children,
}: AlertProps) { ... }

// BAD — defaultProps is deprecated
Alert.defaultProps = {
  type: 'info',
  isDismissible: false,
};
```

---

## Full Example: Well-Structured Props

```tsx
// A real-world DataTable component with well-structured props
interface SortConfig {
  key: string;
  direction: 'asc' | 'desc';
}

interface PaginationConfig {
  page: number;
  pageSize: number;
  total: number;
  onPageChange: (page: number) => void;
}

interface DataTableProps<T extends { id: string }> {
  // Data
  data: T[];
  columns: ColumnDef<T>[];

  // State indicators
  isLoading?: boolean;
  isEmpty?: boolean;
  emptyMessage?: string;

  // Sorting
  sortConfig?: SortConfig;
  onSortChange?: (config: SortConfig) => void;

  // Pagination
  pagination?: PaginationConfig;

  // Row actions
  onRowClick?: (row: T) => void;
  renderRowActions?: (row: T) => React.ReactNode;

  // Styling
  className?: string;
}

function DataTable<T extends { id: string }>({
  data,
  columns,
  isLoading = false,
  isEmpty = data.length === 0,
  emptyMessage = 'No results found',
  sortConfig,
  onSortChange,
  pagination,
  onRowClick,
  renderRowActions,
  className,
}: DataTableProps<T>) {
  // implementation...
}
```
