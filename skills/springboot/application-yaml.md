# Spring Boot application.yaml Configuration Conventions

This document defines the mandatory rules and standard patterns for configuring Spring Boot applications via YAML. AI agents generating configuration files MUST follow every rule in this document.

---

## Critical Rules

- **NEVER hardcode passwords, secrets, API keys, or tokens in any YAML file**
- **ALWAYS use environment variable injection** with the pattern `${ENV_VAR_NAME:default_value}`
- **NEVER commit secrets to source control** — use `.env` files locally and secrets management (AWS Secrets Manager, Vault, etc.) in production
- **ALWAYS provide safe defaults** for non-sensitive values
- **ALWAYS define separate profiles** for dev, staging, and prod

---

## 1. Profile Overview

```
src/main/resources/
├── application.yaml          ← Base config, shared across all profiles
├── application-dev.yaml      ← Development overrides
├── application-staging.yaml  ← Staging overrides (optional)
└── application-prod.yaml     ← Production overrides
```

**DO** keep the base `application.yaml` minimal — only properties that are profile-agnostic.
**DO** override profile-specific values in the respective profile file.
**DON'T** put production secrets in any YAML file — use environment variables or secrets managers.

---

## 2. Base Configuration: `application.yaml`

```yaml
# =====================================================================
# BASE CONFIGURATION — applies to all profiles unless overridden
# =====================================================================

spring:
  application:
    name: user-management-service

  profiles:
    active: ${SPRING_PROFILES_ACTIVE:dev}   # Override via env var in production

  # ----- Jackson -------------------------------------------------------
  jackson:
    serialization:
      write-dates-as-timestamps: false
    deserialization:
      fail-on-unknown-properties: false
    default-property-inclusion: non_null
    time-zone: UTC

  # ----- Async / ThreadPool -------------------------------------------
  task:
    execution:
      pool:
        core-size: 5
        max-size: 20
        queue-capacity: 100
        keep-alive: 60s
      thread-name-prefix: async-

# ----- Server ---------------------------------------------------------
server:
  port: ${SERVER_PORT:8080}
  servlet:
    context-path: /
  compression:
    enabled: true
    mime-types: application/json,application/xml,text/html,text/plain
    min-response-size: 1024
  error:
    include-message: never          # Never expose exception messages in error responses
    include-stacktrace: never       # Never expose stack traces
    include-binding-errors: never

# ----- Application-specific properties --------------------------------
app:
  version: ${APP_VERSION:1.0.0}
  name: User Management Service

  jwt:
    secret: ${JWT_SECRET}           # REQUIRED — no default, must be set via env var
    expiration-ms: ${JWT_EXPIRY_MS:86400000}     # 24 hours default
    refresh-expiration-ms: ${JWT_REFRESH_EXPIRY_MS:604800000}  # 7 days

  cors:
    allowed-origins: ${CORS_ALLOWED_ORIGINS:http://localhost:3000,http://localhost:4200}
    allowed-methods: GET,POST,PUT,PATCH,DELETE,OPTIONS
    allowed-headers: "*"
    allow-credentials: true
    max-age: 3600

# ----- Actuator -------------------------------------------------------
management:
  endpoints:
    web:
      base-path: /actuator
      exposure:
        include: health,info,metrics
  endpoint:
    health:
      show-details: when-authorized
  info:
    env:
      enabled: true

info:
  app:
    name: ${spring.application.name}
    version: ${app.version}
    description: "User management REST API"

# ----- Logging --------------------------------------------------------
logging:
  level:
    root: INFO
    com.company.appname: INFO
  pattern:
    console: "%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n"
    file: "%d{yyyy-MM-dd HH:mm:ss} [%thread] %-5level %logger{36} - %msg%n"

# ----- Springdoc / Swagger --------------------------------------------
springdoc:
  api-docs:
    path: /api-docs
  swagger-ui:
    path: /swagger-ui.html
    operations-sorter: method
    tags-sorter: alpha
    display-request-duration: true
  packages-to-scan: com.company.appname.controller
  show-actuator: false

# ----- Multipart uploads ----------------------------------------------
spring:
  servlet:
    multipart:
      enabled: true
      max-file-size: ${MAX_FILE_SIZE:10MB}
      max-request-size: ${MAX_REQUEST_SIZE:20MB}
```

---

## 3. Development Profile: `application-dev.yaml`

```yaml
# =====================================================================
# DEVELOPMENT CONFIGURATION
# Activated by: SPRING_PROFILES_ACTIVE=dev
# =====================================================================

spring:
  # ----- DataSource — PostgreSQL (local dev) -------------------------
  datasource:
    url: jdbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${DB_NAME:appname_dev}
    username: ${DB_USERNAME:postgres}
    password: ${DB_PASSWORD:postgres}   # Local dev default — never do this in prod
    driver-class-name: org.postgresql.Driver
    hikari:
      pool-name: HikariPool-Dev
      minimum-idle: 2
      maximum-pool-size: 10
      idle-timeout: 30000
      connection-timeout: 20000
      max-lifetime: 1800000
      connection-test-query: SELECT 1

  # ----- JPA / Hibernate ---------------------------------------------
  jpa:
    hibernate:
      ddl-auto: validate            # Use 'validate' with Flyway; never 'create-drop' on shared dbs
    show-sql: true
    properties:
      hibernate:
        format_sql: true
        dialect: org.hibernate.dialect.PostgreSQLDialect
        jdbc:
          batch_size: 20
        order_inserts: true
        order_updates: true
    open-in-view: false             # Always false — prevents lazy-loading in views

  # ----- Flyway (database migrations) --------------------------------
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: true
    validate-on-migrate: true

  # ----- Mail (dev — use MailHog or Mailtrap) -----------------------
  mail:
    host: ${MAIL_HOST:localhost}
    port: ${MAIL_PORT:1025}
    username: ${MAIL_USERNAME:}
    password: ${MAIL_PASSWORD:}
    properties:
      mail:
        smtp:
          auth: false
          starttls:
            enable: false

  # ----- Redis (dev — local) ----------------------------------------
  data:
    redis:
      host: ${REDIS_HOST:localhost}
      port: ${REDIS_PORT:6379}
      password: ${REDIS_PASSWORD:}
      timeout: 2000ms
      lettuce:
        pool:
          min-idle: 1
          max-idle: 5
          max-active: 10

# ----- Logging (verbose in dev) -------------------------------------
logging:
  level:
    root: INFO
    com.company.appname: DEBUG
    org.springframework.web: DEBUG
    org.springframework.security: DEBUG
    org.hibernate.SQL: DEBUG
    org.hibernate.type.descriptor.sql: TRACE

# ----- Actuator (expose more in dev) --------------------------------
management:
  endpoints:
    web:
      exposure:
        include: "*"    # Expose all actuator endpoints in dev
  endpoint:
    health:
      show-details: always

# ----- Swagger enabled in dev ---------------------------------------
springdoc:
  swagger-ui:
    enabled: true
  api-docs:
    enabled: true
```

---

## 4. Production Profile: `application-prod.yaml`

```yaml
# =====================================================================
# PRODUCTION CONFIGURATION
# Activated by: SPRING_PROFILES_ACTIVE=prod
# ALL sensitive values MUST come from environment variables or
# a secrets manager (AWS Secrets Manager, HashiCorp Vault, etc.)
# =====================================================================

spring:
  # ----- DataSource — PostgreSQL (prod) ------------------------------
  datasource:
    url: jdbc:postgresql://${DB_HOST}:${DB_PORT:5432}/${DB_NAME}
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}          # REQUIRED — no default
    driver-class-name: org.postgresql.Driver
    hikari:
      pool-name: HikariPool-Prod
      minimum-idle: 5
      maximum-pool-size: ${DB_POOL_MAX_SIZE:20}
      idle-timeout: 600000            # 10 minutes
      connection-timeout: 30000       # 30 seconds
      max-lifetime: 1800000           # 30 minutes
      leak-detection-threshold: 60000 # 60 seconds
      connection-test-query: SELECT 1

  # ----- JPA / Hibernate ---------------------------------------------
  jpa:
    hibernate:
      ddl-auto: validate              # NEVER use 'create', 'create-drop', or 'update' in prod
    show-sql: false                   # NEVER log SQL in production
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect
        jdbc:
          batch_size: 50
        order_inserts: true
        order_updates: true
        generate_statistics: false
    open-in-view: false

  # ----- Flyway -------------------------------------------------------
  flyway:
    enabled: true
    locations: classpath:db/migration
    validate-on-migrate: true
    out-of-order: false

  # ----- Mail (prod — real SMTP) ------------------------------------
  mail:
    host: ${MAIL_HOST}
    port: ${MAIL_PORT:587}
    username: ${MAIL_USERNAME}
    password: ${MAIL_PASSWORD}        # REQUIRED — no default
    properties:
      mail:
        smtp:
          auth: true
          starttls:
            enable: true
            required: true

  # ----- Redis (prod) -----------------------------------------------
  data:
    redis:
      host: ${REDIS_HOST}
      port: ${REDIS_PORT:6379}
      password: ${REDIS_PASSWORD}     # REQUIRED — no default
      ssl:
        enabled: ${REDIS_SSL_ENABLED:true}
      timeout: 2000ms
      lettuce:
        pool:
          min-idle: 2
          max-idle: 10
          max-active: ${REDIS_POOL_MAX_ACTIVE:20}

# ----- Server (prod hardening) --------------------------------------
server:
  port: ${SERVER_PORT:8080}
  servlet:
    context-path: /
  compression:
    enabled: true
  error:
    include-message: never
    include-stacktrace: never
    include-binding-errors: never

# ----- Logging (minimal in prod) -----------------------------------
logging:
  level:
    root: WARN
    com.company.appname: INFO
  file:
    name: ${LOG_FILE_PATH:/var/log/appname/application.log}
  logback:
    rollingpolicy:
      max-file-size: 100MB
      max-history: 30

# ----- Actuator (restricted in prod) --------------------------------
management:
  endpoints:
    web:
      exposure:
        include: health,info,metrics,prometheus
  endpoint:
    health:
      show-details: when-authorized   # Only show health details to authorized users
  metrics:
    export:
      prometheus:
        enabled: true

# ----- Swagger DISABLED in production --------------------------------
springdoc:
  swagger-ui:
    enabled: false
  api-docs:
    enabled: false
```

---

## 5. MySQL Datasource Example (Alternative)

```yaml
spring:
  datasource:
    url: jdbc:mysql://${DB_HOST:localhost}:${DB_PORT:3306}/${DB_NAME:appname}?useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true
    username: ${DB_USERNAME:root}
    password: ${DB_PASSWORD:}
    driver-class-name: com.mysql.cj.jdbc.Driver
    hikari:
      pool-name: HikariPool-MySQL
      minimum-idle: 2
      maximum-pool-size: 10

  jpa:
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        dialect: org.hibernate.dialect.MySQLDialect
```

---

## 6. HikariCP Connection Pool Reference

```yaml
spring:
  datasource:
    hikari:
      pool-name: HikariPool                 # Visible in JMX / logs
      minimum-idle: 5                       # Min idle connections
      maximum-pool-size: 20                 # Max total connections
      idle-timeout: 600000                  # Remove idle connections after 10 min (ms)
      connection-timeout: 30000             # Wait up to 30s to get a connection (ms)
      max-lifetime: 1800000                 # Max connection lifetime: 30 min (ms)
      leak-detection-threshold: 60000       # Warn if connection held > 60s (ms)
      connection-test-query: SELECT 1       # Validation query (PostgreSQL / MySQL)
      auto-commit: true
```

---

## 7. JWT Configuration Pattern

```yaml
app:
  jwt:
    secret: ${JWT_SECRET}                              # 256-bit+ secret, never hardcoded
    expiration-ms: ${JWT_EXPIRY_MS:86400000}           # 24 hours
    refresh-expiration-ms: ${JWT_REFRESH_EXPIRY_MS:604800000}  # 7 days
    issuer: ${JWT_ISSUER:com.company.appname}
```

Read in a `@ConfigurationProperties` class:

```java
@ConfigurationProperties(prefix = "app.jwt")
@Validated
@Getter
@Setter
public class JwtProperties {

    @NotBlank
    private String secret;

    @Positive
    private long expirationMs;

    @Positive
    private long refreshExpirationMs;

    private String issuer;
}
```

Enable in the main application class:

```java
@SpringBootApplication
@EnableConfigurationProperties(JwtProperties.class)
public class AppNameApplication { ... }
```

---

## 8. CORS Configuration in YAML

```yaml
app:
  cors:
    allowed-origins: ${CORS_ALLOWED_ORIGINS:http://localhost:3000}
    allowed-methods: GET,POST,PUT,PATCH,DELETE,OPTIONS
    allowed-headers: "*"
    exposed-headers: Authorization,Content-Disposition
    allow-credentials: true
    max-age: 3600
```

```java
@Configuration
@RequiredArgsConstructor
public class WebMvcConfig implements WebMvcConfigurer {

    @Value("${app.cors.allowed-origins}")
    private String allowedOrigins;

    @Value("${app.cors.allow-credentials:true}")
    private boolean allowCredentials;

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
                .allowedOriginPatterns(allowedOrigins.split(","))
                .allowedMethods("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
                .allowedHeaders("*")
                .allowCredentials(allowCredentials)
                .maxAge(3600);
    }
}
```

---

## 9. Mail Configuration

```yaml
spring:
  mail:
    host: ${MAIL_HOST:smtp.gmail.com}
    port: ${MAIL_PORT:587}
    username: ${MAIL_USERNAME}
    password: ${MAIL_PASSWORD}          # App password — never hardcode
    properties:
      mail:
        smtp:
          auth: true
          starttls:
            enable: true
            required: true
        debug: false                    # Set to true only for local debugging

app:
  mail:
    from: ${MAIL_FROM:noreply@company.com}
    from-name: ${MAIL_FROM_NAME:Company App}
```

---

## 10. Redis Configuration

```yaml
spring:
  data:
    redis:
      host: ${REDIS_HOST:localhost}
      port: ${REDIS_PORT:6379}
      password: ${REDIS_PASSWORD:}
      timeout: 2000ms
      database: 0
      lettuce:
        pool:
          min-idle: 1
          max-idle: 8
          max-active: 16
          max-wait: -1ms

  cache:
    type: redis
    redis:
      time-to-live: ${CACHE_TTL_MS:3600000}   # 1 hour default
      cache-null-values: false
      key-prefix: "appname:"
      use-key-prefix: true
```

---

## 11. Async Thread Pool Configuration

```yaml
spring:
  task:
    execution:
      pool:
        core-size: ${ASYNC_CORE_POOL_SIZE:5}
        max-size: ${ASYNC_MAX_POOL_SIZE:20}
        queue-capacity: ${ASYNC_QUEUE_CAPACITY:100}
        keep-alive: 60s
      thread-name-prefix: async-task-
    scheduling:
      pool:
        size: ${SCHEDULER_POOL_SIZE:3}
      thread-name-prefix: scheduled-task-
```

---

## 12. Flyway Migration Configuration

```yaml
spring:
  flyway:
    enabled: true
    locations:
      - classpath:db/migration
    baseline-on-migrate: ${FLYWAY_BASELINE:false}
    validate-on-migrate: true
    out-of-order: false
    table: flyway_schema_history
    schemas: public
```

Migration file naming: `V{version}__{description}.sql`

```
src/main/resources/
└── db/
    └── migration/
        ├── V1__create_users_table.sql
        ├── V2__create_orders_table.sql
        └── V3__add_index_on_users_email.sql
```

---

## 13. Environment Variable Injection Patterns

```yaml
# Pattern 1: Required with no default (will fail fast at startup if not set)
database:
  password: ${DB_PASSWORD}

# Pattern 2: Optional with a sensible default
server:
  port: ${SERVER_PORT:8080}

# Pattern 3: Boolean flag
feature:
  email-verification: ${FEATURE_EMAIL_VERIFICATION:false}

# Pattern 4: Comma-separated list
app:
  cors:
    allowed-origins: ${CORS_ORIGINS:http://localhost:3000,http://localhost:4200}

# Pattern 5: Numeric with default
hikari:
  maximum-pool-size: ${DB_POOL_MAX_SIZE:20}
```

**DO** fail fast for required secrets — use `${SECRET_NAME}` with no default so the app refuses to start if the env var is missing.
**DON'T** provide defaults for passwords, JWT secrets, or any sensitive credential.

---

## 14. Logging Configuration

```yaml
logging:
  level:
    root: INFO
    com.company.appname: DEBUG          # Your package — verbose in dev
    org.springframework.web: DEBUG      # HTTP request/response details
    org.springframework.security: DEBUG # Auth decisions
    org.hibernate.SQL: DEBUG            # SQL statements
    org.hibernate.type.descriptor.sql: TRACE  # SQL bind parameters
  pattern:
    console: "%clr(%d{HH:mm:ss.SSS}){faint} %clr(%-5level) %clr(%logger{36}){cyan} - %msg%n"
  file:
    name: ${LOG_FILE:/var/log/appname/app.log}
  logback:
    rollingpolicy:
      file-name-pattern: "${LOG_FILE}.%d{yyyy-MM-dd}.%i.gz"
      max-file-size: 50MB
      max-history: 30
      total-size-cap: 3GB
```

In production, set `org.hibernate.SQL` and `org.springframework.web` to `WARN` or `ERROR` — never leave SQL logging enabled in production.

---

## 15. Complete `gradle.properties` Reference for Environment Variable Defaults

When running locally, create a `.env` file (never commit this):

```bash
# .env (gitignored)
SPRING_PROFILES_ACTIVE=dev
DB_HOST=localhost
DB_PORT=5432
DB_NAME=appname_dev
DB_USERNAME=postgres
DB_PASSWORD=local_dev_password
JWT_SECRET=this-is-a-very-long-development-secret-key-256-bits-minimum
REDIS_HOST=localhost
MAIL_HOST=localhost
MAIL_PORT=1025
```

Load it via a tool like `dotenv-gradle` plugin or manually export in your shell. Never rely on plain `.env` loading in production — use a proper secrets manager.
