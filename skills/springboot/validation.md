# Spring Boot Validation Rules

## Overview

This document defines mandatory rules for input validation in Spring Boot applications using Jakarta Bean Validation (formerly Java EE Bean Validation). Validation must be structured, consistent, and applied at the correct layer.

---

## Jakarta Bean Validation Annotations

DO use the following standard annotations from `jakarta.validation.constraints` on request DTO fields:

### Presence and Nullability

| Annotation      | Applies To                        | Behavior                                              |
|-----------------|-----------------------------------|-------------------------------------------------------|
| `@NotNull`      | Any type                          | Rejects `null`. Accepts empty strings and empty lists.|
| `@NotBlank`     | `String`                          | Rejects `null`, `""`, and whitespace-only strings.    |
| `@NotEmpty`     | `String`, `Collection`, `Map`, arrays | Rejects `null` and empty. Does not trim whitespace. |

DO use `@NotBlank` for all string fields where a meaningful value is required.

DO NOT use `@NotNull` alone on string fields when you actually need to reject empty strings. Use `@NotBlank`.

```java
public record CreateUserRequest(
    @NotBlank(message = "First name is required")
    String firstName,

    @NotNull(message = "Role ID is required")  // UUID — NotBlank doesn't apply
    UUID roleId,

    @NotEmpty(message = "Tags must not be empty")
    List<@NotBlank String> tags
) {}
```

### Size and Range

```java
@Size(min = 2, max = 100, message = "Name must be between 2 and 100 characters")
String name;

@Min(value = 1, message = "Quantity must be at least 1")
@Max(value = 9999, message = "Quantity must not exceed 9999")
Integer quantity;

@DecimalMin(value = "0.01", inclusive = true, message = "Price must be greater than 0")
@DecimalMax(value = "999999.99", inclusive = true, message = "Price must not exceed 999999.99")
BigDecimal price;

@Positive(message = "ID must be a positive number")
Long externalId;

@PositiveOrZero(message = "Score must be zero or positive")
Integer score;
```

### Format and Pattern

```java
@Email(message = "Must be a valid email address")
String email;

@Pattern(regexp = "^[A-Z]{2}$", message = "Country code must be a 2-letter ISO code")
String countryCode;

@Pattern(regexp = "^\\+?[1-9]\\d{7,14}$", message = "Invalid phone number format")
String phoneNumber;
```

### Date and Time

```java
@Future(message = "Scheduled date must be in the future")
LocalDateTime scheduledAt;

@Past(message = "Birth date must be in the past")
LocalDate dateOfBirth;

@FutureOrPresent(message = "Start date must be today or in the future")
LocalDate startDate;
```

---

## @Valid on @RequestBody

DO annotate every `@RequestBody` parameter with `@Valid` in controller methods. Without `@Valid`, constraint annotations on the DTO are not evaluated.

```java
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;

    @PostMapping
    public ResponseEntity<UserResponse> create(@RequestBody @Valid CreateUserRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED).body(userService.createUser(request));
    }

    @PutMapping("/{id}")
    public ResponseEntity<UserResponse> update(
            @PathVariable UUID id,
            @RequestBody @Valid UpdateUserRequest request) {
        return ResponseEntity.ok(userService.updateUser(id, request));
    }
}
```

---

## @Validated for Method-Level Validation

DO annotate the controller class with `@Validated` when you need to validate `@PathVariable`, `@RequestParam`, or method parameters (not `@RequestBody`).

```java
@RestController
@RequestMapping("/api/products")
@Validated
public class ProductController {

    @GetMapping("/{id}")
    public ResponseEntity<ProductResponse> findById(
            @PathVariable @NotNull UUID id) {
        return ResponseEntity.ok(productService.findById(id));
    }

    @GetMapping
    public ResponseEntity<PageResponse<ProductResponse>> findAll(
            @RequestParam(defaultValue = "0") @Min(0) int page,
            @RequestParam(defaultValue = "20") @Min(1) @Max(100) int size) {
        return ResponseEntity.ok(productService.findAll(PageRequest.of(page, size)));
    }
}
```

DO NOT use `@Valid` on `@PathVariable` and `@RequestParam`. Use `@Validated` on the class and Jakarta constraints directly on the parameters.

---

## Validation Groups

DO use validation groups when a field has different validation requirements for create vs update operations.

### Define Group Interfaces

```java
public interface ValidationGroups {
    interface Create {}
    interface Update {}
}
```

### Apply Groups to DTO Fields

```java
@Data
@NoArgsConstructor
@AllArgsConstructor
public class UserRequest {

    // Required only on create; ignored on update (ID comes from path variable)
    @NotBlank(groups = ValidationGroups.Create.class)
    @Email(groups = ValidationGroups.Create.class)
    private String email;

    @NotBlank(groups = {ValidationGroups.Create.class, ValidationGroups.Update.class})
    @Size(max = 100, groups = {ValidationGroups.Create.class, ValidationGroups.Update.class})
    private String firstName;

    @NotBlank(groups = ValidationGroups.Create.class)
    @Size(min = 8, max = 64, groups = ValidationGroups.Create.class)
    private String password;
}
```

### Use @Validated with Groups in Controllers

```java
@PostMapping
public ResponseEntity<UserResponse> create(
        @RequestBody @Validated(ValidationGroups.Create.class) UserRequest request) {
    return ResponseEntity.status(HttpStatus.CREATED).body(userService.createUser(request));
}

@PutMapping("/{id}")
public ResponseEntity<UserResponse> update(
        @PathVariable UUID id,
        @RequestBody @Validated(ValidationGroups.Update.class) UserRequest request) {
    return ResponseEntity.ok(userService.updateUser(id, request));
}
```

DO NOT use `@Valid` when using groups. `@Valid` activates the `Default` group only and ignores custom groups. Use `@Validated(Group.class)` from Spring.

---

## Cascaded Validation on Nested Objects

DO annotate nested DTO fields with `@Valid` to trigger cascaded validation into nested objects and collections:

```java
public record CreateOrderRequest(

    @NotNull UUID customerId,

    @NotNull
    @Valid
    ShippingAddressRequest shippingAddress,

    @NotEmpty(message = "Order must contain at least one item")
    @Valid
    List<OrderItemRequest> items
) {}

public record ShippingAddressRequest(
    @NotBlank String street,
    @NotBlank String city,
    @NotBlank @Size(min = 2, max = 2) String stateCode,
    @NotBlank @Pattern(regexp = "\\d{5}(-\\d{4})?") String zipCode
) {}

public record OrderItemRequest(
    @NotNull UUID productId,
    @NotNull @Min(1) Integer quantity
) {}
```

Without `@Valid` on the nested field, nested constraint annotations are silently ignored.

---

## Custom Constraint Validators

DO create custom validators for domain-specific rules that cannot be expressed with standard annotations.

### Step 1: Define the Annotation

```java
@Documented
@Constraint(validatedBy = UniqueEmailValidator.class)
@Target({ElementType.FIELD, ElementType.PARAMETER})
@Retention(RetentionPolicy.RUNTIME)
public @interface UniqueEmail {
    String message() default "Email address is already registered";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}
```

### Step 2: Implement ConstraintValidator

```java
@Component
@RequiredArgsConstructor
public class UniqueEmailValidator implements ConstraintValidator<UniqueEmail, String> {

    private final UserRepository userRepository;

    @Override
    public boolean isValid(String email, ConstraintValidatorContext context) {
        if (email == null || email.isBlank()) {
            return true; // Let @NotBlank handle null/blank separately
        }
        return !userRepository.existsByEmailIgnoreCase(email);
    }
}
```

Usage on DTO:

```java
public record CreateUserRequest(
    @NotBlank @Email @UniqueEmail
    String email
) {}
```

DO NOT perform heavy operations (e.g., network calls, multi-table joins) in validators. Validators are called on every request.

DO return `true` for `null` in custom validators when another annotation (`@NotNull`, `@NotBlank`) handles the null case. This avoids duplicate error messages.

---

## Cross-Field (Class-Level) Validation

DO implement class-level validators for constraints that span multiple fields.

### Step 1: Define the Class-Level Annotation

```java
@Documented
@Constraint(validatedBy = DateRangeValidator.class)
@Target(ElementType.TYPE)
@Retention(RetentionPolicy.RUNTIME)
public @interface ValidDateRange {
    String message() default "End date must be after start date";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
    String startField() default "startDate";
    String endField() default "endDate";
}
```

### Step 2: Implement the Validator

```java
public class DateRangeValidator implements ConstraintValidator<ValidDateRange, Object> {

    private String startField;
    private String endField;

    @Override
    public void initialize(ValidDateRange annotation) {
        this.startField = annotation.startField();
        this.endField = annotation.endField();
    }

    @Override
    public boolean isValid(Object obj, ConstraintValidatorContext context) {
        try {
            LocalDate start = (LocalDate) BeanUtils.getPropertyDescriptor(
                obj.getClass(), startField).getReadMethod().invoke(obj);
            LocalDate end = (LocalDate) BeanUtils.getPropertyDescriptor(
                obj.getClass(), endField).getReadMethod().invoke(obj);

            if (start == null || end == null) return true;

            boolean valid = !end.isBefore(start);
            if (!valid) {
                context.disableDefaultConstraintViolation();
                context.buildConstraintViolationWithTemplate(context.getDefaultConstraintMessageTemplate())
                    .addPropertyNode(endField)
                    .addConstraintViolation();
            }
            return valid;
        } catch (Exception e) {
            return false;
        }
    }
}
```

### Step 3: Apply to DTO

```java
@ValidDateRange(startField = "startDate", endField = "endDate",
                message = "End date must not be before start date")
public record DateRangeRequest(
    @NotNull LocalDate startDate,
    @NotNull LocalDate endDate
) {}
```

---

## Validation Messages in messages.properties

DO externalize all validation messages to support localization and centralized management:

```properties
# src/main/resources/ValidationMessages.properties
user.firstName.required=First name is required
user.firstName.size=First name must be between {min} and {max} characters
user.email.required=Email address is required
user.email.format=Must be a valid email address
user.email.unique=Email address is already registered
user.password.size=Password must be at least {min} characters
product.price.min=Price must be greater than {value}
order.items.notEmpty=Order must contain at least one item
```

Reference messages using `{key}` syntax in annotations:

```java
public record CreateUserRequest(
    @NotBlank(message = "{user.firstName.required}")
    @Size(min = 2, max = 100, message = "{user.firstName.size}")
    String firstName,

    @NotBlank(message = "{user.email.required}")
    @Email(message = "{user.email.format}")
    @UniqueEmail(message = "{user.email.unique}")
    String email
) {}
```

---

## Programmatic Validation with Validator Bean

DO use the `Validator` bean for programmatic validation in service or utility code where annotation-based validation is not triggered automatically:

```java
@Service
@RequiredArgsConstructor
public class ImportServiceImpl implements ImportService {

    private final Validator validator;
    private final UserRepository userRepository;

    @Override
    @Transactional
    public ImportResult importUsers(List<CreateUserRequest> requests) {
        List<String> errors = new ArrayList<>();

        for (int i = 0; i < requests.size(); i++) {
            Set<ConstraintViolation<CreateUserRequest>> violations = validator.validate(requests.get(i));
            if (!violations.isEmpty()) {
                violations.forEach(v ->
                    errors.add("Row " + (i + 1) + " - " + v.getPropertyPath() + ": " + v.getMessage())
                );
            }
        }

        if (!errors.isEmpty()) {
            throw new ValidationException("Import validation failed: " + String.join(", ", errors));
        }

        // proceed with import
        return new ImportResult(requests.size(), 0);
    }
}
```

---

## Service Layer vs Controller Layer Validation

### Controller Layer Responsibility

The controller layer handles:
- **Format validation**: field nullability, size, regex patterns, email format
- Triggered automatically via `@Valid` / `@Validated`
- Results in `MethodArgumentNotValidException` (handled by global exception handler)

### Service Layer Responsibility

The service layer handles:
- **Business rule validation**: uniqueness, referential integrity, state transitions, authorization checks
- Must be explicit, using repository or domain logic
- Results in typed custom exceptions (`ConflictException`, `ValidationException`, etc.)

```java
// Controller — format validation only
@PostMapping
public ResponseEntity<UserResponse> create(@RequestBody @Valid CreateUserRequest request) {
    return ResponseEntity.status(HttpStatus.CREATED).body(userService.createUser(request));
}

// Service — business rule validation
@Override
@Transactional
public UserResponse createUser(CreateUserRequest request) {
    // Business rule: email must be unique
    if (userRepository.existsByEmail(request.email())) {
        throw new ConflictException("Email already registered: " + request.email());
    }

    // Business rule: role must exist
    Role role = roleRepository.findById(request.roleId())
        .orElseThrow(() -> new ResourceNotFoundException("Role", request.roleId()));

    User user = userMapper.toEntity(request);
    user.setRole(role);
    user = userRepository.save(user);
    return userMapper.toResponse(user);
}
```

### What NOT to Do

DO NOT duplicate business rule checks in the controller.

DO NOT perform database lookups (uniqueness checks, existence checks) in constraint validators that run during controller validation. These belong in the service layer to ensure they run inside the transaction.

---

## DTO-Level vs Entity-Level Validation

DO put validation annotations on **both** DTOs and entities, but understand their different purposes:

| Layer        | Purpose                                                                  |
|--------------|--------------------------------------------------------------------------|
| DTO          | Validate incoming HTTP request data before it reaches the service layer  |
| Entity       | Enforce database schema constraints; act as a last line of defense       |

DO NOT rely solely on entity-level validation as a substitute for DTO validation. Entity validation runs late (at flush time) and produces `ConstraintViolationException`, not `MethodArgumentNotValidException`.

```java
// Entity: constraints as schema documentation and safety net
@Entity
@Table(name = "users")
public class User extends BaseEntity {

    @NotBlank       // entity-level: safety net
    @Size(max = 100)
    @Column(name = "first_name", nullable = false, length = 100)
    private String firstName;

    @NotBlank
    @Email
    @Column(name = "email", nullable = false, unique = true, length = 255)
    private String email;
}

// DTO: constraints as the primary API contract
public record CreateUserRequest(
    @NotBlank(message = "First name is required")
    @Size(max = 100, message = "First name must not exceed 100 characters")
    String firstName,

    @NotBlank(message = "Email is required")
    @Email(message = "Must be a valid email address")
    String email
) {}
```

---

## Summary Checklist

- [ ] `@NotBlank` used for string fields (not `@NotNull`)
- [ ] `@Valid` on every `@RequestBody` parameter in controllers
- [ ] `@Validated` on controller class for method-level validation (`@PathVariable`, `@RequestParam`)
- [ ] Validation groups (`Create`, `Update`) used where create/update constraints differ
- [ ] `@Validated(Group.class)` used in controllers when groups are needed (not `@Valid`)
- [ ] `@Valid` on nested DTO fields for cascaded validation
- [ ] Custom validators implement `ConstraintValidator<A, T>` and are Spring `@Component`s
- [ ] Custom validators return `true` for `null` when `@NotNull`/`@NotBlank` handles null separately
- [ ] Class-level constraints used for cross-field validation
- [ ] Validation messages externalized to `ValidationMessages.properties`
- [ ] Controller handles format/syntax validation; service handles business rule validation
- [ ] No database calls inside constraint validators used at the controller layer
- [ ] DTO constraints and entity constraints are both present but serve different purposes
