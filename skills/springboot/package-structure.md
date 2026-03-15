# Spring Boot Package Structure Conventions

This document defines the mandatory package layout, naming conventions, and class placement rules for all Spring Boot applications. AI agents generating code MUST place every class in the correct package and apply the correct naming convention.

---

## 1. Top-Level Package

The root package follows this pattern:

```
com.{company}.{appname}
```

Examples:
- `com.acme.usermanagement`
- `com.company.orderservice`
- `com.startup.paymentapi`

**DO** keep all application code under this single root package.
**DON'T** create sibling packages at the same level as the root (e.g., `com.acme.util` outside the main package).

---

## 2. Layer-Based Structure (Small/Medium Apps)

For applications with fewer than ~10 bounded contexts, use a flat layer-based structure:

```
com.company.appname
├── AppNameApplication.java                  ← Main class
├── controller/
│   ├── UserController.java
│   ├── OrderController.java
│   └── AuthController.java
├── service/
│   ├── UserService.java                     ← Interface
│   ├── impl/
│   │   └── UserServiceImpl.java             ← Implementation
│   ├── OrderService.java
│   └── impl/
│       └── OrderServiceImpl.java
├── repository/
│   ├── UserRepository.java
│   └── OrderRepository.java
├── entity/
│   ├── User.java
│   └── Order.java
├── dto/
│   ├── common/
│   │   ├── ApiResponse.java
│   │   └── PagedResponse.java
│   ├── request/
│   │   ├── CreateUserRequest.java
│   │   ├── UpdateUserRequest.java
│   │   └── CreateOrderRequest.java
│   └── response/
│       ├── UserResponse.java
│       └── OrderResponse.java
├── mapper/
│   ├── UserMapper.java
│   └── OrderMapper.java
├── exception/
│   ├── GlobalExceptionHandler.java
│   ├── ResourceNotFoundException.java
│   ├── ConflictException.java
│   └── BusinessValidationException.java
├── config/
│   ├── SecurityConfig.java
│   ├── OpenApiConfig.java
│   ├── AsyncConfig.java
│   └── WebMvcConfig.java
├── security/
│   ├── JwtTokenProvider.java
│   ├── JwtAuthenticationFilter.java
│   └── UserDetailsServiceImpl.java
├── util/
│   ├── DateUtils.java
│   └── StringUtils.java
├── constant/
│   └── AppConstants.java
└── enums/
    ├── UserRole.java
    └── OrderStatus.java
```

---

## 3. Feature-Based Structure (Large Apps / Recommended for Microservices)

For applications with multiple distinct domains, use feature-based (vertical slice) packaging. This is the **recommended** approach for large applications.

```
com.company.appname
├── AppNameApplication.java
├── common/
│   ├── dto/
│   │   ├── ApiResponse.java
│   │   └── PagedResponse.java
│   ├── exception/
│   │   ├── GlobalExceptionHandler.java
│   │   ├── ResourceNotFoundException.java
│   │   └── BusinessValidationException.java
│   ├── config/
│   │   ├── SecurityConfig.java
│   │   ├── OpenApiConfig.java
│   │   └── AsyncConfig.java
│   ├── security/
│   │   ├── JwtTokenProvider.java
│   │   └── JwtAuthenticationFilter.java
│   └── util/
│       └── DateUtils.java
├── user/
│   ├── controller/
│   │   └── UserController.java
│   ├── service/
│   │   ├── UserService.java
│   │   └── UserServiceImpl.java
│   ├── repository/
│   │   └── UserRepository.java
│   ├── entity/
│   │   └── User.java
│   ├── dto/
│   │   ├── CreateUserRequest.java
│   │   ├── UpdateUserRequest.java
│   │   └── UserResponse.java
│   ├── mapper/
│   │   └── UserMapper.java
│   └── enums/
│       └── UserRole.java
├── order/
│   ├── controller/
│   │   └── OrderController.java
│   ├── service/
│   │   ├── OrderService.java
│   │   └── OrderServiceImpl.java
│   ├── repository/
│   │   └── OrderRepository.java
│   ├── entity/
│   │   └── Order.java
│   ├── dto/
│   │   ├── CreateOrderRequest.java
│   │   └── OrderResponse.java
│   ├── mapper/
│   │   └── OrderMapper.java
│   └── enums/
│       └── OrderStatus.java
└── notification/
    ├── service/
    │   ├── NotificationService.java
    │   └── NotificationServiceImpl.java
    └── dto/
        └── NotificationRequest.java
```

**DO** use feature-based structure when the project has 3 or more distinct domains.
**DO** keep `common/` for truly cross-cutting concerns (exception handling, security, shared DTOs).
**DON'T** put domain-specific code in `common/`.

---

## 4. What Goes in Each Package

### `controller/`
- `@RestController` classes only
- No business logic — only delegation to service layer
- Request validation via `@Valid`
- Response wrapping with `ApiResponse<T>`

### `service/`
- Business logic interfaces and implementations
- `XxxService.java` — interface
- `impl/XxxServiceImpl.java` — implementation (or co-located `XxxServiceImpl.java` in feature-based)
- All `@Transactional` annotations belong here, not in the controller or repository

### `repository/`
- Spring Data JPA interfaces extending `JpaRepository<Entity, Long>` or `JpaRepository<Entity, UUID>`
- Custom `@Query` methods
- `@Repository` annotation (though Spring Data adds it automatically via `JpaRepository`)
- Never write JDBC or native SQL unless absolutely necessary

### `entity/`
- JPA entity classes annotated with `@Entity`
- Class name is the domain noun (e.g., `User`, `Order`, `Product`) — NOT `UserEntity`
- **DO** follow the convention of naming the class the domain noun and the table name explicitly with `@Table(name = "users")`

### `dto/`
- Plain data transfer objects — no JPA annotations, no business logic
- Split into `request/` and `response/` subdirectories (in layer-based structure)
- `XxxRequest` suffix for inbound data
- `XxxResponse` suffix for outbound data
- `common/` subdirectory for shared wrappers (`ApiResponse<T>`, `PagedResponse<T>`)

### `mapper/`
- MapStruct mapper interfaces annotated with `@Mapper`
- One mapper per entity/feature
- Handles conversion between entity and DTO only

### `exception/`
- `GlobalExceptionHandler.java` — `@ControllerAdvice` class handling all exceptions
- Custom exception classes extending `RuntimeException`
- No business logic, no service calls in exception handlers

### `config/`
- Spring `@Configuration` classes
- Security config, CORS config, async config, cache config, OpenAPI config
- Bean definitions that don't belong to a specific domain

### `security/`
- JWT token provider/validator
- `UserDetailsService` implementation
- Custom authentication filters (`OncePerRequestFilter`)
- Security-related `@Component` classes

### `util/`
- Stateless utility classes with `private` constructors
- `public static` helper methods only
- Date formatting, string manipulation, file utilities

### `constant/`
- Interface or class with `public static final` constant fields
- Groups related constants (API paths, roles, cache key names, etc.)

### `enums/`
- Enum definitions used across the domain
- Enums specific to a domain can live inside the domain package in feature-based structure

---

## 5. Naming Conventions

| Class Type              | Convention                    | Example                           |
|-------------------------|-------------------------------|-----------------------------------|
| Main application class  | `{AppName}Application`        | `UserManagementApplication`       |
| REST controller         | `{Resource}Controller`        | `UserController`, `OrderController` |
| Service interface       | `{Resource}Service`           | `UserService`, `EmailService`     |
| Service implementation  | `{Resource}ServiceImpl`       | `UserServiceImpl`                 |
| Repository interface    | `{Resource}Repository`        | `UserRepository`                  |
| JPA entity              | `{Resource}` (no suffix)      | `User`, `Order`, `Product`        |
| Request DTO             | `{Action}{Resource}Request`   | `CreateUserRequest`, `UpdateOrderRequest` |
| Response DTO            | `{Resource}Response`          | `UserResponse`, `OrderSummaryResponse` |
| Summary response DTO    | `{Resource}SummaryResponse`   | `UserSummaryResponse`             |
| MapStruct mapper        | `{Resource}Mapper`            | `UserMapper`, `OrderMapper`       |
| Exception class         | `{Condition}Exception`        | `ResourceNotFoundException`, `ConflictException` |
| Exception handler       | `GlobalExceptionHandler`      | (always this name)                |
| Configuration class     | `{Purpose}Config`             | `SecurityConfig`, `OpenApiConfig` |
| Filter class            | `{Purpose}Filter`             | `JwtAuthenticationFilter`         |
| Constants class         | `AppConstants`                | (or `{Domain}Constants`)          |
| Enum                    | PascalCase noun                | `UserRole`, `OrderStatus`         |
| Utility class           | `{Purpose}Utils`              | `DateUtils`, `StringUtils`        |

---

## 6. Main Application Class Placement

The main application class MUST be placed at the **root package level** — not in a sub-package. Spring Boot's component scan starts from this class's package and scans all sub-packages.

```java
// CORRECT: com/company/appname/AppNameApplication.java
package com.company.appname;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class AppNameApplication {
    public static void main(String[] args) {
        SpringApplication.run(AppNameApplication.class, args);
    }
}
```

```java
// INCORRECT: com/company/appname/config/AppNameApplication.java
// Moving the main class to a sub-package will break component scanning
```

**DON'T** add `@ComponentScan`, `@EnableJpaRepositories`, or `@EntityScan` unless using a non-standard structure — `@SpringBootApplication` covers all of these.

---

## 7. Test Package Structure

Test packages MUST mirror the main source package structure exactly.

```
src/test/java/
└── com/company/appname/
    ├── controller/
    │   ├── UserControllerTest.java          ← @WebMvcTest slice test
    │   └── OrderControllerTest.java
    ├── service/
    │   ├── UserServiceImplTest.java         ← Unit test with Mockito
    │   └── OrderServiceImplTest.java
    ├── repository/
    │   └── UserRepositoryTest.java          ← @DataJpaTest slice test
    ├── integration/
    │   └── UserIntegrationTest.java         ← @SpringBootTest full integration test
    └── AppNameApplicationTests.java         ← Context load test
```

### Test Class Naming

| Test Type               | Convention                      | Example                        |
|-------------------------|---------------------------------|--------------------------------|
| Unit test               | `{ClassName}Test`               | `UserServiceImplTest`          |
| Controller slice test   | `{Controller}Test`              | `UserControllerTest`           |
| Repository slice test   | `{Repository}Test`              | `UserRepositoryTest`           |
| Integration test        | `{Feature}IntegrationTest`      | `UserIntegrationTest`          |
| Application context test| `{AppName}ApplicationTests`     | `UserManagementApplicationTests` |

---

## 8. Practical Entity Example

```java
// com/company/appname/entity/User.java  (layer-based)
// com/company/appname/user/entity/User.java  (feature-based)

package com.company.appname.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "users")
@Getter
@Setter
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;                  // internal — never exposed via API

    @Column(name = "public_id", unique = true, nullable = false, updatable = false)
    private String publicId;          // UUID — used as the API identifier

    @Column(name = "first_name", nullable = false, length = 50)
    private String firstName;

    @Column(name = "last_name", nullable = false, length = 50)
    private String lastName;

    @Column(unique = true, nullable = false)
    private String email;

    @Column(nullable = false)
    private String password;          // bcrypt hash — never returned in responses

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private UserRole role;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private Instant createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at")
    private Instant updatedAt;

    @PrePersist
    private void generatePublicId() {
        if (this.publicId == null) {
            this.publicId = UUID.randomUUID().toString();
        }
    }
}
```

---

## 9. Practical Mapper Example

```java
// com/company/appname/mapper/UserMapper.java

package com.company.appname.mapper;

import com.company.appname.dto.request.CreateUserRequest;
import com.company.appname.dto.response.UserResponse;
import com.company.appname.entity.User;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.MappingTarget;

@Mapper(componentModel = "spring")
public interface UserMapper {

    @Mapping(target = "id", source = "publicId")   // map internal UUID to "id"
    @Mapping(target = "fullName", expression = "java(user.getFirstName() + ' ' + user.getLastName())")
    UserResponse toResponse(User user);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "publicId", ignore = true)
    @Mapping(target = "password", ignore = true)    // password set separately after encoding
    @Mapping(target = "role", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    User toEntity(CreateUserRequest request);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "publicId", ignore = true)
    @Mapping(target = "email", ignore = true)       // email updates go through a separate flow
    @Mapping(target = "password", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    void updateEntity(UpdateUserRequest request, @MappingTarget User user);
}
```

---

## 10. Decision Guide

| Scenario                                          | Recommendation              |
|---------------------------------------------------|-----------------------------|
| Simple CRUD app, 1-3 resources                    | Layer-based structure       |
| Medium app, 4-10 resources                        | Layer-based structure       |
| Large app with clearly bounded domains            | Feature-based structure     |
| Microservice (one service = one domain)           | Layer-based (single domain) |
| Monolith being prepared for microservice split    | Feature-based structure     |
