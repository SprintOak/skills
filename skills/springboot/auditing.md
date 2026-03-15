# Spring Boot JPA Auditing — AI Agent Context

This file defines the authoritative patterns for entity auditing and soft delete in Spring Boot applications.
Agents MUST follow these patterns when generating or modifying JPA entity code.

---

## Core Principles

- All persistent entities that represent business data MUST extend `BaseEntity`.
- Auditing fields (`createdAt`, `updatedAt`, `createdBy`, `updatedBy`) are managed automatically by Spring Data JPA.
- Soft delete is preferred over hard delete for any business-owned data.
- Hard delete is acceptable only for ephemeral, non-auditable data (sessions, temp files, etc.).
- Use `@Version` on all entities subject to concurrent updates.

---

## BaseEntity — Full Definition

```java
@MappedSuperclass
@EntityListeners(AuditingEntityListener.class)
@Getter
@Setter
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
public abstract class BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "id", updatable = false, nullable = false)
    private UUID id;

    @CreatedDate
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @LastModifiedDate
    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @CreatedBy
    @Column(name = "created_by", updatable = false)
    private String createdBy;

    @LastModifiedBy
    @Column(name = "updated_by")
    private String updatedBy;

    @Version
    @Column(name = "version")
    private Long version;

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof BaseEntity other)) return false;
        return id != null && id.equals(other.id);
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
```

DO:
- Use `@MappedSuperclass` so JPA maps each subclass to its own table with the base fields included.
- Use `@EntityListeners(AuditingEntityListener.class)` to activate Spring's audit population.
- Define `equals` based on `id` only — never use Lombok `@EqualsAndHashCode` on entities.
- Use a fixed `hashCode` (class-based) to keep entities safe in collections before they are persisted.
- Use `UUID` for IDs generated on the database side with `gen_random_uuid()` (or `GenerationType.UUID` for DB-agnostic).
- Add `@Version` for optimistic locking support.

DON'T:
- NEVER use `@Data` on JPA entities — it generates `equals`/`hashCode` based on all fields, which breaks Hibernate's dirty-checking and collection behavior.
- NEVER use auto-increment `Long` IDs unless there is a strong performance reason (UUID avoids sequence bottlenecks and is safer in distributed systems).
- NEVER use `@EqualsAndHashCode` from Lombok on entities.

---

## Enable JPA Auditing

```java
@Configuration
@EnableJpaAuditing(auditorAwareRef = "auditorProvider")
public class JpaAuditingConfig {
    // All auditing configuration is in this class
}
```

Or add to your main `@SpringBootApplication` class if no separate config is needed:

```java
@SpringBootApplication
@EnableJpaAuditing(auditorAwareRef = "auditorProvider")
public class MyApplication {
    public static void main(String[] args) {
        SpringApplication.run(MyApplication.class, args);
    }
}
```

DO:
- Always reference the `AuditorAware` bean by name using `auditorAwareRef`.
- Place `@EnableJpaAuditing` on a `@Configuration` class to keep it separate from the application entry point.

---

## AuditorAware Bean

```java
@Component("auditorProvider")
public class SecurityAuditorAware implements AuditorAware<String> {

    @Override
    public Optional<String> getCurrentAuditor() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

        if (authentication == null
                || !authentication.isAuthenticated()
                || authentication instanceof AnonymousAuthenticationToken) {
            return Optional.of("SYSTEM");
        }

        return Optional.ofNullable(authentication.getName());
    }
}
```

DO:
- Return `Optional.of("SYSTEM")` (or a sentinel value) when no authenticated user is present — this handles application startup migrations and batch jobs.
- Use `authentication.getName()` which returns the username/email (the value from `UserDetails.getUsername()`).
- Name the bean to match `auditorAwareRef` in `@EnableJpaAuditing`.

DON'T:
- NEVER return `Optional.empty()` — Spring Data will skip populating `@CreatedBy`/`@LastModifiedBy` if empty.
- NEVER throw exceptions from `getCurrentAuditor`.

---

## Concrete Entity Example

```java
@Entity
@Table(name = "orders")
@Getter
@Setter
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
public class Order extends BaseEntity {

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false)
    private OrderStatus status;

    @Column(name = "total", nullable = false, precision = 19, scale = 2)
    private BigDecimal total;

    @OneToMany(mappedBy = "order", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<OrderItem> items = new ArrayList<>();
}
```

---

## Soft Delete Pattern

### BaseEntity with Soft Delete Support

```java
@MappedSuperclass
@EntityListeners(AuditingEntityListener.class)
@Getter
@Setter
@SuperBuilder
@NoArgsConstructor
@AllArgsConstructor
public abstract class BaseEntity {

    // ... (id, createdAt, updatedAt, createdBy, updatedBy, version as above)

    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    public boolean isDeleted() {
        return deletedAt != null;
    }

    public void markDeleted() {
        this.deletedAt = LocalDateTime.now();
    }
}
```

### Filtering Deleted Records

For Hibernate 6+ (Spring Boot 3+):

```java
@Entity
@Table(name = "users")
@SQLRestriction("deleted_at IS NULL")   // Hibernate 6+ — applied to all queries on this entity
@Getter
@Setter
@SuperBuilder
@NoArgsConstructor
public class User extends BaseEntity {

    @Column(name = "email", nullable = false, unique = true)
    private String email;

    @Column(name = "first_name", nullable = false)
    private String firstName;

    @Column(name = "last_name", nullable = false)
    private String lastName;
}
```

For Hibernate 5 (Spring Boot 2.x) use `@Where`:

```java
@Where(clause = "deleted_at IS NULL")  // Hibernate 5
public class User extends BaseEntity { ... }
```

DO:
- Use `@SQLRestriction` for Hibernate 6+ (Spring Boot 3+).
- Use `@Where` only for Hibernate 5 / Spring Boot 2.x — it is deprecated in Hibernate 6.
- Implement `markDeleted()` on `BaseEntity` to encapsulate the delete logic.
- Always add a partial index on `deleted_at` in your Flyway migration for query performance:

```sql
-- In migration file
CREATE INDEX idx_users_not_deleted ON users(id) WHERE deleted_at IS NULL;
```

DON'T:
- NEVER physically delete rows for business data (orders, users, transactions, invoices).
- NEVER set `deleted_at` directly from outside the entity — always call `entity.markDeleted()`.
- NEVER forget to apply the `@SQLRestriction` / `@Where` annotation when adding soft delete.

### Soft Delete in Repository

```java
public interface UserRepository extends JpaRepository<User, UUID> {

    // @SQLRestriction automatically filters deleted users from all queries below

    Optional<User> findByEmail(String email);

    List<User> findByRole(Role role);

    // To explicitly query deleted records (bypass @SQLRestriction):
    @Query(value = "SELECT * FROM users WHERE id = :id", nativeQuery = true)
    Optional<User> findByIdIncludingDeleted(@Param("id") UUID id);
}
```

### Soft Delete in Service

```java
@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;

    public void deleteUser(UUID userId) {
        User user = userRepository.findById(userId)
            .orElseThrow(() -> new EntityNotFoundException("User not found: " + userId));

        user.markDeleted();
        userRepository.save(user);
        // The user is now filtered from all subsequent queries by @SQLRestriction
    }
}
```

---

## Hard Delete vs Soft Delete — Decision Rules

| Situation | Approach |
|-----------|----------|
| Business entities: users, orders, products, invoices | Soft delete |
| Audit logs | Immutable — never delete |
| Tokens, sessions, OTP codes | Hard delete (ephemeral) |
| Regulatory/compliance requirement to purge data | Scheduled hard delete after soft delete period |
| Join/lookup tables (many-to-many) | Hard delete (typically) |
| User-generated content | Soft delete |

---

## Optimistic Locking with @Version

```java
// BaseEntity already includes @Version
// In service code — handle optimistic lock failures

@Service
@RequiredArgsConstructor
public class ProductService {

    private final ProductRepository productRepository;

    @Transactional
    public Product updatePrice(UUID productId, BigDecimal newPrice) {
        Product product = productRepository.findById(productId)
            .orElseThrow(() -> new EntityNotFoundException("Product not found: " + productId));

        product.setPrice(newPrice);
        return productRepository.save(product);
        // If another transaction modified this product since it was loaded,
        // Hibernate throws OptimisticLockException (HTTP 409)
    }
}

// In GlobalExceptionHandler
@ExceptionHandler(ObjectOptimisticLockingFailureException.class)
public ResponseEntity<ErrorResponse> handleOptimisticLock(ObjectOptimisticLockingFailureException ex) {
    return ResponseEntity.status(HttpStatus.CONFLICT)
        .body(ErrorResponse.of("The resource was modified by another request. Please retry."));
}
```

DO:
- Always handle `ObjectOptimisticLockingFailureException` in the global exception handler and return `409 Conflict`.
- Include the `version` field in update request DTOs so the client must echo it back.

---

## Auditing in Multi-Tenant Scenarios

```java
@Component("auditorProvider")
public class MultiTenantAuditorAware implements AuditorAware<String> {

    @Override
    public Optional<String> getCurrentAuditor() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

        if (authentication == null || !authentication.isAuthenticated()
                || authentication instanceof AnonymousAuthenticationToken) {
            return Optional.of("SYSTEM");
        }

        // Include tenant context in the auditor string: "tenantId:userId"
        String tenantId = TenantContext.getCurrentTenantId();
        String userId = authentication.getName();

        return Optional.of(tenantId != null
            ? tenantId + ":" + userId
            : userId);
    }
}
```

For multi-tenant systems with tenant-scoped queries, combine `@SQLRestriction` with a tenant discriminator column:

```java
@Entity
@Table(name = "orders")
@SQLRestriction("deleted_at IS NULL AND tenant_id = 'CURRENT_TENANT'")
// OR handle via Hibernate filter for dynamic values:
@FilterDef(name = "tenantFilter",
           parameters = @ParamDef(name = "tenantId", type = String.class))
@Filter(name = "tenantFilter", condition = "tenant_id = :tenantId")
public class Order extends BaseEntity {

    @Column(name = "tenant_id", nullable = false, updatable = false)
    private String tenantId;
    // ...
}
```

For dynamic tenant filtering, prefer Hibernate `@Filter` over `@SQLRestriction` because `@SQLRestriction` cannot accept runtime parameters.

---

## Flyway Migration for BaseEntity Fields

Every entity table must have these columns created in its migration:

```sql
-- V1__create_orders_table.sql
CREATE TABLE orders (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID         NOT NULL REFERENCES users(id),
    status      VARCHAR(50)  NOT NULL DEFAULT 'PENDING',
    total       NUMERIC(19,2) NOT NULL,

    -- BaseEntity audit fields
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    created_by  VARCHAR(255),
    updated_by  VARCHAR(255),
    version     BIGINT       NOT NULL DEFAULT 0,

    -- Soft delete
    deleted_at  TIMESTAMP
);

CREATE INDEX idx_orders_user_id         ON orders(user_id);
CREATE INDEX idx_orders_status          ON orders(status);
CREATE INDEX idx_orders_not_deleted     ON orders(id) WHERE deleted_at IS NULL;
```

---

## Summary Checklist

- [ ] `BaseEntity` declared as `@MappedSuperclass` with `@EntityListeners(AuditingEntityListener.class)`
- [ ] `@CreatedDate`, `@LastModifiedDate`, `@CreatedBy`, `@LastModifiedBy` on corresponding fields
- [ ] `@Version` field present on `BaseEntity`
- [ ] `@EnableJpaAuditing(auditorAwareRef = "auditorProvider")` on a `@Configuration` class
- [ ] `AuditorAware<String>` bean implemented, returns `"SYSTEM"` as fallback
- [ ] `deletedAt` field and `markDeleted()` method on `BaseEntity`
- [ ] `@SQLRestriction("deleted_at IS NULL")` on every entity that supports soft delete (Hibernate 6+)
- [ ] Partial index on `deleted_at` in Flyway migration
- [ ] `equals` based on `id` only; `hashCode` returns class hash
- [ ] `@Data` NOT used on any JPA entity
- [ ] `OptimisticLockException` handled in global exception handler returning `409 Conflict`
- [ ] Business data uses soft delete; ephemeral data uses hard delete
