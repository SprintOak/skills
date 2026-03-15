# Spring Boot Logging — AI Agent Context

This file defines the authoritative patterns for logging in Spring Boot applications.
Agents MUST follow these patterns when generating or modifying any logging-related code.

---

## Core Principles

- Use SLF4J as the logging facade. Spring Boot includes it by default with Logback as the implementation.
- NEVER use `System.out.println` or `System.err.println`.
- NEVER log sensitive data: passwords, tokens, credit card numbers, PII (emails, phone numbers, SSNs).
- Always use parameterized logging. Never use string concatenation in log statements.
- Use MDC to propagate contextual data (request ID, user ID, trace ID) through the request lifecycle.
- Log at the appropriate level: do not log everything at INFO or ERROR.

---

## Logger Declaration

### Option 1: Manual (no Lombok)

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Service
public class OrderService {

    private static final Logger log = LoggerFactory.getLogger(OrderService.class);

    // ...
}
```

### Option 2: Lombok @Slf4j (preferred when Lombok is available)

```java
import lombok.extern.slf4j.Slf4j;

@Slf4j
@Service
public class OrderService {
    // log is auto-generated as: private static final Logger log = LoggerFactory.getLogger(OrderService.class);
}
```

DO:
- Declare loggers as `private static final`.
- Name the logger after the declaring class using `getLogger(Xxx.class)`.
- Use `@Slf4j` when Lombok is already a project dependency.

DON'T:
- NEVER use `System.out.println`.
- NEVER use `java.util.logging.Logger` or `log4j.Logger` directly — always use SLF4J.
- NEVER declare a non-static logger (creates a new instance per object).

---

## Log Levels — When to Use Each

| Level | When to Use |
|-------|-------------|
| `TRACE` | Very fine-grained diagnostic output. Method entry/exit with full parameter values. Usually disabled in production. |
| `DEBUG` | Diagnostic info useful during development: query results, internal state transitions, loop iterations. Disabled in production by default. |
| `INFO`  | High-level application events: service started, job completed, user authenticated, order placed. Always enabled in production. |
| `WARN`  | Something unexpected but recoverable: deprecated API used, retry attempt, fallback behavior triggered, near-capacity thresholds. |
| `ERROR` | Failures that prevent a specific operation from completing: uncaught exceptions, external service failures, data corruption detected. Always log with the exception. |

```java
// TRACE — method-level detail, usually only in dev
log.trace("Entering findOrderById with id={}", orderId);

// DEBUG — useful diagnostic info
log.debug("Fetched {} orders for userId={}", orders.size(), userId);

// INFO — significant business event
log.info("Order placed: orderId={}, userId={}, total={}", order.getId(), userId, order.getTotal());

// WARN — unexpected but non-fatal
log.warn("Payment retry attempt {}/3 for orderId={}", attempt, orderId);

// ERROR — failure with full exception
log.error("Failed to process payment for orderId={}", orderId, e);
```

DO:
- Always pass the exception as the last argument (not `e.getMessage()`), so the full stack trace is logged.
- Use INFO for observable business milestones.
- Use WARN when a fallback or retry is triggered.

DON'T:
- NEVER use `log.error("Error: " + e.getMessage())` — this discards the stack trace.
- NEVER log at ERROR for expected business validation failures (e.g., "email already taken") — use WARN or DEBUG.

---

## Parameterized Logging (Performance)

```java
// CORRECT — SLF4J defers string construction until the level is enabled
log.debug("Processing order: id={}, items={}, userId={}", order.getId(), order.getItemCount(), userId);

// WRONG — string is always concatenated, even if DEBUG is disabled
log.debug("Processing order: id=" + order.getId() + ", items=" + order.getItemCount());

// WRONG — use {} placeholders, not String.format
log.info(String.format("User %s logged in", username));
```

DO:
- Always use `{}` placeholder syntax.
- Pass variables as arguments after the message template.

DON'T:
- NEVER concatenate strings inline in log statements.
- NEVER wrap log statements in `if (log.isDebugEnabled())` unless the argument computation itself is expensive (e.g., involves a method call that serializes an entire object).

---

## Never Log Sensitive Data

```java
// WRONG
log.info("User login: email={}, password={}", email, password);
log.debug("Auth token: {}", jwtToken);
log.info("Card number: {}", creditCardNumber);

// CORRECT
log.info("User login attempt: email={}", email);
log.debug("Authentication successful for userId={}", userId);
log.info("Payment processed for userId={} with masked card ending in {}", userId, maskedLast4);
```

NEVER log:
- Passwords or password hashes
- JWT tokens or API keys
- Full credit card numbers (PCI-DSS)
- Social security numbers or national IDs
- Full email addresses in DEBUG/TRACE where unnecessary
- Raw request bodies that may contain any of the above

---

## MDC — Structured Contextual Logging

MDC (Mapped Diagnostic Context) attaches key-value pairs to the current thread's log output.
Always populate MDC at the boundary of each request so all logs within the request share the same context.

### Request Logging Filter with MDC

```java
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestLoggingFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(RequestLoggingFilter.class);

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        String requestId = Optional.ofNullable(request.getHeader("X-Request-Id"))
            .orElse(UUID.randomUUID().toString());

        MDC.put("requestId", requestId);
        MDC.put("method", request.getMethod());
        MDC.put("uri", request.getRequestURI());

        // Set after authentication if needed; update when user is resolved
        String userId = extractUserIdFromContext();
        if (userId != null) {
            MDC.put("userId", userId);
        }

        response.setHeader("X-Request-Id", requestId);

        long startTime = System.currentTimeMillis();
        try {
            filterChain.doFilter(request, response);
        } finally {
            long duration = System.currentTimeMillis() - startTime;
            MDC.put("durationMs", String.valueOf(duration));
            MDC.put("status", String.valueOf(response.getStatus()));
            log.info("Request completed");
            MDC.clear(); // ALWAYS clear MDC after the request completes
        }
    }

    private String extractUserIdFromContext() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth != null && auth.isAuthenticated() && auth.getPrincipal() instanceof User user) {
            return user.getId().toString();
        }
        return null;
    }
}
```

DO:
- Always call `MDC.clear()` in a `finally` block after the request is complete.
- Propagate a `requestId` from incoming headers or generate one if absent.
- Echo the `requestId` back in the response headers for client correlation.
- Include `userId`, `traceId`, `method`, and `uri` in MDC where applicable.

DON'T:
- NEVER leave MDC populated after a request — it leaks into subsequent requests on thread pool reuse.
- NEVER put sensitive values (tokens, passwords) into MDC.

---

## Service Method Logging Pattern

```java
@Slf4j
@Service
@RequiredArgsConstructor
public class OrderService {

    private final OrderRepository orderRepository;

    public Order createOrder(CreateOrderRequest request, UUID userId) {
        log.debug("Creating order for userId={}, itemCount={}", userId, request.getItems().size());

        Order order = Order.builder()
            .userId(userId)
            .items(request.getItems())
            .status(OrderStatus.PENDING)
            .build();

        Order saved = orderRepository.save(order);

        log.info("Order created: orderId={}, userId={}", saved.getId(), userId);
        return saved;
    }

    public void cancelOrder(UUID orderId, UUID userId) {
        log.debug("Cancelling orderId={} by userId={}", orderId, userId);

        Order order = orderRepository.findById(orderId)
            .orElseThrow(() -> {
                log.warn("Cancel failed — order not found: orderId={}", orderId);
                return new OrderNotFoundException(orderId);
            });

        try {
            order.cancel();
            orderRepository.save(order);
            log.info("Order cancelled: orderId={}, userId={}", orderId, userId);
        } catch (IllegalStateException e) {
            log.error("Failed to cancel order: orderId={}, currentStatus={}", orderId, order.getStatus(), e);
            throw e;
        }
    }
}
```

---

## Logback Configuration

### Option 1: application.yaml (simple level configuration)

```yaml
logging:
  level:
    root: INFO
    com.example.myapp: DEBUG
    com.example.myapp.repository: INFO
    org.springframework.security: DEBUG   # enable only during dev
    org.hibernate.SQL: DEBUG              # log SQL in dev only
    org.hibernate.type.descriptor.sql: TRACE  # log bind params
  file:
    name: logs/application.log
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level [%X{requestId}] %logger{36} - %msg%n"
    file: "%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level [%X{requestId}] [%X{userId}] %logger{36} - %msg%n"
```

### Option 2: logback-spring.xml (full control — production recommended)

Place at `src/main/resources/logback-spring.xml`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>

    <springProfile name="default,dev">
        <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
            <encoder>
                <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level [%X{requestId}] %logger{36} - %msg%n</pattern>
            </encoder>
        </appender>

        <root level="INFO">
            <appender-ref ref="CONSOLE"/>
        </root>
        <logger name="com.example.myapp" level="DEBUG"/>
    </springProfile>

    <springProfile name="prod">
        <!-- JSON structured logging for log aggregation systems (ELK, Datadog, etc.) -->
        <appender name="JSON_CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
            <encoder class="net.logstash.logback.encoder.LogstashEncoder">
                <includeCallerData>false</includeCallerData>
                <includeMdcKeyNames>requestId,userId,traceId,method,uri,status,durationMs</includeMdcKeyNames>
            </encoder>
        </appender>

        <!-- Rolling file appender -->
        <appender name="ROLLING_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
            <file>logs/application.log</file>
            <rollingPolicy class="ch.qos.logback.core.rolling.TimeBasedRollingPolicy">
                <fileNamePattern>logs/application-%d{yyyy-MM-dd}.%i.log.gz</fileNamePattern>
                <timeBasedFileNamingAndTriggeringPolicy
                        class="ch.qos.logback.core.rolling.SizeAndTimeBasedFNATP">
                    <maxFileSize>100MB</maxFileSize>
                </timeBasedFileNamingAndTriggeringPolicy>
                <maxHistory>30</maxHistory>
                <totalSizeCap>3GB</totalSizeCap>
            </rollingPolicy>
            <encoder class="net.logstash.logback.encoder.LogstashEncoder"/>
        </appender>

        <root level="INFO">
            <appender-ref ref="JSON_CONSOLE"/>
            <appender-ref ref="ROLLING_FILE"/>
        </root>
    </springProfile>

</configuration>
```

DO:
- Use `logback-spring.xml` (not `logback.xml`) to leverage Spring's `<springProfile>` support.
- In production, output JSON format using `logstash-logback-encoder` for ELK/Splunk/Datadog ingestion.
- Configure rolling file policies with `maxHistory` and `totalSizeCap` to prevent disk exhaustion.
- Use separate log levels per environment via Spring profiles.

DON'T:
- NEVER use `logback.xml` if you need `<springProfile>` — it loads before Spring context.
- NEVER set root level to `DEBUG` in production.
- NEVER log to a file without rotation policy.

---

## JSON Logging Dependency

```xml
<dependency>
    <groupId>net.logstash.logback</groupId>
    <artifactId>logstash-logback-encoder</artifactId>
    <version>8.0</version>
</dependency>
```

---

## Package-Level Log Level Examples

```yaml
logging:
  level:
    # Application packages
    com.example.myapp.service: DEBUG
    com.example.myapp.repository: INFO
    com.example.myapp.controller: INFO
    com.example.myapp.security: WARN

    # Framework packages (only enable during troubleshooting)
    org.springframework.web: WARN
    org.springframework.security: WARN
    org.springframework.data.jpa: DEBUG   # dev only
    org.hibernate.SQL: DEBUG              # dev only
    org.hibernate.type: TRACE            # dev only (logs bind parameters)
    com.zaxxer.hikari: WARN
```

---

## Async and Thread Boundary MDC Propagation

MDC is thread-local. When using `@Async`, `CompletableFuture`, or thread pools, MDC must be copied manually.

```java
@Configuration
@EnableAsync
public class AsyncConfig {

    @Bean
    public Executor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(5);
        executor.setMaxPoolSize(10);
        executor.setTaskDecorator(new MdcTaskDecorator());
        executor.initialize();
        return executor;
    }
}

public class MdcTaskDecorator implements TaskDecorator {

    @Override
    public Runnable decorate(Runnable runnable) {
        Map<String, String> contextMap = MDC.getCopyOfContextMap();
        return () -> {
            try {
                if (contextMap != null) {
                    MDC.setContextMap(contextMap);
                }
                runnable.run();
            } finally {
                MDC.clear();
            }
        };
    }
}
```

DO:
- Always use `MdcTaskDecorator` on `ThreadPoolTaskExecutor` beans.
- Copy MDC before submitting tasks; clear it in the worker's `finally` block.

---

## Summary Checklist

- [ ] All loggers declared as `private static final Logger log` or `@Slf4j`
- [ ] No `System.out.println` anywhere in the codebase
- [ ] Parameterized logging used exclusively (no string concatenation)
- [ ] No sensitive data in log statements
- [ ] MDC populated and cleared in a request filter
- [ ] `logback-spring.xml` used for environment-specific configuration
- [ ] JSON format enabled for the `prod` profile
- [ ] Rolling file appender with rotation and size caps for production
- [ ] Exceptions logged with full stack trace as the last argument to `log.error`
- [ ] Root log level is INFO in production; package-specific levels for application code
