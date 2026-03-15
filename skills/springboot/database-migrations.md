# Spring Boot Database Migrations — AI Agent Context

This file defines the authoritative patterns for managing database migrations in Spring Boot applications.
Agents MUST follow these patterns when generating or modifying database schema change code.

---

## Core Principles

- Use Flyway for all schema and data migrations. Flyway is preferred over Liquibase for its simplicity.
- NEVER use `spring.jpa.hibernate.ddl-auto=create`, `create-drop`, or `update` in production.
- NEVER modify an existing migration file after it has been applied to any environment.
- Every schema change, index addition, and reference data change goes through a migration file.
- Migrations must be idempotent where possible (use `IF NOT EXISTS`, `IF EXISTS`).

---

## Dependency Setup

```xml
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-core</artifactId>
</dependency>
<!-- Required for PostgreSQL 10+ -->
<dependency>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-database-postgresql</artifactId>
</dependency>
```

---

## Migration File Naming and Location

### Naming Convention

```
V{version}__{description}.sql
```

- `V` — versioned migration prefix (uppercase)
- `{version}` — numeric, uses dots or underscores: `1`, `1.1`, `2`, `10`
- `__` — double underscore separates version from description
- `{description}` — words separated by single underscores

### Examples

```
V1__create_users_table.sql
V2__create_orders_table.sql
V3__add_status_column_to_orders.sql
V4__create_products_table.sql
V5__add_index_on_orders_user_id.sql
V6__seed_roles.sql
V10__add_soft_delete_to_users.sql
```

### Location

```
src/main/resources/db/migration/
```

All Flyway migration scripts go in this directory by default.
Sub-directories are allowed for organization in large applications:

```
src/main/resources/db/migration/
    V1__create_users_table.sql
    V2__create_orders_table.sql
    seed/
        V100__seed_roles.sql
        V101__seed_countries.sql
```

Configure custom locations if needed:
```yaml
spring:
  flyway:
    locations: classpath:db/migration,classpath:db/seed
```

DO:
- Name files descriptively — the name is permanent documentation of what the migration does.
- Use sequential versions; never reuse a version number.
- Keep version numbers dense at the start; leave gaps only for planned groupings (e.g., 100+ for seed data).

DON'T:
- NEVER reorder, rename, or delete migration files once applied.
- NEVER use timestamps in version numbers (leads to merge conflicts in teams).

---

## Flyway Application Configuration

```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: true   # required for databases with existing schema
    baseline-version: 0
    validate-on-migrate: true   # always validate checksum before migrating
    out-of-order: false         # never allow out-of-order migrations in prod
    placeholders:
      schema: public
  jpa:
    hibernate:
      ddl-auto: validate   # validate schema matches entities; NEVER use update/create in prod
    show-sql: false
```

### Environment-Specific Settings

```yaml
# application-dev.yaml
spring:
  flyway:
    out-of-order: true    # allow dev flexibility when working across feature branches
  jpa:
    hibernate:
      ddl-auto: validate
    show-sql: true

# application-prod.yaml
spring:
  flyway:
    out-of-order: false
    clean-disabled: true  # CRITICAL: prevent accidental flyway:clean in production
  jpa:
    hibernate:
      ddl-auto: validate
```

DO:
- Set `spring.flyway.clean-disabled=true` in production to prevent accidental `flyway:clean`.
- Set `baseline-on-migrate=true` when running Flyway on an existing database for the first time.
- Always use `ddl-auto=validate` in production so Hibernate confirms schema matches entities.

DON'T:
- NEVER set `ddl-auto=create-drop` or `ddl-auto=update` in any non-local environment.
- NEVER set `out-of-order=true` in production.

---

## Migration File Best Practices

### Creating Tables

```sql
-- V1__create_users_table.sql
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email       VARCHAR(255) NOT NULL UNIQUE,
    password    VARCHAR(255) NOT NULL,
    first_name  VARCHAR(100) NOT NULL,
    last_name   VARCHAR(100) NOT NULL,
    role        VARCHAR(50)  NOT NULL DEFAULT 'USER',
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    created_by  VARCHAR(255),
    updated_by  VARCHAR(255)
);

CREATE INDEX idx_users_email ON users(email);
```

```sql
-- V2__create_orders_table.sql
CREATE TABLE orders (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID         NOT NULL REFERENCES users(id),
    status      VARCHAR(50)  NOT NULL DEFAULT 'PENDING',
    total       NUMERIC(19,2) NOT NULL,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status  ON orders(status);
```

### Adding Columns

```sql
-- V3__add_phone_to_users.sql
-- CORRECT: add nullable column first, then backfill, then add constraint if needed
ALTER TABLE users ADD COLUMN phone VARCHAR(20);

-- If you need NOT NULL: add with DEFAULT first, backfill, then optionally drop the default
-- V4__make_phone_not_null.sql (separate migration after backfill)
UPDATE users SET phone = 'UNKNOWN' WHERE phone IS NULL;
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
```

DO:
- Always add NOT NULL columns with a DEFAULT value so existing rows are not rejected.
- Split large operations into multiple migrations: add column (nullable) → backfill → add constraint.
- Add indexes concurrently in PostgreSQL for large tables to avoid locks:

```sql
-- V5__add_index_on_orders_created_at.sql
-- NOTE: CONCURRENTLY cannot run inside a transaction; use a separate migration
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_created_at ON orders(created_at);
```

For `CREATE INDEX CONCURRENTLY`, configure Flyway to not wrap in a transaction:
```java
// In a Java-based migration for CONCURRENTLY indexes
@Component
public class V5__add_index_on_orders_created_at extends BaseJavaMigration {
    @Override
    public void migrate(Context context) throws Exception {
        context.getConnection().setAutoCommit(true);
        try (var stmt = context.getConnection().createStatement()) {
            stmt.execute("""
                CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_created_at
                ON orders(created_at)
            """);
        } finally {
            context.getConnection().setAutoCommit(false);
        }
    }
}
```

### Soft Delete Column

```sql
-- V6__add_soft_delete_to_users.sql
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMP;
CREATE INDEX idx_users_deleted_at ON users(deleted_at) WHERE deleted_at IS NULL;
```

### Deprecating Columns (NEVER drop immediately)

```sql
-- V7__deprecate_legacy_username.sql
-- Step 1: rename to signal deprecation (do NOT drop yet)
COMMENT ON COLUMN users.username IS 'DEPRECATED: use email field instead. Will be removed in V20+.';

-- Step 2: after application code is fully migrated, drop in a later migration
-- V20__drop_deprecated_username.sql
ALTER TABLE users DROP COLUMN username;
```

DON'T:
- NEVER drop a column in the same migration that stops using it — deploy the app change first, then drop.
- NEVER rename columns in a single deployment — add the new column, migrate data, drop the old one.

---

## Seed Data Migrations

Separate structural migrations (table/column changes) from seed data (reference data).
Use a distinct version range for seed migrations (e.g., 100+).

```sql
-- V100__seed_roles.sql
INSERT INTO roles (id, name, description) VALUES
    (gen_random_uuid(), 'ADMIN',   'Administrator with full access'),
    (gen_random_uuid(), 'MANAGER', 'Manager with elevated access'),
    (gen_random_uuid(), 'USER',    'Standard user access')
ON CONFLICT (name) DO NOTHING;

-- V101__seed_countries.sql
INSERT INTO countries (code, name) VALUES
    ('US', 'United States'),
    ('GB', 'United Kingdom'),
    ('CA', 'Canada')
ON CONFLICT (code) DO NOTHING;
```

DO:
- Use `ON CONFLICT DO NOTHING` for idempotent inserts.
- Use a version range gap (e.g., 100+) to clearly separate seed from structural migrations.

DON'T:
- NEVER insert large volumes of data without batching — use scripts or Java migrations for bulk loads.

---

## Repeatable Migrations

Repeatable migrations run whenever their checksum changes. Use for views, functions, stored procedures.

```
src/main/resources/db/migration/
    R__create_order_summary_view.sql
    R__create_audit_trigger.sql
```

```sql
-- R__create_order_summary_view.sql
CREATE OR REPLACE VIEW order_summary AS
SELECT
    o.id,
    o.status,
    o.total,
    u.email AS user_email,
    o.created_at
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.deleted_at IS NULL;
```

DO:
- Use `R__` prefix for views, functions, and triggers that are replaced-in-place.
- Repeatable migrations run after all versioned migrations.
- Use `CREATE OR REPLACE` inside repeatable migrations.

DON'T:
- NEVER use repeatable migrations for structural changes (table/column creation/deletion).

---

## Rollback Strategy

Flyway Community Edition does not support automatic undo migrations. Use a manual approach:

```sql
-- V8__add_notification_preferences.sql  (forward)
ALTER TABLE users ADD COLUMN notifications_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- V8__undo_add_notification_preferences.sql  (stored separately, NOT in the migration path)
-- Run manually if rollback is needed BEFORE deploying V9+
ALTER TABLE users DROP COLUMN notifications_enabled;
```

Production rollback strategy:
1. Never apply the forward migration to production until it is fully tested.
2. Prepare an undo script for every migration and store it alongside the versioned file.
3. For complex rollbacks: deploy a new forward migration that reverses the change (`V9__revert_notification_preferences.sql`).

---

## Testing Migrations with Testcontainers

```java
@SpringBootTest
@Testcontainers
class FlywayMigrationTest {

    @Container
    static final PostgreSQLContainer<?> POSTGRES =
        new PostgreSQLContainer<>("postgres:16-alpine");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
    }

    @Autowired
    private Flyway flyway;

    @Autowired
    private DataSource dataSource;

    @Test
    void allMigrations_applyCleanly() {
        MigrationInfo[] migrations = flyway.info().all();
        assertThat(migrations).isNotEmpty();

        long failedCount = Arrays.stream(migrations)
            .filter(m -> m.getState().isFailed())
            .count();

        assertThat(failedCount).isZero();
    }

    @Test
    void schema_matchesEntityModel() throws Exception {
        // If ddl-auto=validate passes on startup, the schema is correct.
        // This test simply verifies the application context loads without error.
        try (Connection conn = dataSource.getConnection()) {
            assertThat(conn.isValid(1)).isTrue();
        }
    }
}
```

DO:
- Run migration tests against Testcontainers using the same database engine as production.
- Include a migration test in your CI pipeline to catch broken migrations early.

DON'T:
- NEVER test migrations against H2 if your production database is PostgreSQL.

---

## Multi-Module Migration Paths

For multi-module projects where each module owns its schema:

```yaml
spring:
  flyway:
    locations:
      - classpath:db/migration/core
      - classpath:db/migration/billing
      - classpath:db/migration/notifications
```

Each module contributes migration files to its own sub-directory with non-overlapping version ranges:

| Module         | Version Range |
|----------------|---------------|
| core           | V1 – V99      |
| billing        | V200 – V299   |
| notifications  | V300 – V399   |

---

## Dev vs Prod Migration Strategies

| Concern                     | Dev                              | Prod                              |
|-----------------------------|----------------------------------|-----------------------------------|
| `ddl-auto`                  | `validate`                       | `validate`                        |
| `out-of-order`              | `true` (feature branch flexibility) | `false`                        |
| `clean-disabled`            | `false` (allow reset)            | `true` (critical)                 |
| Migration location          | `classpath:db/migration`         | `classpath:db/migration`          |
| Flyway repair               | Allowed manually                 | Allowed, with change review       |
| Schema baseline             | Not needed for new DBs           | `baseline-on-migrate=true` for legacy |

---

## Summary Checklist

- [ ] Flyway dependency added (`flyway-core`, `flyway-database-postgresql`)
- [ ] Migration files in `src/main/resources/db/migration/`
- [ ] Naming convention: `V{N}__{description}.sql`
- [ ] `ddl-auto=validate` in all non-local environments
- [ ] `clean-disabled=true` in production config
- [ ] `baseline-on-migrate=true` for first-time Flyway on existing database
- [ ] No modification of applied migration files
- [ ] NOT NULL additions include a DEFAULT
- [ ] Column drops staged over multiple deployments
- [ ] Seed data in separate version range (100+) with `ON CONFLICT DO NOTHING`
- [ ] Repeatable migrations (`R__`) used for views and functions
- [ ] Migration tests run against Testcontainers in CI
- [ ] Undo scripts prepared for each migration
