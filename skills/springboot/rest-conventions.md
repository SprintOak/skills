# Spring Boot REST API Conventions

This document defines the mandatory REST API conventions for all Spring Boot services. AI agents generating controller code, DTOs, or API endpoints MUST follow these rules exactly.

---

## 1. URL Naming

### Rules

- **DO** use kebab-case for multi-word path segments: `/user-profiles`, `/order-items`
- **DO** use plural nouns for resource collections: `/users`, `/products`, `/orders`
- **DO** use singular nouns when referring to a single resource via ID: `/users/{userId}`
- **DO** nest resources to express ownership: `/users/{userId}/orders`, `/orders/{orderId}/items`
- **DON'T** use verbs in URLs: never `/getUsers`, `/createOrder`, `/deleteProduct`
- **DON'T** use underscores in URL paths: never `/user_profiles`
- **DON'T** use camelCase in URL paths: never `/userProfiles`
- **DON'T** go deeper than 3 levels of nesting: avoid `/users/{userId}/orders/{orderId}/items/{itemId}/reviews`

### Examples

```
# CORRECT
GET  /api/v1/users
GET  /api/v1/users/{userId}
GET  /api/v1/users/{userId}/orders
POST /api/v1/orders
PUT  /api/v1/orders/{orderId}
GET  /api/v1/product-categories
GET  /api/v1/product-categories/{categoryId}/products

# INCORRECT
GET  /api/v1/getUsers
POST /api/v1/createOrder
GET  /api/v1/userProfile
GET  /api/v1/user_profiles
GET  /api/v1/users/{userId}/orders/{orderId}/items/{itemId}/reviews/{reviewId}/comments
```

---

## 2. HTTP Method Semantics

| Method   | Use Case                                      | Idempotent | Safe |
|----------|-----------------------------------------------|------------|------|
| `GET`    | Retrieve a resource or collection             | Yes        | Yes  |
| `POST`   | Create a new resource                         | No         | No   |
| `PUT`    | Replace an entire resource                    | Yes        | No   |
| `PATCH`  | Partially update a resource                   | No         | No   |
| `DELETE` | Remove a resource                             | Yes        | No   |

### Rules

- **DO** use `GET` for all read operations — never modify state in a GET handler
- **DO** use `POST` to create resources — return `201 Created` with the created resource
- **DO** use `PUT` when the client sends a full replacement of the resource
- **DO** use `PATCH` for partial updates — only the provided fields are updated
- **DO** use `DELETE` to remove resources — return `204 No Content` on success
- **DON'T** use `POST` for updates or deletes
- **DON'T** use `GET` with a request body to perform queries (use query params or a dedicated `POST /search` endpoint)

---

## 3. Standard Response Wrapper

All API responses MUST be wrapped in `ApiResponse<T>`. Never return raw entities or plain data directly.

### ApiResponse Structure

```java
package com.company.appname.dto.common;

import com.fasterxml.jackson.annotation.JsonInclude;
import lombok.Builder;
import lombok.Getter;

import java.time.Instant;

@Getter
@Builder
@JsonInclude(JsonInclude.Include.NON_NULL)
public class ApiResponse<T> {

    private final boolean success;
    private final String message;
    private final T data;
    private final Object errors;

    @Builder.Default
    private final Instant timestamp = Instant.now();

    public static <T> ApiResponse<T> success(T data) {
        return ApiResponse.<T>builder()
                .success(true)
                .message("Operation completed successfully")
                .data(data)
                .build();
    }

    public static <T> ApiResponse<T> success(T data, String message) {
        return ApiResponse.<T>builder()
                .success(true)
                .message(message)
                .data(data)
                .build();
    }

    public static <T> ApiResponse<T> error(String message, Object errors) {
        return ApiResponse.<T>builder()
                .success(false)
                .message(message)
                .errors(errors)
                .build();
    }

    public static <T> ApiResponse<T> error(String message) {
        return ApiResponse.<T>builder()
                .success(false)
                .message(message)
                .build();
    }
}
```

### Usage in Controllers

```java
// Single resource
return ResponseEntity.ok(ApiResponse.success(userResponse));

// Created resource
return ResponseEntity.status(HttpStatus.CREATED)
        .body(ApiResponse.success(userResponse, "User created successfully"));

// No content (DELETE) — no wrapper needed
return ResponseEntity.noContent().build();
```

### Example JSON Output

```json
{
  "success": true,
  "message": "User retrieved successfully",
  "data": {
    "id": "a1b2c3d4-...",
    "email": "user@example.com",
    "fullName": "Jane Doe"
  },
  "timestamp": "2026-03-14T10:00:00Z"
}
```

---

## 4. HTTP Status Codes

| Code | Meaning                  | When to Use                                                              |
|------|--------------------------|--------------------------------------------------------------------------|
| 200  | OK                       | Successful GET, PUT, PATCH                                               |
| 201  | Created                  | Successful POST that creates a resource                                  |
| 204  | No Content               | Successful DELETE, or PUT/PATCH that returns no body                     |
| 400  | Bad Request              | Malformed JSON, missing required fields, invalid format                  |
| 401  | Unauthorized             | Missing or invalid authentication token                                  |
| 403  | Forbidden                | Authenticated but lacks permission                                       |
| 404  | Not Found                | Resource does not exist                                                  |
| 409  | Conflict                 | Duplicate resource (e.g., email already registered)                      |
| 422  | Unprocessable Entity     | Request is well-formed but fails business validation rules               |
| 500  | Internal Server Error    | Unexpected server-side failure                                           |

### Rules

- **DO** return `201` from `POST` endpoints that create resources
- **DO** return `204` from `DELETE` endpoints — no body
- **DO** return `404` when a resource is not found by ID — never return `200` with null data
- **DO** return `409` for uniqueness violations (duplicate email, username, etc.)
- **DO** return `422` for business rule violations (e.g., insufficient balance, invalid state transition)
- **DON'T** return `200` for errors — always use an appropriate 4xx or 5xx code
- **DON'T** expose stack traces in 500 responses

---

## 5. Request and Response Body Conventions

- **DO** use dedicated DTO classes for requests and responses — never expose JPA entities directly
- **DO** name request DTOs `XxxRequest` (e.g., `CreateUserRequest`, `UpdateOrderRequest`)
- **DO** name response DTOs `XxxResponse` (e.g., `UserResponse`, `OrderSummaryResponse`)
- **DO** use `camelCase` for all JSON field names (Spring Boot default with Jackson)
- **DON'T** include `password`, `secret`, or sensitive fields in response DTOs
- **DON'T** include internal database fields (e.g., `createdBy` as a raw ID) in responses

### Request DTO Example

```java
@Getter
@Setter
@NoArgsConstructor
public class CreateUserRequest {

    @NotBlank(message = "First name is required")
    @Size(max = 50, message = "First name must not exceed 50 characters")
    private String firstName;

    @NotBlank(message = "Last name is required")
    @Size(max = 50, message = "Last name must not exceed 50 characters")
    private String lastName;

    @NotBlank(message = "Email is required")
    @Email(message = "Email must be a valid email address")
    private String email;

    @NotBlank(message = "Password is required")
    @Size(min = 8, max = 100, message = "Password must be between 8 and 100 characters")
    private String password;
}
```

### Response DTO Example

```java
@Getter
@Builder
public class UserResponse {

    private String id;            // UUID as string — never expose numeric database ID
    private String firstName;
    private String lastName;
    private String email;
    private String role;
    private Instant createdAt;
    private Instant updatedAt;
}
```

---

## 6. API Versioning

- **DO** prefix all API paths with `/api/v{n}`: `/api/v1/users`, `/api/v2/users`
- **DO** define the version prefix at the controller level using `@RequestMapping`
- **DON'T** version via request headers (Accept: application/vnd.company.v1+json) — path versioning is preferred for simplicity
- **DON'T** change an existing versioned endpoint in a breaking way — create a new version

```java
@RestController
@RequestMapping("/api/v1/users")
public class UserController {
    // ...
}
```

For multi-version support, create separate controller classes:

```java
@RestController
@RequestMapping("/api/v2/users")
public class UserV2Controller {
    // ...
}
```

---

## 7. Idempotency Rules

- **DO** make `PUT` and `DELETE` handlers idempotent — calling them multiple times with the same input MUST produce the same result
- **DO** return `200` (not `201`) when a `PUT` updates an existing resource and you want to confirm it
- **DO** return `204` for `DELETE` even if the resource was already deleted (or `404` if strict not-found semantics are needed — document your choice per endpoint)
- **DON'T** make `POST` idempotent by default — if idempotency is needed (e.g., payment), use an `Idempotency-Key` header

---

## 8. Controller Method Naming Conventions

Use consistent, descriptive method names that reflect the action and resource:

| HTTP Method | Path                          | Method Name           |
|-------------|-------------------------------|-----------------------|
| GET         | `/users`                      | `getAllUsers`         |
| GET         | `/users/{userId}`             | `getUserById`         |
| POST        | `/users`                      | `createUser`          |
| PUT         | `/users/{userId}`             | `updateUser`          |
| PATCH       | `/users/{userId}`             | `partialUpdateUser`   |
| DELETE      | `/users/{userId}`             | `deleteUser`          |
| GET         | `/users/{userId}/orders`      | `getOrdersByUser`     |

---

## 9. Path Variable vs Request Parameter Rules

### Path Variables

Use `@PathVariable` when the value **identifies a specific resource**:

```java
@GetMapping("/{userId}")
public ResponseEntity<ApiResponse<UserResponse>> getUserById(
        @PathVariable String userId) {
    // ...
}
```

### Request Parameters

Use `@RequestParam` for **filtering, sorting, searching, and pagination**:

```java
@GetMapping
public ResponseEntity<ApiResponse<Page<UserResponse>>> getAllUsers(
        @RequestParam(defaultValue = "0") int page,
        @RequestParam(defaultValue = "20") int size,
        @RequestParam(defaultValue = "createdAt") String sortBy,
        @RequestParam(defaultValue = "DESC") String sortDir,
        @RequestParam(required = false) String search,
        @RequestParam(required = false) String status) {
    // ...
}
```

- **DON'T** put filter criteria in path variables: avoid `/users/active` — use `/users?status=ACTIVE`
- **DON'T** put the operation in the URL: avoid `/users/search` when query params suffice

---

## 10. Pagination Query Parameters Standard

All paginated endpoints MUST use this standard set of query parameters:

| Parameter | Type    | Default   | Description                          |
|-----------|---------|-----------|--------------------------------------|
| `page`    | integer | `0`       | Zero-based page index                |
| `size`    | integer | `20`      | Number of items per page (max: 100)  |
| `sortBy`  | string  | varies    | Field name to sort by                |
| `sortDir` | string  | `DESC`    | Sort direction: `ASC` or `DESC`      |

### Paginated Response Structure

```java
@Getter
@Builder
public class PagedResponse<T> {

    private List<T> content;
    private int page;
    private int size;
    private long totalElements;
    private int totalPages;
    private boolean last;
    private boolean first;
}
```

```java
// Controller helper
private <T> PagedResponse<T> toPagedResponse(Page<T> page) {
    return PagedResponse.<T>builder()
            .content(page.getContent())
            .page(page.getNumber())
            .size(page.getSize())
            .totalElements(page.getTotalElements())
            .totalPages(page.getTotalPages())
            .last(page.isLast())
            .first(page.isFirst())
            .build();
}
```

---

## 11. Content-Type Headers

- **DO** set `Content-Type: application/json` for all JSON request/response bodies (Spring Boot default)
- **DO** use `MediaType.APPLICATION_JSON_VALUE` constant in annotations — never hardcode the string
- **DO** specify `consumes` and `produces` explicitly when the endpoint is not JSON-only

```java
@PostMapping(
    consumes = MediaType.APPLICATION_JSON_VALUE,
    produces = MediaType.APPLICATION_JSON_VALUE
)
public ResponseEntity<ApiResponse<UserResponse>> createUser(
        @Valid @RequestBody CreateUserRequest request) {
    // ...
}

@PostMapping(path = "/avatar", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
public ResponseEntity<ApiResponse<String>> uploadAvatar(
        @RequestParam("file") MultipartFile file) {
    // ...
}
```

---

## 12. Never Expose Internal IDs

- **DO** use UUIDs as public identifiers in all API responses and path variables
- **DO** generate UUIDs in the entity: `@GeneratedValue(strategy = GenerationType.UUID)`
- **DON'T** expose numeric auto-increment database IDs (`Long id`) in any API response or URL
- **DON'T** use numeric IDs in path variables: never `/users/42`

```java
@Entity
@Table(name = "users")
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;              // internal only — never exposed via API

    @Column(unique = true, nullable = false, updatable = false)
    private String publicId;      // UUID — this is what the API uses

    @PrePersist
    private void generatePublicId() {
        if (publicId == null) {
            publicId = UUID.randomUUID().toString();
        }
    }
}
```

---

## 13. HATEOAS Hints

While full HATEOAS implementation is optional, include relevant links in responses for discoverability:

```java
@Getter
@Builder
public class UserResponse {

    private String id;
    private String email;
    private String fullName;

    // Optional: self-link and related links
    private Map<String, String> links;
}

// In the mapper or service:
Map<String, String> links = new LinkedHashMap<>();
links.put("self", "/api/v1/users/" + user.getPublicId());
links.put("orders", "/api/v1/users/" + user.getPublicId() + "/orders");
```

For new projects requiring full HATEOAS, use `spring-boot-starter-hateoas` and `EntityModel<T>` / `CollectionModel<T>`.

---

## 14. Full Controller Example

```java
@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor
@Validated
public class UserController {

    private final UserService userService;

    @GetMapping
    public ResponseEntity<ApiResponse<PagedResponse<UserResponse>>> getAllUsers(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(defaultValue = "createdAt") String sortBy,
            @RequestParam(defaultValue = "DESC") String sortDir,
            @RequestParam(required = false) String search) {

        PagedResponse<UserResponse> result = userService.getAllUsers(page, size, sortBy, sortDir, search);
        return ResponseEntity.ok(ApiResponse.success(result));
    }

    @GetMapping("/{userId}")
    public ResponseEntity<ApiResponse<UserResponse>> getUserById(
            @PathVariable String userId) {

        UserResponse user = userService.getUserById(userId);
        return ResponseEntity.ok(ApiResponse.success(user));
    }

    @PostMapping
    public ResponseEntity<ApiResponse<UserResponse>> createUser(
            @Valid @RequestBody CreateUserRequest request) {

        UserResponse created = userService.createUser(request);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(ApiResponse.success(created, "User created successfully"));
    }

    @PutMapping("/{userId}")
    public ResponseEntity<ApiResponse<UserResponse>> updateUser(
            @PathVariable String userId,
            @Valid @RequestBody UpdateUserRequest request) {

        UserResponse updated = userService.updateUser(userId, request);
        return ResponseEntity.ok(ApiResponse.success(updated, "User updated successfully"));
    }

    @DeleteMapping("/{userId}")
    public ResponseEntity<Void> deleteUser(@PathVariable String userId) {
        userService.deleteUser(userId);
        return ResponseEntity.noContent().build();
    }
}
```
