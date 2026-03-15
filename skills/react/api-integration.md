# React API Integration

## Architecture Overview

All API communication follows a layered architecture:

```
Component / Hook
    ↓
TanStack Query (useQuery / useMutation)
    ↓
Service Layer (userService.ts, productService.ts)
    ↓
Axios Instance (api.ts)
    ↓
REST API
```

Never call `fetch` directly in a component. Never call the Axios instance directly from a component. All HTTP calls go through a typed service function, which is consumed by a TanStack Query hook.

---

## Axios Instance Setup

Create a single Axios instance with base configuration. All services import from this instance.

```ts
// lib/api.ts
import axios from 'axios';

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL,
  timeout: 15_000,
  headers: {
    'Content-Type': 'application/json',
  },
});
```

### Environment-Based API URL

```ts
// .env.development
VITE_API_URL=http://localhost:3000/api

// .env.production
VITE_API_URL=https://api.yourapp.com
```

```ts
// Vite exposes these via import.meta.env
const baseURL = import.meta.env.VITE_API_URL;
```

**DON'T: Hardcode base URLs or environment-specific config in source files.**

```ts
// BAD
const api = axios.create({ baseURL: 'https://api.yourapp.com' });
```

---

## Request Interceptor — Attach JWT Token

```ts
// lib/api.ts
import axios from 'axios';
import { useAuthStore } from '@/store/useAuthStore';

export const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL,
  timeout: 15_000,
});

// Request interceptor — attach auth token
api.interceptors.request.use(
  (config) => {
    // Read token from Zustand store or localStorage
    const token = useAuthStore.getState().token;
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error),
);
```

Note: Call `useAuthStore.getState()` (not the hook) inside interceptors — hooks cannot be called outside React components.

---

## Response Interceptor — Error Handling

```ts
// lib/api.ts (continued)
import { useAuthStore } from '@/store/useAuthStore';
import { useNotificationStore } from '@/store/useNotificationStore';

api.interceptors.response.use(
  (response) => response,
  (error: AxiosError) => {
    const status = error.response?.status;

    if (status === 401) {
      // Token expired or invalid — clear auth and redirect to login
      useAuthStore.getState().clearUser();
      window.location.href = '/login';
      return Promise.reject(error);
    }

    if (status === 403) {
      // Authenticated but not authorized — show error
      useNotificationStore.getState().addNotification({
        type: 'error',
        message: 'You do not have permission to perform this action.',
      });
      return Promise.reject(error);
    }

    if (status === 500 || status === 503) {
      // Server error — show global error notification
      useNotificationStore.getState().addNotification({
        type: 'error',
        message: 'A server error occurred. Please try again later.',
      });
    }

    return Promise.reject(error);
  },
);
```

---

## API Service Files

Create one service file per domain. Each service function is a typed async function that returns a specific data shape.

```
src/
  services/
    userService.ts
    productService.ts
    orderService.ts
    authService.ts
```

### Service File Structure

```ts
// services/userService.ts
import { api } from '@/lib/api';
import type { User, CreateUserPayload, UpdateUserPayload, UserFilters, PaginatedResponse } from '@/types';

export const userService = {
  async getUsers(filters?: UserFilters): Promise<PaginatedResponse<User>> {
    const { data } = await api.get<PaginatedResponse<User>>('/users', { params: filters });
    return data;
  },

  async getUser(id: string): Promise<User> {
    const { data } = await api.get<User>(`/users/${id}`);
    return data;
  },

  async createUser(payload: CreateUserPayload): Promise<User> {
    const { data } = await api.post<User>('/users', payload);
    return data;
  },

  async updateUser(id: string, payload: UpdateUserPayload): Promise<User> {
    const { data } = await api.patch<User>(`/users/${id}`, payload);
    return data;
  },

  async deleteUser(id: string): Promise<void> {
    await api.delete(`/users/${id}`);
  },
};
```

```ts
// services/authService.ts
import { api } from '@/lib/api';
import type { User, LoginPayload, LoginResponse } from '@/types';

export const authService = {
  async login(payload: LoginPayload): Promise<LoginResponse> {
    const { data } = await api.post<LoginResponse>('/auth/login', payload);
    return data;
  },

  async logout(): Promise<void> {
    await api.post('/auth/logout');
  },

  async getSession(): Promise<User> {
    const { data } = await api.get<User>('/auth/me');
    return data;
  },

  async refreshToken(): Promise<{ token: string }> {
    const { data } = await api.post<{ token: string }>('/auth/refresh');
    return data;
  },
};
```

---

## Typed Response Shapes

Define all API response types in `types/api.ts` or alongside the relevant domain types.

```ts
// types/api.ts
export interface PaginatedResponse<T> {
  data: T[];
  meta: {
    page: number;
    pageSize: number;
    total: number;
    totalPages: number;
  };
}

export interface ApiError {
  message: string;
  code: string;
  details?: Record<string, string[]>;
}

// types/user.ts
export interface User {
  id: string;
  name: string;
  email: string;
  role: 'admin' | 'editor' | 'viewer';
  avatarUrl: string | null;
  createdAt: string;
}

export interface CreateUserPayload {
  name: string;
  email: string;
  role: User['role'];
}

export interface UpdateUserPayload {
  name?: string;
  email?: string;
  role?: User['role'];
}

export interface UserFilters {
  role?: User['role'];
  search?: string;
  page?: number;
  pageSize?: number;
}
```

---

## TanStack Query Integration

### QueryClient Configuration

```tsx
// main.tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ReactQueryDevtools } from '@tanstack/react-query-devtools';
import { isAxiosError } from 'axios';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5,    // 5 minutes
      gcTime: 1000 * 60 * 10,      // 10 minutes (formerly cacheTime)
      retry: (failureCount, error) => {
        // Do not retry on 4xx errors
        if (isAxiosError(error) && error.response?.status && error.response.status < 500) {
          return false;
        }
        return failureCount < 2;
      },
      refetchOnWindowFocus: true,
    },
    mutations: {
      retry: 0,
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

### Query Key Factory

```ts
// queries/userKeys.ts
import type { UserFilters } from '@/types';

export const userKeys = {
  all: ['users'] as const,
  lists: () => [...userKeys.all, 'list'] as const,
  list: (filters: UserFilters) => [...userKeys.lists(), filters] as const,
  details: () => [...userKeys.all, 'detail'] as const,
  detail: (id: string) => [...userKeys.details(), id] as const,
};
```

### useQuery Hooks

```ts
// hooks/queries/useUsers.ts
import { useQuery } from '@tanstack/react-query';
import { userService } from '@/services/userService';
import { userKeys } from '@/queries/userKeys';
import type { UserFilters } from '@/types';

export function useUsers(filters: UserFilters = {}) {
  return useQuery({
    queryKey: userKeys.list(filters),
    queryFn: () => userService.getUsers(filters),
    placeholderData: (previousData) => previousData, // keep showing old data while fetching next page
  });
}

export function useUser(id: string) {
  return useQuery({
    queryKey: userKeys.detail(id),
    queryFn: () => userService.getUser(id),
    enabled: !!id,
    staleTime: 1000 * 60 * 10, // user detail can be cached longer
  });
}
```

### useMutation Hooks

```ts
// hooks/mutations/useCreateUser.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { userService } from '@/services/userService';
import { userKeys } from '@/queries/userKeys';
import type { CreateUserPayload } from '@/types';

export function useCreateUser() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (payload: CreateUserPayload) => userService.createUser(payload),
    onSuccess: (newUser) => {
      // Invalidate all user lists
      queryClient.invalidateQueries({ queryKey: userKeys.lists() });
      // Optionally seed the detail cache to avoid an extra fetch
      queryClient.setQueryData(userKeys.detail(newUser.id), newUser);
    },
  });
}

export function useUpdateUser() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, payload }: { id: string; payload: UpdateUserPayload }) =>
      userService.updateUser(id, payload),
    onSuccess: (updatedUser) => {
      queryClient.invalidateQueries({ queryKey: userKeys.lists() });
      queryClient.setQueryData(userKeys.detail(updatedUser.id), updatedUser);
    },
  });
}

export function useDeleteUser() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => userService.deleteUser(id),
    onSuccess: (_data, id) => {
      queryClient.invalidateQueries({ queryKey: userKeys.lists() });
      queryClient.removeQueries({ queryKey: userKeys.detail(id) });
    },
  });
}
```

### Using Mutation Hooks in Components

```tsx
// UserManagement.tsx
import { useUsers } from '@/hooks/queries/useUsers';
import { useDeleteUser } from '@/hooks/mutations/useDeleteUser';

export function UserManagement() {
  const { data, isLoading } = useUsers();
  const { mutate: deleteUser, isPending: isDeleting } = useDeleteUser();

  if (isLoading) return <Spinner />;

  return (
    <table>
      <tbody>
        {data?.data.map(user => (
          <tr key={user.id}>
            <td>{user.name}</td>
            <td>{user.email}</td>
            <td>
              <button
                onClick={() =>
                  deleteUser(user.id, {
                    onSuccess: () => toast.success('User deleted'),
                    onError: () => toast.error('Failed to delete user'),
                  })
                }
                disabled={isDeleting}
              >
                Delete
              </button>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
```

---

## Optimistic Updates Pattern

```ts
// hooks/mutations/useToggleUserStatus.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { userService } from '@/services/userService';
import { userKeys } from '@/queries/userKeys';
import type { User } from '@/types';

export function useToggleUserStatus() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, isActive }: { id: string; isActive: boolean }) =>
      userService.updateUser(id, { isActive }),

    onMutate: async ({ id, isActive }) => {
      // Cancel outgoing refetches to prevent overwriting optimistic update
      await queryClient.cancelQueries({ queryKey: userKeys.detail(id) });

      // Snapshot the previous value for rollback
      const previousUser = queryClient.getQueryData<User>(userKeys.detail(id));

      // Optimistically update the detail cache
      queryClient.setQueryData<User>(userKeys.detail(id), (old) =>
        old ? { ...old, isActive } : old,
      );

      // Optimistically update any list caches
      queryClient.setQueriesData<{ data: User[] }>(
        { queryKey: userKeys.lists() },
        (old) => old
          ? { ...old, data: old.data.map(u => u.id === id ? { ...u, isActive } : u) }
          : old,
      );

      return { previousUser };
    },

    onError: (_err, { id }, context) => {
      // Roll back the optimistic update
      if (context?.previousUser) {
        queryClient.setQueryData(userKeys.detail(id), context.previousUser);
      }
      queryClient.invalidateQueries({ queryKey: userKeys.detail(id) });
    },

    onSettled: (_data, _err, { id }) => {
      // Always refetch after mutation to sync with server
      queryClient.invalidateQueries({ queryKey: userKeys.detail(id) });
    },
  });
}
```

---

## Handling Paginated API Responses

```tsx
// hooks/queries/useUsersPaginated.ts
import { useQuery, keepPreviousData } from '@tanstack/react-query';
import { userService } from '@/services/userService';
import { userKeys } from '@/queries/userKeys';
import { useSearchParams } from 'react-router-dom';

export function useUsersPaginated() {
  const [searchParams, setSearchParams] = useSearchParams();
  const page = Number(searchParams.get('page') ?? '1');
  const pageSize = Number(searchParams.get('pageSize') ?? '20');

  const query = useQuery({
    queryKey: userKeys.list({ page, pageSize }),
    queryFn: () => userService.getUsers({ page, pageSize }),
    placeholderData: keepPreviousData, // prevents empty flash between pages
  });

  const setPage = (next: number) => {
    setSearchParams(prev => {
      const params = new URLSearchParams(prev);
      params.set('page', String(next));
      return params;
    });
  };

  return { ...query, page, pageSize, setPage };
}
```

```tsx
// UserListPage.tsx
import { useUsersPaginated } from '@/hooks/queries/useUsersPaginated';

export function UserListPage() {
  const { data, isLoading, isFetching, page, setPage } = useUsersPaginated();

  return (
    <div>
      {isFetching && <div className="loading-indicator">Updating...</div>}
      {isLoading ? (
        <Spinner />
      ) : (
        <>
          <UserTable users={data?.data ?? []} />
          <Pagination
            currentPage={page}
            totalPages={data?.meta.totalPages ?? 1}
            onPageChange={setPage}
          />
        </>
      )}
    </div>
  );
}
```

---

## Request Cancellation with AbortController

TanStack Query automatically passes an AbortSignal to the query function. Pass it through to Axios.

```ts
// hooks/queries/useUserSearch.ts
import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/api';
import type { User } from '@/types';

export function useUserSearch(searchTerm: string) {
  return useQuery({
    queryKey: ['users', 'search', searchTerm],
    queryFn: async ({ signal }) => {
      const { data } = await api.get<User[]>('/users/search', {
        params: { q: searchTerm },
        signal, // pass through so Axios cancels the request when query is aborted
      });
      return data;
    },
    enabled: searchTerm.length >= 2,
  });
}
```

---

## Error Types and Error Handling

```ts
// lib/errors.ts
import { isAxiosError } from 'axios';
import type { ApiError } from '@/types';

export function getErrorMessage(error: unknown): string {
  if (isAxiosError<ApiError>(error)) {
    return error.response?.data?.message ?? error.message;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return 'An unexpected error occurred';
}

export function getFieldErrors(error: unknown): Record<string, string[]> {
  if (isAxiosError<ApiError>(error)) {
    return error.response?.data?.details ?? {};
  }
  return {};
}

export function isNotFoundError(error: unknown): boolean {
  return isAxiosError(error) && error.response?.status === 404;
}

export function isUnauthorizedError(error: unknown): boolean {
  return isAxiosError(error) && error.response?.status === 401;
}
```

```tsx
// UserDetail.tsx
import { useUser } from '@/hooks/queries/useUsers';
import { getErrorMessage, isNotFoundError } from '@/lib/errors';

export function UserDetail({ id }: { id: string }) {
  const { data: user, isLoading, isError, error } = useUser(id);

  if (isLoading) return <Spinner />;

  if (isError) {
    if (isNotFoundError(error)) {
      return <NotFound message="User not found" />;
    }
    return <ErrorMessage message={getErrorMessage(error)} />;
  }

  return <div>{user.name}</div>;
}
```

---

## Retry Logic Configuration

```ts
import { isAxiosError } from 'axios';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: (failureCount, error) => {
        // Never retry on client errors (4xx)
        if (isAxiosError(error)) {
          const status = error.response?.status;
          if (status && status >= 400 && status < 500) return false;
        }
        // Retry server errors up to 2 times with exponential backoff
        return failureCount < 2;
      },
      retryDelay: (attemptIndex) => Math.min(1000 * 2 ** attemptIndex, 30_000),
    },
  },
});
```

---

## Complete Example: Product Service and Hooks

```ts
// services/productService.ts
import { api } from '@/lib/api';
import type {
  Product,
  CreateProductPayload,
  ProductFilters,
  PaginatedResponse,
} from '@/types';

export const productService = {
  async getProducts(filters?: ProductFilters): Promise<PaginatedResponse<Product>> {
    const { data } = await api.get<PaginatedResponse<Product>>('/products', { params: filters });
    return data;
  },

  async getProduct(id: string): Promise<Product> {
    const { data } = await api.get<Product>(`/products/${id}`);
    return data;
  },

  async createProduct(payload: CreateProductPayload): Promise<Product> {
    const { data } = await api.post<Product>('/products', payload);
    return data;
  },

  async uploadProductImage(id: string, file: File): Promise<{ imageUrl: string }> {
    const formData = new FormData();
    formData.append('image', file);
    const { data } = await api.post<{ imageUrl: string }>(
      `/products/${id}/image`,
      formData,
      { headers: { 'Content-Type': 'multipart/form-data' } },
    );
    return data;
  },
};

// queries/productKeys.ts
export const productKeys = {
  all: ['products'] as const,
  lists: () => [...productKeys.all, 'list'] as const,
  list: (filters: ProductFilters) => [...productKeys.lists(), filters] as const,
  details: () => [...productKeys.all, 'detail'] as const,
  detail: (id: string) => [...productKeys.details(), id] as const,
};

// hooks/queries/useProducts.ts
import { useQuery } from '@tanstack/react-query';
import { productService } from '@/services/productService';
import { productKeys } from '@/queries/productKeys';

export function useProducts(filters: ProductFilters = {}) {
  return useQuery({
    queryKey: productKeys.list(filters),
    queryFn: () => productService.getProducts(filters),
  });
}

// hooks/mutations/useCreateProduct.ts
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { productService } from '@/services/productService';
import { productKeys } from '@/queries/productKeys';

export function useCreateProduct() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: productService.createProduct,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: productKeys.lists() });
    },
  });
}
```
