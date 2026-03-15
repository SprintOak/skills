# Spring Boot Service Layer Rules

## Overview

This document defines mandatory rules for the service layer in Spring Boot applications. The service layer is the heart of business logic. It must be kept clean, testable, and free of infrastructure concerns.

---

## Service Interface + ServiceImpl Pattern

DO define a Java interface for every service and place the implementation in a separate class.

```java
// Interface
public interface UserService {
    UserResponse createUser(CreateUserRequest request);
    UserResponse updateUser(UUID id, UpdateUserRequest request);
    void deleteUser(UUID id);
    UserResponse findById(UUID id);
    Page<UserResponse> findAll(Pageable pageable);
    boolean existsByEmail(String email);
}

// Implementation
@Service
@RequiredArgsConstructor
public class UserServiceImpl implements UserService {
    // ...
}
```

DO place interfaces in the service package and implementations in a `service.impl` sub-package, or co-locate them — choose one convention and be consistent across the project.

DO NOT create a service class without an interface. The interface enables mocking in unit tests and allows proxy-based features (`@Transactional`, `@Async`, AOP) to work correctly.

DO NOT name the interface `IUserService` or `UserServiceInterface`. Use `UserService` for the interface and `UserServiceImpl` for the implementation.

---

## Dependency Injection

DO inject all dependencies via constructor injection using `@RequiredArgsConstructor` (Lombok).

```java
@Service
@RequiredArgsConstructor
public class OrderServiceImpl implements OrderService {

    private final OrderRepository orderRepository;
    private final UserRepository userRepository;
    private final ProductRepository productRepository;
    private final OrderMapper orderMapper;
    private final ApplicationEventPublisher eventPublisher;
}
```

DO NOT use `@Autowired` field injection. It prevents immutability, makes dependencies opaque, and breaks unit testing without a Spring context.

```java
// WRONG — never do this
@Service
public class OrderServiceImpl {
    @Autowired
    private OrderRepository orderRepository;
}
```

DO NOT use setter injection unless dealing with optional dependencies or circular dependency resolution (which itself should be avoided).

DO annotate only the implementation class with `@Service`. Do not annotate the interface.

---

## Return Types: DTOs Only

DO return DTOs from all service methods. Entities must not leak outside the service layer.

```java
// CORRECT
public UserResponse findById(UUID id) {
    User user = userRepository.findById(id)
        .orElseThrow(() -> new ResourceNotFoundException("User", id));
    return userMapper.toResponse(user);
}

// WRONG — returning entity to caller
public User findById(UUID id) {
    return userRepository.findById(id)
        .orElseThrow(() -> new ResourceNotFoundException("User", id));
}
```

DO NOT pass entity objects as parameters to or return values from public service methods. Use request DTOs for input and response DTOs for output.

---

## Method Naming Conventions

DO follow these naming conventions for service methods:

| Operation              | Method Name Pattern           |
|------------------------|-------------------------------|
| Create resource        | `createXxx(XxxRequest)`       |
| Update resource        | `updateXxx(UUID, XxxRequest)` |
| Delete resource        | `deleteXxx(UUID)`             |
| Fetch single by ID     | `findById(UUID)`              |
| Fetch single by field  | `findByEmail(String)`         |
| Fetch paginated list   | `findAll(Pageable)`           |
| Fetch filtered list    | `findAllBy...(params, Pageable)` |
| Check existence        | `existsByXxx(value)`          |

---

## Input Validation

DO validate business rules at the service layer. Constraint annotations (`@NotNull`, `@Size`) belong on request DTOs and are checked at the controller layer. Business logic validation (e.g., "email must be unique") belongs in the service.

```java
public UserResponse createUser(CreateUserRequest request) {
    if (userRepository.existsByEmail(request.email())) {
        throw new ConflictException("A user with this email already exists: " + request.email());
    }
    User user = userMapper.toEntity(request);
    user = userRepository.save(user);
    return userMapper.toResponse(user);
}
```

DO NOT duplicate Jakarta Bean Validation logic (field nullability, size) at the service layer. That is the controller's responsibility via `@Valid`.

---

## Exception Handling

DO throw custom, typed exceptions from service methods. Never throw `RuntimeException` or `Exception` directly.

```java
// WRONG
throw new RuntimeException("User not found");

// CORRECT
throw new ResourceNotFoundException("User", id);
```

DO use a consistent `ResourceNotFoundException` for missing entities:

```java
public UserResponse findById(UUID id) {
    return userRepository.findById(id)
        .map(userMapper::toResponse)
        .orElseThrow(() -> new ResourceNotFoundException("User", id));
}
```

DO throw `ConflictException` for uniqueness violations, `ValidationException` for business rule violations, and `ForbiddenException` for authorization failures.

DO NOT catch and re-wrap exceptions without adding value. Let exceptions propagate to the global exception handler.

---

## Optional Handling

DO use `Optional.orElseThrow()` immediately when the absent case is an error condition. Do not store `Optional` in a variable and then call `isPresent()`.

```java
// CORRECT
User user = userRepository.findByEmail(email)
    .orElseThrow(() -> new ResourceNotFoundException("User not found with email: " + email));

// WRONG — verbose and unnecessary
Optional<User> optionalUser = userRepository.findByEmail(email);
if (optionalUser.isEmpty()) {
    throw new ResourceNotFoundException("...");
}
User user = optionalUser.get();
```

DO use `Optional.map()` and `Optional.orElse()` for non-error optional values:

```java
return userRepository.findByEmail(email)
    .map(userMapper::toResponse)
    .orElse(null);
```

DO NOT call `Optional.get()` without first checking presence. Always use `orElseThrow`, `orElse`, or `orElseGet`.

---

## @Transactional Rules

DO annotate service methods with `@Transactional` (not repositories, not controllers).

```java
@Override
@Transactional
public UserResponse createUser(CreateUserRequest request) {
    // ...
}
```

DO use `@Transactional(readOnly = true)` for all read operations. This provides a performance hint to the persistence provider and prevents accidental writes.

```java
@Override
@Transactional(readOnly = true)
public UserResponse findById(UUID id) {
    // ...
}

@Override
@Transactional(readOnly = true)
public Page<UserResponse> findAll(Pageable pageable) {
    // ...
}
```

DO NOT annotate private methods with `@Transactional`. Spring's proxy mechanism only intercepts public method calls from outside the class. A `@Transactional` annotation on a private method is silently ignored.

```java
// WRONG — @Transactional is ignored on private methods
@Transactional
private void doSomethingInternal() { }
```

DO NOT annotate the entire class with `@Transactional` as a shortcut. Apply it per method so the intent is explicit.

### Proxy Self-Invocation Problem

DO NOT call `@Transactional` (or `@Async`) methods of the same class directly from within that class. The call bypasses the Spring proxy and the annotation has no effect.

```java
// WRONG — self-invocation bypasses the proxy
@Service
public class OrderServiceImpl implements OrderService {

    @Transactional
    public void processOrder(UUID id) {
        this.sendConfirmation(id); // @Transactional on sendConfirmation is ignored
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void sendConfirmation(UUID id) { }
}
```

DO extract the method into a separate Spring bean (service) to ensure proxy interception:

```java
@Service
@RequiredArgsConstructor
public class OrderServiceImpl implements OrderService {

    private final OrderConfirmationService orderConfirmationService;

    @Transactional
    public void processOrder(UUID id) {
        orderConfirmationService.sendConfirmation(id); // proxy intercepts correctly
    }
}
```

---

## Pagination in Service Methods

DO accept `Pageable` as a method parameter and return `Page<XxxResponse>`.

```java
@Override
@Transactional(readOnly = true)
public Page<ProductResponse> findAll(Pageable pageable) {
    return productRepository.findAll(pageable)
        .map(productMapper::toResponse);
}
```

DO validate and cap the page size in the service layer:

```java
@Override
@Transactional(readOnly = true)
public Page<ProductResponse> findAll(Pageable pageable) {
    int safeSize = Math.min(pageable.getPageSize(), 100);
    Pageable safePage = PageRequest.of(pageable.getPageNumber(), safeSize, pageable.getSort());
    return productRepository.findAll(safePage).map(productMapper::toResponse);
}
```

---

## Event Publishing

DO use `ApplicationEventPublisher` to publish domain events from service methods instead of coupling services directly.

```java
@Service
@RequiredArgsConstructor
public class UserServiceImpl implements UserService {

    private final UserRepository userRepository;
    private final UserMapper userMapper;
    private final ApplicationEventPublisher eventPublisher;

    @Override
    @Transactional
    public UserResponse createUser(CreateUserRequest request) {
        User user = userMapper.toEntity(request);
        user = userRepository.save(user);
        eventPublisher.publishEvent(new UserCreatedEvent(this, user.getId(), user.getEmail()));
        return userMapper.toResponse(user);
    }
}
```

DO define event classes as simple records or value objects:

```java
public record UserCreatedEvent(Object source, UUID userId, String email) {}
```

DO annotate event listeners with `@EventListener` (synchronous) or `@TransactionalEventListener` when the listener should run after the transaction commits:

```java
@Component
public class UserCreatedListener {

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void handleUserCreated(UserCreatedEvent event) {
        // send welcome email, provision resources, etc.
    }
}
```

---

## Async Methods

DO annotate methods intended for asynchronous execution with `@Async` and return `CompletableFuture<T>` or `void`.

```java
@Service
@RequiredArgsConstructor
public class EmailServiceImpl implements EmailService {

    @Async
    @Override
    public CompletableFuture<Void> sendWelcomeEmail(String to, String name) {
        // email sending logic
        return CompletableFuture.completedFuture(null);
    }
}
```

DO enable async support in a configuration class:

```java
@Configuration
@EnableAsync
public class AsyncConfig {

    @Bean
    public Executor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(4);
        executor.setMaxPoolSize(16);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("async-");
        executor.initialize();
        return executor;
    }
}
```

DO NOT use `@Async` on methods in the same class that are called internally (same proxy issue as `@Transactional`).

DO NOT fire-and-forget critical operations with `@Async` without proper error handling. Use `CompletableFuture` with `.exceptionally()` or a global `AsyncUncaughtExceptionHandler`.

---

## Full Service Example

```java
@Service
@RequiredArgsConstructor
public class ProductServiceImpl implements ProductService {

    private final ProductRepository productRepository;
    private final CategoryRepository categoryRepository;
    private final ProductMapper productMapper;
    private final ApplicationEventPublisher eventPublisher;

    @Override
    @Transactional
    public ProductResponse createProduct(CreateProductRequest request) {
        Category category = categoryRepository.findById(request.categoryId())
            .orElseThrow(() -> new ResourceNotFoundException("Category", request.categoryId()));

        if (productRepository.existsByNameAndCategoryId(request.name(), request.categoryId())) {
            throw new ConflictException("Product already exists in this category: " + request.name());
        }

        Product product = productMapper.toEntity(request);
        product.setCategory(category);
        product = productRepository.save(product);

        eventPublisher.publishEvent(new ProductCreatedEvent(this, product.getId()));
        return productMapper.toResponse(product);
    }

    @Override
    @Transactional(readOnly = true)
    public ProductResponse findById(UUID id) {
        return productRepository.findById(id)
            .map(productMapper::toResponse)
            .orElseThrow(() -> new ResourceNotFoundException("Product", id));
    }

    @Override
    @Transactional(readOnly = true)
    public Page<ProductResponse> findAll(Pageable pageable) {
        int safeSize = Math.min(pageable.getPageSize(), 100);
        Pageable safe = PageRequest.of(pageable.getPageNumber(), safeSize, pageable.getSort());
        return productRepository.findAll(safe).map(productMapper::toResponse);
    }

    @Override
    @Transactional
    public ProductResponse updateProduct(UUID id, UpdateProductRequest request) {
        Product product = productRepository.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException("Product", id));

        productMapper.updateEntity(request, product);
        product = productRepository.save(product);
        return productMapper.toResponse(product);
    }

    @Override
    @Transactional
    public void deleteProduct(UUID id) {
        if (!productRepository.existsById(id)) {
            throw new ResourceNotFoundException("Product", id);
        }
        productRepository.deleteById(id);
    }
}
```

---

## Summary Checklist

- [ ] Service interface defined; implementation in `XxxServiceImpl`
- [ ] `@Service` only on implementation class
- [ ] Constructor injection via `@RequiredArgsConstructor` (no `@Autowired`)
- [ ] All public methods return DTOs, never entities
- [ ] Custom exceptions thrown (not `RuntimeException`)
- [ ] `@Transactional(readOnly = true)` on all read methods
- [ ] `@Transactional` on all write methods
- [ ] No `@Transactional` on private methods
- [ ] No self-invocation of `@Transactional` or `@Async` methods
- [ ] Pagination capped at service layer
- [ ] Events published via `ApplicationEventPublisher`
- [ ] `@Async` methods on separate beans, return `CompletableFuture`
