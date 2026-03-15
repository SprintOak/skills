# Spring Boot OpenAPI / Swagger Documentation Conventions

This document defines mandatory rules for documenting Spring Boot REST APIs using springdoc-openapi. AI agents generating controllers, DTOs, or configuration code MUST follow every rule in this document.

---

## 1. Dependency

Add the following to your Gradle build (see `gradle.md` for full dependency file structure):

```groovy
// In gradle/dependencies.gradle
implementation 'org.springdoc:springdoc-openapi-starter-webmvc-ui:2.5.0'
```

**DON'T** use the legacy `springfox` library. **DON'T** use `springdoc-openapi-ui` (the old artifact). Always use `springdoc-openapi-starter-webmvc-ui`.

---

## 2. application.yaml Configuration

```yaml
springdoc:
  api-docs:
    path: /api-docs
    enabled: true
  swagger-ui:
    path: /swagger-ui.html
    enabled: true
    operations-sorter: method
    tags-sorter: alpha
    display-request-duration: true
    default-models-expand-depth: 2
  packages-to-scan: com.company.appname.controller
  show-actuator: false
```

In production, disable the Swagger UI:

```yaml
# application-prod.yaml
springdoc:
  swagger-ui:
    enabled: false
  api-docs:
    enabled: false
```

---

## 3. OpenAPI Bean Configuration

Every application MUST define an `OpenAPI` bean in a dedicated configuration class.

```java
package com.company.appname.config;

import io.swagger.v3.oas.models.Components;
import io.swagger.v3.oas.models.ExternalDocumentation;
import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenApiConfig {

    @Value("${app.version:1.0.0}")
    private String appVersion;

    @Bean
    public OpenAPI customOpenAPI() {
        final String securitySchemeName = "bearerAuth";

        return new OpenAPI()
                .info(new Info()
                        .title("User Management API")
                        .version(appVersion)
                        .description("REST API for managing users, roles, and authentication.")
                        .contact(new Contact()
                                .name("Platform Team")
                                .email("platform@company.com")
                                .url("https://company.com"))
                        .license(new License()
                                .name("Apache 2.0")
                                .url("https://www.apache.org/licenses/LICENSE-2.0")))
                .externalDocs(new ExternalDocumentation()
                        .description("Full Developer Documentation")
                        .url("https://docs.company.com"))
                .addSecurityItem(new SecurityRequirement().addList(securitySchemeName))
                .components(new Components()
                        .addSecuritySchemes(securitySchemeName,
                                new SecurityScheme()
                                        .name(securitySchemeName)
                                        .type(SecurityScheme.Type.HTTP)
                                        .scheme("bearer")
                                        .bearerFormat("JWT")
                                        .description("Enter your JWT Bearer token")));
    }
}
```

---

## 4. Controller-Level Annotations

Every controller class MUST have a `@Tag` annotation.

### Rules

- **DO** add `@Tag(name = "...", description = "...")` to every `@RestController` class
- **DO** use a short, human-readable tag name (e.g., `"User Management"`, `"Orders"`)
- **DO** group related controllers under the same tag name
- **DON'T** leave a controller without a `@Tag` — it will appear as "default" in the Swagger UI

```java
@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor
@Tag(name = "User Management", description = "Endpoints for creating, updating, retrieving, and deleting users")
public class UserController {
    // ...
}
```

---

## 5. Endpoint-Level Annotations

Every endpoint method MUST have an `@Operation` annotation with both `summary` and `description`.

### Rules

- **DO** add `@Operation(summary = "...", description = "...")` to every handler method
- **DO** keep `summary` to one short sentence (shown in the list view)
- **DO** use `description` to explain behavior, edge cases, required permissions, and side effects
- **DON'T** leave `description` empty — it must add value beyond the summary

```java
@Operation(
    summary = "Get a user by ID",
    description = "Retrieves a single user by their public UUID. Returns 404 if the user does not exist. Requires ROLE_ADMIN or the user's own token."
)
@GetMapping("/{userId}")
public ResponseEntity<ApiResponse<UserResponse>> getUserById(@PathVariable String userId) {
    // ...
}
```

---

## 6. Response Annotations

Every endpoint MUST declare `@ApiResponse` annotations for ALL expected HTTP status codes.

### Rules

- **DO** annotate every handler with `@ApiResponses` listing all possible responses
- **DO** include at least: success code, `400`, `401`, `404` (if applicable), `500`
- **DO** provide `description` for every `@ApiResponse`
- **DON'T** omit the error responses — they are as important as the success response

```java
@Operation(
    summary = "Create a new user",
    description = "Registers a new user account. Returns 409 if the email is already taken."
)
@ApiResponses(value = {
    @ApiResponse(responseCode = "201", description = "User created successfully",
        content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
            schema = @Schema(implementation = UserResponseWrapper.class))),
    @ApiResponse(responseCode = "400", description = "Validation failed — check the errors field",
        content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
            schema = @Schema(implementation = ErrorResponseWrapper.class))),
    @ApiResponse(responseCode = "409", description = "Email address is already registered",
        content = @Content(mediaType = MediaType.APPLICATION_JSON_VALUE,
            schema = @Schema(implementation = ErrorResponseWrapper.class))),
    @ApiResponse(responseCode = "500", description = "Unexpected internal server error",
        content = @Content(schema = @Schema(hidden = true)))
})
@PostMapping
public ResponseEntity<ApiResponse<UserResponse>> createUser(
        @Valid @RequestBody CreateUserRequest request) {
    // ...
}
```

For wrapped generic responses (`ApiResponse<T>`), define concrete wrapper classes for Swagger to resolve generics:

```java
// In a swagger-helpers package or inline as a nested class
class UserResponseWrapper extends ApiResponse<UserResponse> {}
class ErrorResponseWrapper extends ApiResponse<Void> {}
```

Alternatively, use `@Schema` with `ref` to point to a defined schema component.

---

## 7. Parameter Annotations

Every path variable and query parameter MUST have a `@Parameter` annotation.

### Rules

- **DO** annotate every `@PathVariable` and `@RequestParam` with `@Parameter`
- **DO** provide `description`, `example`, and `required` in every `@Parameter`
- **DON'T** leave parameters undocumented — they will appear with no context in Swagger UI

```java
@GetMapping
public ResponseEntity<ApiResponse<PagedResponse<UserResponse>>> getAllUsers(
        @Parameter(description = "Zero-based page index", example = "0", required = false)
        @RequestParam(defaultValue = "0") int page,

        @Parameter(description = "Number of items per page (max 100)", example = "20", required = false)
        @RequestParam(defaultValue = "20") int size,

        @Parameter(description = "Field to sort by", example = "createdAt", required = false)
        @RequestParam(defaultValue = "createdAt") String sortBy,

        @Parameter(description = "Sort direction: ASC or DESC", example = "DESC", required = false)
        @RequestParam(defaultValue = "DESC") String sortDir,

        @Parameter(description = "Search term to filter by name or email", example = "jane", required = false)
        @RequestParam(required = false) String search) {
    // ...
}

@GetMapping("/{userId}")
public ResponseEntity<ApiResponse<UserResponse>> getUserById(
        @Parameter(description = "Public UUID of the user", example = "a1b2c3d4-e5f6-7890-abcd-ef1234567890", required = true)
        @PathVariable String userId) {
    // ...
}
```

---

## 8. DTO Schema Annotations

All request and response DTOs used in API endpoints MUST have `@Schema` annotations.

### Rules

- **DO** annotate the DTO class with `@Schema(description = "...")`
- **DO** annotate every field with `@Schema(description = "...", example = "...")`
- **DO** mark required fields with `@Schema(requiredMode = Schema.RequiredMode.REQUIRED)`
- **DO** mark optional fields with `@Schema(requiredMode = Schema.RequiredMode.NOT_REQUIRED)`
- **DON'T** leave fields without descriptions — they show up as unnamed in Swagger UI

### Request DTO Example

```java
@Getter
@Setter
@NoArgsConstructor
@Schema(description = "Request body for creating a new user account")
public class CreateUserRequest {

    @NotBlank
    @Size(max = 50)
    @Schema(
        description = "User's first name",
        example = "Jane",
        requiredMode = Schema.RequiredMode.REQUIRED
    )
    private String firstName;

    @NotBlank
    @Size(max = 50)
    @Schema(
        description = "User's last name",
        example = "Doe",
        requiredMode = Schema.RequiredMode.REQUIRED
    )
    private String lastName;

    @NotBlank
    @Email
    @Schema(
        description = "User's email address — must be unique across the system",
        example = "jane.doe@example.com",
        requiredMode = Schema.RequiredMode.REQUIRED
    )
    private String email;

    @NotBlank
    @Size(min = 8, max = 100)
    @Schema(
        description = "Password — minimum 8 characters, must include at least one number",
        example = "Str0ng!Pass",
        requiredMode = Schema.RequiredMode.REQUIRED
    )
    private String password;

    @Schema(
        description = "Optional phone number in E.164 format",
        example = "+12025551234",
        requiredMode = Schema.RequiredMode.NOT_REQUIRED
    )
    private String phoneNumber;
}
```

### Response DTO Example

```java
@Getter
@Builder
@Schema(description = "User details returned by the API")
public class UserResponse {

    @Schema(description = "Public UUID of the user", example = "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
    private String id;

    @Schema(description = "User's first name", example = "Jane")
    private String firstName;

    @Schema(description = "User's last name", example = "Doe")
    private String lastName;

    @Schema(description = "User's email address", example = "jane.doe@example.com")
    private String email;

    @Schema(description = "Assigned role", example = "ROLE_USER", allowableValues = {"ROLE_USER", "ROLE_ADMIN", "ROLE_MODERATOR"})
    private String role;

    @Schema(description = "Timestamp when the user was created (ISO-8601)", example = "2026-03-14T10:00:00Z")
    private Instant createdAt;
}
```

---

## 9. Enum Documentation

Enums used in DTOs MUST be explicitly documented.

```java
@Schema(description = "Order status lifecycle values")
public enum OrderStatus {

    @Schema(description = "Order has been placed but not yet confirmed")
    PENDING,

    @Schema(description = "Order has been confirmed and is being processed")
    CONFIRMED,

    @Schema(description = "Order has been shipped")
    SHIPPED,

    @Schema(description = "Order has been delivered to the customer")
    DELIVERED,

    @Schema(description = "Order was cancelled before shipping")
    CANCELLED
}
```

In request/response DTOs, reference the enum and document allowed values:

```java
@Schema(
    description = "Current status of the order",
    example = "PENDING",
    allowableValues = {"PENDING", "CONFIRMED", "SHIPPED", "DELIVERED", "CANCELLED"}
)
private OrderStatus status;
```

---

## 10. Documenting Paginated Responses

Since `Page<T>` from Spring Data is complex to document directly, always use a concrete `PagedResponse<T>` class (see `rest-conventions.md`) and document it explicitly.

```java
@Getter
@Builder
@Schema(description = "Paginated list of users")
public class UserPagedResponse {

    @Schema(description = "List of users on the current page")
    private List<UserResponse> content;

    @Schema(description = "Current page index (zero-based)", example = "0")
    private int page;

    @Schema(description = "Number of items per page", example = "20")
    private int size;

    @Schema(description = "Total number of matching users", example = "150")
    private long totalElements;

    @Schema(description = "Total number of pages", example = "8")
    private int totalPages;

    @Schema(description = "Whether this is the last page", example = "false")
    private boolean last;

    @Schema(description = "Whether this is the first page", example = "true")
    private boolean first;
}
```

In the endpoint:

```java
@Operation(summary = "List all users", description = "Returns a paginated list of all users. Supports sorting and text search.")
@ApiResponses(value = {
    @ApiResponse(responseCode = "200", description = "Users retrieved successfully",
        content = @Content(schema = @Schema(implementation = UserPagedResponseWrapper.class))),
    @ApiResponse(responseCode = "401", description = "Authentication required")
})
@GetMapping
public ResponseEntity<ApiResponse<UserPagedResponse>> getAllUsers(...) {
    // ...
}
```

---

## 11. Security Documentation

When an endpoint requires authentication, it automatically inherits the global `bearerAuth` security scheme defined in the `OpenAPI` bean. To override for specific endpoints:

```java
// Mark an endpoint as publicly accessible (no auth required)
@Operation(
    summary = "Login",
    description = "Authenticates a user and returns a JWT token.",
    security = {}  // empty overrides the global security requirement
)
@PostMapping("/login")
public ResponseEntity<ApiResponse<AuthResponse>> login(@Valid @RequestBody LoginRequest request) {
    // ...
}
```

---

## 12. Full Annotated Controller Example

```java
package com.company.appname.controller;

import com.company.appname.dto.common.ApiResponse;
import com.company.appname.dto.common.PagedResponse;
import com.company.appname.dto.request.CreateUserRequest;
import com.company.appname.dto.request.UpdateUserRequest;
import com.company.appname.dto.response.UserResponse;
import com.company.appname.service.UserService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/users")
@RequiredArgsConstructor
@Tag(name = "User Management", description = "CRUD operations for user accounts")
public class UserController {

    private final UserService userService;

    @Operation(
        summary = "List all users",
        description = "Returns a paginated list of users. Supports search by name or email. Requires ROLE_ADMIN."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Users retrieved successfully"),
        @ApiResponse(responseCode = "401", description = "Missing or invalid JWT token"),
        @ApiResponse(responseCode = "403", description = "Insufficient permissions")
    })
    @GetMapping(produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<com.company.appname.dto.common.ApiResponse<PagedResponse<UserResponse>>> getAllUsers(
            @Parameter(description = "Page index (zero-based)", example = "0")
            @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "Page size", example = "20")
            @RequestParam(defaultValue = "20") int size,
            @Parameter(description = "Search by name or email", example = "jane")
            @RequestParam(required = false) String search) {

        return ResponseEntity.ok(
            com.company.appname.dto.common.ApiResponse.success(
                userService.getAllUsers(page, size, search)));
    }

    @Operation(
        summary = "Get user by ID",
        description = "Retrieves a user by their public UUID. Returns 404 if not found."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "User found"),
        @ApiResponse(responseCode = "401", description = "Missing or invalid JWT token"),
        @ApiResponse(responseCode = "404", description = "User not found")
    })
    @GetMapping(value = "/{userId}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<com.company.appname.dto.common.ApiResponse<UserResponse>> getUserById(
            @Parameter(description = "User's public UUID", example = "a1b2c3d4-e5f6-7890-abcd-ef1234567890", required = true)
            @PathVariable String userId) {

        return ResponseEntity.ok(
            com.company.appname.dto.common.ApiResponse.success(userService.getUserById(userId)));
    }

    @Operation(
        summary = "Create a new user",
        description = "Registers a new user. Returns 409 if the email is already taken."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "201", description = "User created successfully"),
        @ApiResponse(responseCode = "400", description = "Validation error"),
        @ApiResponse(responseCode = "409", description = "Email already in use")
    })
    @PostMapping(
        consumes = MediaType.APPLICATION_JSON_VALUE,
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<com.company.appname.dto.common.ApiResponse<UserResponse>> createUser(
            @Valid @RequestBody CreateUserRequest request) {

        UserResponse created = userService.createUser(request);
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(com.company.appname.dto.common.ApiResponse.success(created, "User created successfully"));
    }

    @Operation(
        summary = "Update a user",
        description = "Replaces all updatable fields of a user. Requires ROLE_ADMIN or ownership."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "User updated successfully"),
        @ApiResponse(responseCode = "400", description = "Validation error"),
        @ApiResponse(responseCode = "403", description = "Not authorized to update this user"),
        @ApiResponse(responseCode = "404", description = "User not found")
    })
    @PutMapping(
        value = "/{userId}",
        consumes = MediaType.APPLICATION_JSON_VALUE,
        produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<com.company.appname.dto.common.ApiResponse<UserResponse>> updateUser(
            @Parameter(description = "User's public UUID", required = true)
            @PathVariable String userId,
            @Valid @RequestBody UpdateUserRequest request) {

        return ResponseEntity.ok(
            com.company.appname.dto.common.ApiResponse.success(
                userService.updateUser(userId, request), "User updated successfully"));
    }

    @Operation(
        summary = "Delete a user",
        description = "Soft-deletes a user account. Requires ROLE_ADMIN."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "204", description = "User deleted"),
        @ApiResponse(responseCode = "401", description = "Missing or invalid JWT token"),
        @ApiResponse(responseCode = "403", description = "Insufficient permissions"),
        @ApiResponse(responseCode = "404", description = "User not found")
    })
    @DeleteMapping("/{userId}")
    public ResponseEntity<Void> deleteUser(
            @Parameter(description = "User's public UUID", required = true)
            @PathVariable String userId) {

        userService.deleteUser(userId);
        return ResponseEntity.noContent().build();
    }
}
```

---

## 13. Quick Reference Checklist

Before finalizing any controller, verify:

- [ ] Controller has `@Tag(name, description)`
- [ ] Every method has `@Operation(summary, description)`
- [ ] Every method has `@ApiResponses` covering all status codes
- [ ] Every `@PathVariable` and `@RequestParam` has `@Parameter(description, example)`
- [ ] Every request DTO has `@Schema` on the class and all fields
- [ ] Every response DTO has `@Schema` on the class and all fields
- [ ] Enums used in DTOs have `@Schema` with `allowableValues`
- [ ] JWT Bearer security scheme is configured in `OpenApiConfig`
- [ ] Public endpoints override security with `security = {}`
- [ ] Swagger UI is disabled in production profile
