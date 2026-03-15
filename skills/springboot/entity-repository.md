# Spring Boot Entity & Repository Rules

## Overview

This document defines mandatory rules for JPA entity classes and Spring Data JPA repositories. All rules are prescriptive. Deviations require explicit justification.

---

## Entity Class Rules

### Basic Annotations

DO annotate every entity class with `@Entity` and `@Table`.

```java
@Entity
@Table(name = "users")
public class User extends BaseEntity {
    // ...
}
```

DO NOT omit `@Table`. Relying on default table name derivation leads to naming inconsistencies across databases.

DO NOT use class-level `@Table` with `schema` unless the application explicitly manages multiple schemas.

### Naming Convention

DO use singular class names. DO map to plural table names via `@Table(name = "...")`.

| Class Name       | Table Name         |
|------------------|--------------------|
| `User`           | `users`            |
| `OrderItem`      | `order_items`      |
| `ProductCategory`| `product_categories`|

DO use snake_case for all table and column names.

DO NOT rely on Hibernate's implicit naming strategy. Always declare names explicitly.

### Primary Key

DO always use `UUID` as the primary key type.

```java
@Id
@GeneratedValue(strategy = GenerationType.UUID)
@Column(name = "id", updatable = false, nullable = false)
private UUID id;
```

DO NOT use `Long` or auto-increment integers as public-facing identifiers. UUIDs prevent ID enumeration attacks and simplify distributed system design.

DO NOT use `@GeneratedValue(strategy = GenerationType.IDENTITY)` with UUID columns.

---

## BaseEntity: Mandatory Superclass

DO define a `BaseEntity` mapped superclass and extend it in every entity. All entities must carry `id`, `createdAt`, and `updatedAt`.

```java
@MappedSuperclass
@EntityListeners(AuditingEntityListener.class)
public abstract class BaseEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "id", updatable = false, nullable = false)
    private UUID id;

    @CreatedDate
    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @LastModifiedDate
    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof BaseEntity that)) return false;
        return id != null && id.equals(that.id);
    }

    @Override
    public int hashCode() {
        return getClass().hashCode();
    }
}
```

DO enable JPA auditing in the main application class or a configuration class:

```java
@Configuration
@EnableJpaAuditing
public class JpaConfig {}
```

DO NOT duplicate `id`, `createdAt`, or `updatedAt` fields in subclasses.

DO NOT use `@Data` (Lombok) on entities. It generates `equals`, `hashCode`, and `toString` incorrectly for JPA entities.

---

## Column Constraints

DO declare `nullable`, `length`, and `unique` constraints explicitly on every `@Column`.

```java
@Column(name = "email", nullable = false, unique = true, length = 255)
private String email;

@Column(name = "first_name", nullable = false, length = 100)
private String firstName;

@Column(name = "bio", columnDefinition = "TEXT")
private String bio;
```

DO use `columnDefinition = "TEXT"` for unbounded string columns instead of an arbitrary large `length`.

DO NOT use default `@Column` without constraints. Silent defaults cause schema drift.

DO use `precision` and `scale` for monetary or decimal fields:

```java
@Column(name = "price", nullable = false, precision = 10, scale = 2)
private BigDecimal price;
```

---

## Relationships

### Default Fetch Strategy

DO always specify `fetch = FetchType.LAZY` on every relationship. Eager loading causes N+1 problems and uncontrolled query scope.

```java
@ManyToOne(fetch = FetchType.LAZY)
@JoinColumn(name = "department_id", nullable = false)
private Department department;

@OneToMany(mappedBy = "department", fetch = FetchType.LAZY, cascade = CascadeType.ALL, orphanRemoval = true)
private List<Employee> employees = new ArrayList<>();
```

DO NOT use `FetchType.EAGER` unless there is a documented, performance-tested reason.

DO initialize collection fields to empty collections (`new ArrayList<>()`, `new HashSet<>()`) to avoid `NullPointerException`.

### @OneToMany / @ManyToOne

DO use `mappedBy` on the `@OneToMany` side (the non-owning side).

DO use `orphanRemoval = true` when the child entity has no independent lifecycle.

DO add bidirectional helper methods on the owning side:

```java
// In Department entity
public void addEmployee(Employee employee) {
    employees.add(employee);
    employee.setDepartment(this);
}

public void removeEmployee(Employee employee) {
    employees.remove(employee);
    employee.setDepartment(null);
}
```

### @ManyToMany

DO use a join table with explicit column definitions.

```java
@ManyToMany(fetch = FetchType.LAZY)
@JoinTable(
    name = "user_roles",
    joinColumns = @JoinColumn(name = "user_id"),
    inverseJoinColumns = @JoinColumn(name = "role_id")
)
private Set<Role> roles = new HashSet<>();
```

DO NOT use `CascadeType.ALL` on `@ManyToMany`. Cascading deletes through a many-to-many relationship will delete the shared entity from all other associations.

DO use `Set` (not `List`) for `@ManyToMany` to avoid Hibernate's "HHH90003004" duplicate join issue.

### Cascade Rules Summary

| Relationship     | Allowed Cascades                    | Forbidden              |
|------------------|-------------------------------------|------------------------|
| `@OneToMany`     | `ALL` (when orphanRemoval=true)     | None                   |
| `@ManyToOne`     | `PERSIST`, `MERGE` only             | `REMOVE`, `ALL`        |
| `@ManyToMany`    | `PERSIST`, `MERGE` only             | `REMOVE`, `ALL`        |
| `@OneToOne`      | `ALL` (when owned exclusively)      | None                   |

### @JsonIgnore on Bidirectional Relationships

DO annotate the back-reference side with `@JsonIgnore` to prevent infinite recursion during serialization.

```java
// In Employee entity (the "many" side)
@ManyToOne(fetch = FetchType.LAZY)
@JoinColumn(name = "department_id")
@JsonIgnore
private Department department;
```

DO NOT use `@JsonManagedReference` / `@JsonBackReference` as a general solution. They tightly couple entity serialization to JSON output, which is the service layer's responsibility. Prefer `@JsonIgnore` or, better, always serialize DTOs instead of entities.

---

## equals, hashCode, and toString

### equals and hashCode

DO base `equals` and `hashCode` only on the `id` field, following the pattern in `BaseEntity` above.

DO NOT include mutable business fields in `equals`/`hashCode`. This breaks collections when fields change.

DO NOT use Lombok's `@EqualsAndHashCode` on entities without explicitly setting `onlyExplicitlyIncluded = true` and annotating the `id` field.

```java
// Acceptable Lombok approach
@EqualsAndHashCode(onlyExplicitlyIncluded = true, callSuper = false)
public class User extends BaseEntity {

    @EqualsAndHashCode.Include
    // id is already in BaseEntity, so override equals/hashCode there
}
```

The simpler approach is to implement `equals`/`hashCode` manually in `BaseEntity` as shown above.

### toString

DO annotate `toString` to exclude lazy-loaded collection fields to prevent unintentional database queries and `LazyInitializationException`.

```java
@ToString(exclude = {"orders", "roles"})
@Entity
@Table(name = "users")
public class User extends BaseEntity {
    // ...
}
```

DO NOT call `toString()` on an entity outside a transaction context if it includes relationships.

---

## Full Entity Example

```java
@Entity
@Table(name = "products")
@Getter
@Setter
@ToString(exclude = {"orderItems", "categories"})
@NoArgsConstructor
public class Product extends BaseEntity {

    @Column(name = "name", nullable = false, length = 200)
    private String name;

    @Column(name = "description", columnDefinition = "TEXT")
    private String description;

    @Column(name = "price", nullable = false, precision = 10, scale = 2)
    private BigDecimal price;

    @Column(name = "stock_quantity", nullable = false)
    private Integer stockQuantity;

    @Column(name = "active", nullable = false)
    private boolean active = true;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "category_id", nullable = false)
    @JsonIgnore
    private Category category;

    @OneToMany(mappedBy = "product", fetch = FetchType.LAZY, cascade = CascadeType.ALL, orphanRemoval = true)
    private List<OrderItem> orderItems = new ArrayList<>();
}
```

---

## Repository Interface Rules

### Extend JpaRepository

DO extend `JpaRepository<Entity, UUID>` for all repositories.

```java
public interface UserRepository extends JpaRepository<User, UUID> {
}
```

DO NOT extend `CrudRepository` or `PagingAndSortingRepository` directly. `JpaRepository` provides the full interface.

DO NOT add `@Repository` to repository interfaces. Spring Data detects them automatically.

### Derived Query Methods

DO use Spring Data's derived query method naming for simple lookups:

```java
public interface UserRepository extends JpaRepository<User, UUID> {

    Optional<User> findByEmail(String email);

    List<User> findByLastNameAndActive(String lastName, boolean active);

    boolean existsByEmail(String email);

    long countByActive(boolean active);

    Optional<User> findTopByOrderByCreatedAtDesc();
}
```

DO NOT write `@Query` for queries that can be expressed as derived method names.

### @Query with JPQL

DO use JPQL `@Query` for joins, subqueries, and complex predicates:

```java
@Query("SELECT u FROM User u JOIN FETCH u.roles r WHERE u.active = true AND r.name = :roleName")
List<User> findActiveUsersByRole(@Param("roleName") String roleName);

@Query("SELECT u FROM User u WHERE u.createdAt BETWEEN :start AND :end")
Page<User> findByCreatedAtBetween(
    @Param("start") Instant start,
    @Param("end") Instant end,
    Pageable pageable
);
```

DO use `JOIN FETCH` in JPQL when you intentionally need to load a lazy association in one query.

### Native SQL Queries

DO use `nativeQuery = true` only when the query cannot be expressed in JPQL (e.g., database-specific functions, CTEs, window functions).

```java
@Query(
    value = "SELECT * FROM users WHERE LOWER(email) = LOWER(:email)",
    nativeQuery = true
)
Optional<User> findByEmailIgnoreCaseNative(@Param("email") String email);
```

DO annotate the `countQuery` when using native queries with pagination:

```java
@Query(
    value = "SELECT * FROM products WHERE category_id = :categoryId",
    countQuery = "SELECT COUNT(*) FROM products WHERE category_id = :categoryId",
    nativeQuery = true
)
Page<Product> findByCategoryIdNative(@Param("categoryId") UUID categoryId, Pageable pageable);
```

### @Modifying and @Transactional for Mutations

DO annotate bulk update and delete queries with both `@Modifying` and `@Transactional`:

```java
@Modifying
@Transactional
@Query("UPDATE User u SET u.active = false WHERE u.id = :id")
int deactivateUser(@Param("id") UUID id);

@Modifying
@Transactional
@Query("DELETE FROM RefreshToken t WHERE t.expiresAt < :now")
int deleteExpiredTokens(@Param("now") Instant now);
```

DO NOT call `@Modifying` queries without `@Transactional`. It will throw `InvalidDataAccessApiUsageException`.

DO use `clearAutomatically = true` on `@Modifying` when the same transaction reads the modified entity afterward:

```java
@Modifying(clearAutomatically = true)
@Transactional
@Query("UPDATE Product p SET p.stockQuantity = p.stockQuantity - :qty WHERE p.id = :id")
int decrementStock(@Param("id") UUID id, @Param("qty") int qty);
```

### Projection Interfaces

DO use projection interfaces to fetch partial data and reduce query payload:

```java
// Closed projection — only declared fields fetched
public interface UserSummary {
    UUID getId();
    String getFirstName();
    String getLastName();
    String getEmail();
}

// In repository
List<UserSummary> findByActive(boolean active);

// Open projection — SpEL expressions allowed
public interface UserFullName {
    @Value("#{target.firstName + ' ' + target.lastName}")
    String getFullName();
    String getEmail();
}
```

DO prefer closed projections over open projections for performance. Open projections load the full entity.

### Specification Pattern for Dynamic Queries

DO implement `JpaSpecificationExecutor<Entity>` for dynamic filtering:

```java
public interface ProductRepository extends JpaRepository<Product, UUID>,
        JpaSpecificationExecutor<Product> {
}
```

DO define specifications as static factory methods in a dedicated class:

```java
public class ProductSpecifications {

    public static Specification<Product> hasCategory(UUID categoryId) {
        return (root, query, cb) ->
            categoryId == null ? null : cb.equal(root.get("category").get("id"), categoryId);
    }

    public static Specification<Product> isActive() {
        return (root, query, cb) -> cb.isTrue(root.get("active"));
    }

    public static Specification<Product> priceBetween(BigDecimal min, BigDecimal max) {
        return (root, query, cb) -> {
            if (min == null && max == null) return null;
            if (min == null) return cb.lessThanOrEqualTo(root.get("price"), max);
            if (max == null) return cb.greaterThanOrEqualTo(root.get("price"), min);
            return cb.between(root.get("price"), min, max);
        };
    }
}
```

Usage in service layer:

```java
Specification<Product> spec = Specification
    .where(ProductSpecifications.isActive())
    .and(ProductSpecifications.hasCategory(categoryId))
    .and(ProductSpecifications.priceBetween(minPrice, maxPrice));

Page<Product> results = productRepository.findAll(spec, pageable);
```

### Pagination

DO NEVER call `findAll()` without a `Pageable` parameter when the result set can grow unbounded.

```java
// WRONG — never do this for unbounded data
List<User> allUsers = userRepository.findAll();

// CORRECT
Page<User> users = userRepository.findAll(PageRequest.of(page, size, Sort.by("createdAt").descending()));
```

DO define a default page size at the service layer, not the controller layer.

DO NOT accept unbounded `size` values from clients. Cap at a safe maximum (e.g., 100).

---

## Summary Checklist

- [ ] Entity extends `BaseEntity`
- [ ] `@Table(name = "snake_case_plural")` declared
- [ ] UUID primary key via `@GeneratedValue(strategy = GenerationType.UUID)`
- [ ] All `@Column` annotations have `nullable` and `length` declared
- [ ] All relationships declare `fetch = FetchType.LAZY`
- [ ] No `CascadeType.ALL` on `@ManyToMany`
- [ ] `@JsonIgnore` on back-reference side of bidirectional relationships
- [ ] `equals`/`hashCode` based on `id` only (in `BaseEntity`)
- [ ] `toString` excludes collection fields
- [ ] Repository extends `JpaRepository<Entity, UUID>`
- [ ] `@Modifying` queries also annotated with `@Transactional`
- [ ] No unbounded `findAll()` calls
