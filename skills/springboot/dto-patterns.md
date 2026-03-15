# Spring Boot DTO Patterns

## Overview

This document defines mandatory rules for Data Transfer Object (DTO) design, validation, and mapping in Spring Boot applications. DTOs are the contract between layers. They must be stable, validated, and never confused with entities.

---

## Request vs Response DTOs

DO use separate classes for request and response payloads. They have different validation requirements and different field sets.

| Type           | Naming Pattern     | Purpose                                        |
|----------------|--------------------|------------------------------------------------|
| Request (write)| `XxxRequest`       | Incoming payload for create/update operations  |
| Response (read)| `XxxResponse`      | Outgoing payload returned to clients           |
| Filter/query   | `XxxFilter`        | Query parameters for search/filter operations  |
| Event payload  | `XxxEvent`         | Internal event data (not HTTP-facing)          |

DO NOT reuse the same DTO for both input and output. Input DTOs carry validation annotations; output DTOs carry computed or sensitive fields that should not be writable by clients.

---

## Immutable DTOs with Java Records (Preferred)

DO use Java records for DTOs when the project targets Java 17+. Records are immutable, concise, and naturally suited for data transfer.

```java
// Request DTO
public record CreateUserRequest(
    @NotBlank @Size(max = 100) String firstName,
    @NotBlank @Size(max = 100) String lastName,
    @NotBlank @Email @Size(max = 255) String email,
    @NotBlank @Size(min = 8, max = 64) String password,
    @NotNull UUID roleId
) {}

// Response DTO
public record UserResponse(
    UUID id,
    String firstName,
    String lastName,
    String email,
    String roleName,
    Instant createdAt
) {}
```

DO NOT put `@Autowired`, Spring annotations, or persistence logic inside record DTOs.

### Lombok Alternative

DO use Lombok when records cannot be used (Java < 17, or when mutability is needed for MapStruct `@MappingTarget`):

```java
// Immutable response (equivalent to record)
@Value
@Builder
public class UserResponse {
    UUID id;
    String firstName;
    String lastName;
    String email;
    Instant createdAt;
}

// Mutable request (for MapStruct toUpdateEntity)
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class UpdateUserRequest {
    @NotBlank @Size(max = 100)
    private String firstName;

    @NotBlank @Size(max = 100)
    private String lastName;
}
```

DO NOT use `@Data` on response DTOs if they are meant to be immutable. Use `@Value` or a record.

---

## Never Use Entities as Request/Response Bodies

DO NOT bind `@RequestBody` or return `@ResponseBody` directly to/from entity classes.

```java
// WRONG — exposes entity internals, bypasses validation, risks mass assignment
@PostMapping
public User createUser(@RequestBody User user) { }

// CORRECT
@PostMapping
public ResponseEntity<UserResponse> createUser(@RequestBody @Valid CreateUserRequest request) { }
```

Reasons:
- Entities include fields that must never be client-controlled (e.g., `id`, `createdAt`, `password` hash).
- Entity serialization may trigger lazy-loading outside a transaction.
- It couples the HTTP API to the database schema.

---

## Validation Annotations on Request DTOs

DO annotate all constraint rules directly on the request DTO fields using Jakarta Bean Validation:

```java
public record CreateProductRequest(

    @NotBlank(message = "Product name is required")
    @Size(min = 2, max = 200, message = "Name must be between 2 and 200 characters")
    String name,

    @Size(max = 5000, message = "Description must not exceed 5000 characters")
    String description,

    @NotNull(message = "Price is required")
    @DecimalMin(value = "0.01", message = "Price must be greater than zero")
    @DecimalMax(value = "999999.99", message = "Price must not exceed 999999.99")
    BigDecimal price,

    @NotNull(message = "Stock quantity is required")
    @Min(value = 0, message = "Stock quantity cannot be negative")
    Integer stockQuantity,

    @NotNull(message = "Category ID is required")
    UUID categoryId,

    @Email(message = "Invalid contact email")
    String contactEmail,

    @Pattern(regexp = "^[A-Z]{2,3}$", message = "Currency must be a 2-3 letter ISO code")
    String currency
) {}
```

DO use descriptive, user-facing error messages in all validation annotations.

DO NOT rely on default validation messages (e.g., `"must not be blank"`). They lack context.

---

## @Valid in Controllers

DO annotate `@RequestBody` parameters with `@Valid` in every controller method that accepts a request DTO.

```java
@PostMapping
public ResponseEntity<UserResponse> createUser(@RequestBody @Valid CreateUserRequest request) {
    return ResponseEntity.status(HttpStatus.CREATED).body(userService.createUser(request));
}
```

DO NOT call validation manually with the `Validator` bean in controllers. `@Valid` triggers it automatically.

DO add `@Valid` on `@PathVariable` and `@RequestParam` by annotating the controller class with `@Validated`:

```java
@RestController
@RequestMapping("/api/users")
@Validated
public class UserController {

    @GetMapping("/{id}")
    public ResponseEntity<UserResponse> findById(
        @PathVariable @org.hibernate.validator.constraints.UUID String id) {
        // ...
    }
}
```

---

## Nested DTOs

DO use nested DTO types for complex objects. Do not flatten nested domain concepts.

```java
public record CreateOrderRequest(

    @NotNull UUID customerId,

    @NotNull
    @Valid  // cascade validation into nested DTO
    ShippingAddressRequest shippingAddress,

    @NotEmpty
    @Valid
    List<OrderItemRequest> items
) {}

public record ShippingAddressRequest(
    @NotBlank String street,
    @NotBlank String city,
    @NotBlank @Size(min = 2, max = 2) String stateCode,
    @NotBlank @Pattern(regexp = "\\d{5}(-\\d{4})?") String zipCode,
    @NotBlank @Size(min = 2, max = 2) String countryCode
) {}

public record OrderItemRequest(
    @NotNull UUID productId,
    @NotNull @Min(1) Integer quantity
) {}
```

DO annotate nested DTO fields with `@Valid` to trigger cascaded validation.

---

## Pagination Response DTO

DO define a reusable `PageResponse<T>` wrapper instead of returning `Page<T>` directly (which includes Spring internals in the JSON).

```java
@Value
@Builder
public class PageResponse<T> {
    List<T> content;
    int page;
    int size;
    long totalElements;
    int totalPages;
    boolean first;
    boolean last;

    public static <T> PageResponse<T> from(Page<T> page) {
        return PageResponse.<T>builder()
            .content(page.getContent())
            .page(page.getNumber())
            .size(page.getSize())
            .totalElements(page.getTotalElements())
            .totalPages(page.getTotalPages())
            .first(page.isFirst())
            .last(page.isLast())
            .build();
    }
}
```

Usage in service:

```java
public PageResponse<ProductResponse> findAll(Pageable pageable) {
    return PageResponse.from(
        productRepository.findAll(pageable).map(productMapper::toResponse)
    );
}
```

DO NOT return `Map<String, Object>` as a response body. It defeats type safety, breaks client code generation, and makes API contracts unenforceable.

---

## MapStruct for Entity-DTO Mapping

DO use MapStruct for all entity-DTO conversions. Do not write manual mapping code.

### Mapper Configuration

DO use `componentModel = "spring"` so mappers are Spring beans and can be injected:

```java
@Mapper(componentModel = "spring")
public interface UserMapper {

    UserResponse toResponse(User user);

    User toEntity(CreateUserRequest request);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    @Mapping(target = "password", ignore = true)
    void updateEntity(UpdateUserRequest request, @MappingTarget User user);

    List<UserResponse> toResponseList(List<User> users);
}
```

DO ignore auto-managed fields (`id`, `createdAt`, `updatedAt`) when mapping from request to entity.

DO NOT set `id` from a request DTO. It must be generated by the persistence layer.

### Handling Relationships in Mapping

DO map foreign key IDs from nested entities explicitly:

```java
@Mapper(componentModel = "spring")
public interface OrderMapper {

    @Mapping(target = "customerId", source = "customer.id")
    @Mapping(target = "customerName", expression = "java(order.getCustomer().getFirstName() + ' ' + order.getCustomer().getLastName())")
    OrderResponse toResponse(Order order);
}
```

### Custom Mapping Methods with @Named

DO use `@Named` for reusable conversion logic:

```java
@Mapper(componentModel = "spring")
public interface ProductMapper {

    @Mapping(target = "categoryName", source = "category.name")
    @Mapping(target = "priceFormatted", source = "price", qualifiedByName = "formatPrice")
    ProductResponse toResponse(Product product);

    @Named("formatPrice")
    default String formatPrice(BigDecimal price) {
        return price == null ? null : "$" + price.setScale(2, RoundingMode.HALF_UP);
    }
}
```

### Bidirectional Mapping

DO provide `toEntity`, `toResponse`, and `updateEntity` (using `@MappingTarget`) methods in every mapper:

```java
@Mapper(componentModel = "spring")
public interface CategoryMapper {

    CategoryResponse toResponse(Category category);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    Category toEntity(CreateCategoryRequest request);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    void updateEntity(UpdateCategoryRequest request, @MappingTarget Category category);

    List<CategoryResponse> toResponseList(List<Category> categories);
}
```

DO NOT mix `toEntity` and `updateEntity` into one method. They serve different purposes: `toEntity` creates a new instance; `updateEntity` mutates an existing managed entity.

### MapStruct with Lombok

DO add the `lombok-mapstruct-binding` annotation processor dependency and declare annotation processors in the correct order (Lombok before MapStruct) in `pom.xml` or `build.gradle`:

```xml
<!-- Maven -->
<dependency>
    <groupId>org.projectlombok</groupId>
    <artifactId>lombok-mapstruct-binding</artifactId>
    <version>0.2.0</version>
</dependency>
```

---

## Field Naming Conventions

DO use `camelCase` in both Java DTO fields and JSON output. Spring Boot's default Jackson configuration handles this automatically.

DO NOT use `snake_case` in Java field names. If the client requires `snake_case` JSON, configure Jackson globally:

```java
@Bean
public Jackson2ObjectMapperBuilderCustomizer jacksonCustomizer() {
    return builder -> builder.propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE);
}
```

DO NOT mix naming conventions within the same project.

---

## Avoid Map<String, Object> as Response

DO NOT use `Map<String, Object>`, `HashMap`, or untyped `JsonNode` as controller response bodies.

```java
// WRONG
@GetMapping("/{id}")
public Map<String, Object> getUser(@PathVariable UUID id) {
    Map<String, Object> response = new HashMap<>();
    response.put("id", user.getId());
    response.put("email", user.getEmail());
    return response;
}

// CORRECT
@GetMapping("/{id}")
public ResponseEntity<UserResponse> getUser(@PathVariable UUID id) {
    return ResponseEntity.ok(userService.findById(id));
}
```

---

## Full Example: Create + Response DTOs with Mapper

```java
// Request DTO
public record CreateUserRequest(
    @NotBlank @Size(max = 100) String firstName,
    @NotBlank @Size(max = 100) String lastName,
    @NotBlank @Email @Size(max = 255) String email,
    @NotBlank @Size(min = 8, max = 64) String password
) {}

// Update request
@Data
@NoArgsConstructor
@AllArgsConstructor
public class UpdateUserRequest {
    @NotBlank @Size(max = 100) private String firstName;
    @NotBlank @Size(max = 100) private String lastName;
}

// Response DTO
public record UserResponse(
    UUID id,
    String firstName,
    String lastName,
    String email,
    Instant createdAt,
    Instant updatedAt
) {}

// Mapper
@Mapper(componentModel = "spring")
public interface UserMapper {

    UserResponse toResponse(User user);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    User toEntity(CreateUserRequest request);

    @Mapping(target = "id", ignore = true)
    @Mapping(target = "createdAt", ignore = true)
    @Mapping(target = "updatedAt", ignore = true)
    @Mapping(target = "email", ignore = true)
    @Mapping(target = "password", ignore = true)
    void updateEntity(UpdateUserRequest request, @MappingTarget User user);

    List<UserResponse> toResponseList(List<User> users);
}
```

---

## Summary Checklist

- [ ] Separate `XxxRequest` and `XxxResponse` classes for every resource
- [ ] Records (Java 17+) or Lombok `@Value`/`@Data` used — not plain POJOs with getters/setters
- [ ] No entity used as request or response body
- [ ] All `@RequestBody` parameters annotated with `@Valid`
- [ ] Validation annotations on all request DTO fields with descriptive messages
- [ ] Nested DTOs annotated with `@Valid` for cascade validation
- [ ] `PageResponse<T>` wrapper for paginated endpoints
- [ ] No `Map<String, Object>` as response body
- [ ] MapStruct mapper with `componentModel = "spring"` for all mappings
- [ ] `id`, `createdAt`, `updatedAt` ignored in `toEntity` and `updateEntity`
- [ ] `updateEntity` uses `@MappingTarget`
- [ ] List mapping method provided in each mapper
