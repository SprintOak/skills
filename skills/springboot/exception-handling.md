# Spring Boot Exception Handling Rules

## Overview

This document defines mandatory rules for exception design, global exception handling, and error response formatting in Spring Boot applications. Consistent, well-structured error responses are critical for API consumers and operational debugging.

---

## Custom Exception Hierarchy

DO define a typed exception hierarchy rooted at a common `AppException` base class. Every exception in the application must extend this hierarchy.

```
AppException (abstract, extends RuntimeException)
├── ResourceNotFoundException        → 404 Not Found
├── ValidationException              → 422 Unprocessable Entity
├── ConflictException                → 409 Conflict
├── BadRequestException              → 400 Bad Request
├── UnauthorizedException            → 401 Unauthorized
└── ForbiddenException               → 403 Forbidden
```

DO NOT throw `RuntimeException`, `IllegalArgumentException`, or `IllegalStateException` from service or controller code. These exceptions have no HTTP status mapping and produce 500 errors.

### Base Exception

```java
public abstract class AppException extends RuntimeException {

    private final HttpStatus status;

    protected AppException(String message, HttpStatus status) {
        super(message);
        this.status = status;
    }

    protected AppException(String message, HttpStatus status, Throwable cause) {
        super(message, cause);
        this.status = status;
    }

    public HttpStatus getStatus() {
        return status;
    }
}
```

### Concrete Exception Classes

```java
public class ResourceNotFoundException extends AppException {

    public ResourceNotFoundException(String message) {
        super(message, HttpStatus.NOT_FOUND);
    }

    public ResourceNotFoundException(String resourceName, UUID id) {
        super(resourceName + " not found with id: " + id, HttpStatus.NOT_FOUND);
    }

    public ResourceNotFoundException(String resourceName, String field, Object value) {
        super(resourceName + " not found with " + field + ": " + value, HttpStatus.NOT_FOUND);
    }
}

public class ConflictException extends AppException {
    public ConflictException(String message) {
        super(message, HttpStatus.CONFLICT);
    }
}

public class ValidationException extends AppException {
    public ValidationException(String message) {
        super(message, HttpStatus.UNPROCESSABLE_ENTITY);
    }
}

public class BadRequestException extends AppException {
    public BadRequestException(String message) {
        super(message, HttpStatus.BAD_REQUEST);
    }
}

public class UnauthorizedException extends AppException {
    public UnauthorizedException(String message) {
        super(message, HttpStatus.UNAUTHORIZED);
    }
}

public class ForbiddenException extends AppException {
    public ForbiddenException(String message) {
        super(message, HttpStatus.FORBIDDEN);
    }
}
```

DO NOT annotate custom exceptions with `@ResponseStatus`. HTTP status is managed by `AppException` fields and mapped centrally in the global handler.

---

## Standard Error Response Structure

DO use a single, consistent `ErrorResponse` structure for all error responses.

```java
@Value
@Builder
@JsonInclude(JsonInclude.Include.NON_NULL)
public class ErrorResponse {
    Instant timestamp;
    int status;
    String error;
    String message;
    String path;
    List<FieldError> details;  // present only for validation errors

    @Value
    @Builder
    public static class FieldError {
        String field;
        Object rejectedValue;
        String message;
    }
}
```

The JSON structure produced:

```json
{
  "timestamp": "2026-03-14T10:23:45.123Z",
  "status": 422,
  "error": "Unprocessable Entity",
  "message": "Validation failed for 2 field(s)",
  "path": "/api/users",
  "details": [
    {
      "field": "email",
      "rejectedValue": "not-an-email",
      "message": "must be a well-formed email address"
    },
    {
      "field": "firstName",
      "rejectedValue": "",
      "message": "must not be blank"
    }
  ]
}
```

DO NOT include Java stack traces, class names, or internal package paths in error responses. These expose system internals.

DO NOT use `Map<String, Object>` as the error response body. It is untyped and inconsistent.

---

## Global Exception Handler

DO define a single `@RestControllerAdvice` class that handles all exceptions. Do not scatter `@ExceptionHandler` across controllers.

```java
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    // -------------------------------------------------------------------------
    // Application-defined exceptions
    // -------------------------------------------------------------------------

    @ExceptionHandler(AppException.class)
    public ResponseEntity<ErrorResponse> handleAppException(
            AppException ex, HttpServletRequest request) {

        HttpStatus status = ex.getStatus();
        logException(ex, status);

        return ResponseEntity.status(status).body(ErrorResponse.builder()
            .timestamp(Instant.now())
            .status(status.value())
            .error(status.getReasonPhrase())
            .message(ex.getMessage())
            .path(request.getRequestURI())
            .build());
    }

    // -------------------------------------------------------------------------
    // Jakarta Bean Validation — @Valid on @RequestBody
    // -------------------------------------------------------------------------

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(
            MethodArgumentNotValidException ex, HttpServletRequest request) {

        List<ErrorResponse.FieldError> details = ex.getBindingResult()
            .getFieldErrors()
            .stream()
            .map(fe -> ErrorResponse.FieldError.builder()
                .field(fe.getField())
                .rejectedValue(fe.getRejectedValue())
                .message(fe.getDefaultMessage())
                .build())
            .toList();

        log.warn("Validation failed for request {}: {} error(s)", request.getRequestURI(), details.size());

        return ResponseEntity.status(HttpStatus.UNPROCESSABLE_ENTITY).body(ErrorResponse.builder()
            .timestamp(Instant.now())
            .status(HttpStatus.UNPROCESSABLE_ENTITY.value())
            .error("Unprocessable Entity")
            .message("Validation failed for " + details.size() + " field(s)")
            .path(request.getRequestURI())
            .details(details)
            .build());
    }

    // -------------------------------------------------------------------------
    // @Validated method-level constraint violations
    // -------------------------------------------------------------------------

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ErrorResponse> handleConstraintViolation(
            ConstraintViolationException ex, HttpServletRequest request) {

        List<ErrorResponse.FieldError> details = ex.getConstraintViolations()
            .stream()
            .map(cv -> ErrorResponse.FieldError.builder()
                .field(extractFieldName(cv.getPropertyPath().toString()))
                .rejectedValue(cv.getInvalidValue())
                .message(cv.getMessage())
                .build())
            .toList();

        log.warn("Constraint violation at {}: {}", request.getRequestURI(), ex.getMessage());

        return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(ErrorResponse.builder()
            .timestamp(Instant.now())
            .status(HttpStatus.BAD_REQUEST.value())
            .error("Bad Request")
            .message("Constraint violation: " + details.size() + " error(s)")
            .path(request.getRequestURI())
            .details(details)
            .build());
    }

    // -------------------------------------------------------------------------
    // Malformed JSON body
    // -------------------------------------------------------------------------

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ErrorResponse> handleNotReadable(
            HttpMessageNotReadableException ex, HttpServletRequest request) {

        log.warn("Unreadable HTTP message at {}: {}", request.getRequestURI(), ex.getMessage());

        return ResponseEntity.badRequest().body(ErrorResponse.builder()
            .timestamp(Instant.now())
            .status(HttpStatus.BAD_REQUEST.value())
            .error("Bad Request")
            .message("Malformed or unreadable request body")
            .path(request.getRequestURI())
            .build());
    }

    // -------------------------------------------------------------------------
    // 404 No Handler Found
    // -------------------------------------------------------------------------

    @ExceptionHandler(NoHandlerFoundException.class)
    public ResponseEntity<ErrorResponse> handleNoHandlerFound(
            NoHandlerFoundException ex, HttpServletRequest request) {

        log.warn("No handler found for {} {}", ex.getHttpMethod(), ex.getRequestURL());

        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(ErrorResponse.builder()
            .timestamp(Instant.now())
            .status(HttpStatus.NOT_FOUND.value())
            .error("Not Found")
            .message("No endpoint found for " + ex.getHttpMethod() + " " + ex.getRequestURL())
            .path(request.getRequestURI())
            .build());
    }

    // -------------------------------------------------------------------------
    // Wrong HTTP method
    // -------------------------------------------------------------------------

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ErrorResponse> handleMethodNotSupported(
            HttpRequestMethodNotSupportedException ex, HttpServletRequest request) {

        log.warn("Method not supported: {} at {}", ex.getMethod(), request.getRequestURI());

        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED).body(ErrorResponse.builder()
            .timestamp(Instant.now())
            .status(HttpStatus.METHOD_NOT_ALLOWED.value())
            .error("Method Not Allowed")
            .message(ex.getMessage())
            .path(request.getRequestURI())
            .build());
    }

    // -------------------------------------------------------------------------
    // File upload size exceeded
    // -------------------------------------------------------------------------

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ResponseEntity<ErrorResponse> handleMaxUploadSize(
            MaxUploadSizeExceededException ex, HttpServletRequest request) {

        log.warn("Upload size exceeded at {}", request.getRequestURI());

        return ResponseEntity.status(HttpStatus.PAYLOAD_TOO_LARGE).body(ErrorResponse.builder()
            .timestamp(Instant.now())
            .status(HttpStatus.PAYLOAD_TOO_LARGE.value())
            .error("Payload Too Large")
            .message("Uploaded file exceeds the maximum allowed size")
            .path(request.getRequestURI())
            .build());
    }

    // -------------------------------------------------------------------------
    // Database integrity violations (unique constraint, FK violation)
    // -------------------------------------------------------------------------

    @ExceptionHandler(DataIntegrityViolationException.class)
    public ResponseEntity<ErrorResponse> handleDataIntegrityViolation(
            DataIntegrityViolationException ex, HttpServletRequest request) {

        log.warn("Data integrity violation at {}: {}", request.getRequestURI(), ex.getMostSpecificCause().getMessage());

        return ResponseEntity.status(HttpStatus.CONFLICT).body(ErrorResponse.builder()
            .timestamp(Instant.now())
            .status(HttpStatus.CONFLICT.value())
            .error("Conflict")
            .message("A data integrity constraint was violated. The operation could not be completed.")
            .path(request.getRequestURI())
            .build());
    }

    // -------------------------------------------------------------------------
    // Spring Security — access denied
    // -------------------------------------------------------------------------

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ErrorResponse> handleAccessDenied(
            AccessDeniedException ex, HttpServletRequest request) {

        log.warn("Access denied at {}: {}", request.getRequestURI(), ex.getMessage());

        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(ErrorResponse.builder()
            .timestamp(Instant.now())
            .status(HttpStatus.FORBIDDEN.value())
            .error("Forbidden")
            .message("You do not have permission to perform this action")
            .path(request.getRequestURI())
            .build());
    }

    // -------------------------------------------------------------------------
    // Spring Security — authentication failure
    // -------------------------------------------------------------------------

    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<ErrorResponse> handleAuthentication(
            AuthenticationException ex, HttpServletRequest request) {

        log.warn("Authentication failure at {}: {}", request.getRequestURI(), ex.getMessage());

        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(ErrorResponse.builder()
            .timestamp(Instant.now())
            .status(HttpStatus.UNAUTHORIZED.value())
            .error("Unauthorized")
            .message("Authentication is required to access this resource")
            .path(request.getRequestURI())
            .build());
    }

    // -------------------------------------------------------------------------
    // Catch-all fallback — never expose internals
    // -------------------------------------------------------------------------

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGenericException(
            Exception ex, HttpServletRequest request) {

        log.error("Unhandled exception at {}: {}", request.getRequestURI(), ex.getMessage(), ex);

        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(ErrorResponse.builder()
            .timestamp(Instant.now())
            .status(HttpStatus.INTERNAL_SERVER_ERROR.value())
            .error("Internal Server Error")
            .message("An unexpected error occurred. Please try again later.")
            .path(request.getRequestURI())
            .build());
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private void logException(AppException ex, HttpStatus status) {
        if (status.is4xxClientError()) {
            log.warn("Client error [{}]: {}", status.value(), ex.getMessage());
        } else {
            log.error("Server error [{}]: {}", status.value(), ex.getMessage(), ex);
        }
    }

    private String extractFieldName(String propertyPath) {
        int lastDot = propertyPath.lastIndexOf('.');
        return lastDot >= 0 ? propertyPath.substring(lastDot + 1) : propertyPath;
    }
}
```

### Logging Levels

DO log 4xx responses at WARN level and 5xx responses at ERROR level.

DO NOT log 4xx exceptions with full stack traces. The stack trace is noise for client errors.

DO log 5xx exceptions with full stack traces (`log.error("...", ex)`).

DO NOT log sensitive data (passwords, tokens, PII) in exception messages or log statements.

---

## Hiding Stack Traces in Production

DO configure Spring Boot to never include stack traces in the response body:

```yaml
# application.yml
server:
  error:
    include-stacktrace: never
    include-message: never   # also suppress Spring's default "message" field
    include-binding-errors: never
```

DO NOT set `include-stacktrace: on-param` or `include-stacktrace: always` in production profiles.

---

## DataIntegrityViolationException vs ConflictException

DO throw `ConflictException` proactively in service code when you can detect the conflict before hitting the database (e.g., `existsByEmail` check before insert). This produces a clean, user-facing error message.

DO handle `DataIntegrityViolationException` in the global handler as a safety net for race conditions or constraints not checked at the service layer. Return a generic conflict message without exposing constraint names.

---

## RFC 7807 Problem+JSON (Optional)

DO consider adopting RFC 7807 Problem+JSON for APIs consumed by external parties or OpenAPI clients. Spring 6 / Spring Boot 3 includes built-in support via `ProblemDetail`.

```java
// Using Spring's built-in ProblemDetail
@ExceptionHandler(ResourceNotFoundException.class)
public ProblemDetail handleNotFound(ResourceNotFoundException ex, HttpServletRequest request) {
    ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, ex.getMessage());
    problem.setTitle("Resource Not Found");
    problem.setInstance(URI.create(request.getRequestURI()));
    return problem;
}
```

DO NOT mix `ProblemDetail` responses with custom `ErrorResponse` responses. Choose one format and use it consistently.

---

## Exception Message Localization

DO externalize user-facing error messages to `messages.properties` for localization support:

```properties
# src/main/resources/messages.properties
error.user.notFound=User not found with id: {0}
error.user.emailConflict=A user with email ''{0}'' already exists
error.product.outOfStock=Product ''{0}'' is out of stock
```

DO inject `MessageSource` in exception construction where locale-sensitive messages are needed:

```java
@Service
@RequiredArgsConstructor
public class UserServiceImpl implements UserService {

    private final MessageSource messageSource;

    public UserResponse findById(UUID id) {
        return userRepository.findById(id)
            .map(userMapper::toResponse)
            .orElseThrow(() -> new ResourceNotFoundException(
                messageSource.getMessage("error.user.notFound",
                    new Object[]{id}, LocaleContextHolder.getLocale())
            ));
    }
}
```

DO NOT hardcode user-facing strings in service logic if the application supports multiple languages.

---

## Enable No-Handler-Found Exception

DO configure Spring Boot to throw `NoHandlerFoundException` for unknown paths (disabled by default):

```yaml
spring:
  mvc:
    throw-exception-if-no-handler-found: true
  web:
    resources:
      add-mappings: false
```

---

## Summary Checklist

- [ ] Exception hierarchy: `AppException` → typed subclasses
- [ ] No `RuntimeException` thrown directly from service or controller
- [ ] `ErrorResponse` with `timestamp`, `status`, `error`, `message`, `path`, `details`
- [ ] Single `@RestControllerAdvice` global handler
- [ ] `MethodArgumentNotValidException` handler with field-level details
- [ ] `ConstraintViolationException` handler
- [ ] `HttpMessageNotReadableException` handler (malformed JSON)
- [ ] `NoHandlerFoundException` handler (404 on unknown paths)
- [ ] `HttpRequestMethodNotSupportedException` handler (405)
- [ ] `MaxUploadSizeExceededException` handler (413)
- [ ] `DataIntegrityViolationException` handler (409, no DB details exposed)
- [ ] `AccessDeniedException` handler (403)
- [ ] `AuthenticationException` handler (401)
- [ ] Generic `Exception` fallback handler (500, no stack trace in response)
- [ ] 4xx logged at WARN, 5xx logged at ERROR
- [ ] `server.error.include-stacktrace: never` in all production profiles
- [ ] No stack traces or internal package names in response bodies
