# Spring Boot Gradle Build Conventions

This document defines the mandatory Gradle project structure, file organization, and dependency conventions for all Spring Boot applications. AI agents generating build files MUST follow every rule in this document.

---

## 1. Project Structure

### Single Module (most common)

```
project-root/
├── build.gradle                  ← Main build file
├── settings.gradle               ← Project name
├── gradle.properties             ← JVM args, project metadata
├── gradlew                       ← Gradle wrapper script (Unix)
├── gradlew.bat                   ← Gradle wrapper script (Windows)
├── gradle/
│   ├── wrapper/
│   │   ├── gradle-wrapper.jar
│   │   └── gradle-wrapper.properties
│   ├── dependencies.gradle       ← All dependency declarations
│   └── plugins.gradle            ← All plugin declarations
└── src/
    ├── main/
    │   ├── java/
    │   └── resources/
    └── test/
        ├── java/
        └── resources/
```

### Multi-Module (if needed)

```
project-root/
├── build.gradle                  ← Root build (shared config)
├── settings.gradle               ← Includes all submodules
├── gradle.properties
├── gradle/
│   ├── wrapper/...
│   ├── dependencies.gradle
│   └── plugins.gradle
├── api/                          ← Submodule: REST API
│   ├── build.gradle
│   └── src/
├── service/                      ← Submodule: Business logic
│   ├── build.gradle
│   └── src/
└── common/                       ← Submodule: Shared code
    ├── build.gradle
    └── src/
```

---

## 2. `settings.gradle`

```groovy
rootProject.name = 'user-management-service'

// For multi-module projects, include submodules:
// include 'api', 'service', 'common'
```

---

## 3. `gradle.properties`

```properties
# Project metadata
version=1.0.0
group=com.company.appname
description=User Management REST API Service

# Gradle JVM arguments — increase heap for large projects
org.gradle.jvmargs=-Xmx2048m -Xms512m -XX:MaxMetaspaceSize=512m -XX:+HeapDumpOnOutOfMemoryError -Dfile.encoding=UTF-8

# Enable Gradle build cache
org.gradle.caching=true

# Enable parallel execution
org.gradle.parallel=true

# Enable configuration cache (Gradle 7.4+)
org.gradle.configuration-cache=true

# Kotlin DSL daemon — uncomment if using .kts build files
# kotlin.daemon.jvm.options=-Xmx2048m

# Dependency versions (used in dependencies.gradle via ext block)
springBootVersion=3.3.5
springDepManagementVersion=1.1.6
lombokVersion=1.18.34
mapstructVersion=1.6.2
springdocVersion=2.5.0
flywayVersion=10.17.3
postgresqlVersion=42.7.4
testcontainersVersion=1.20.2
```

---

## 4. `gradle/plugins.gradle`

```groovy
// gradle/plugins.gradle
// Applied in the main build.gradle via: apply from: 'gradle/plugins.gradle'

apply plugin: 'java'
apply plugin: 'org.springframework.boot'
apply plugin: 'io.spring.dependency-management'

// Lombok annotation processing
configurations {
    compileOnly {
        extendsFrom annotationProcessor
    }
}
```

The plugin IDs are declared in the `build.gradle` `plugins {}` block (see below). This file contains supplementary `apply plugin` calls and configuration blocks.

---

## 5. `gradle/dependencies.gradle`

```groovy
// gradle/dependencies.gradle
// Applied in the main build.gradle via: apply from: 'gradle/dependencies.gradle'

dependencies {

    // ============================================================
    // SPRING BOOT CORE
    // ============================================================
    implementation 'org.springframework.boot:spring-boot-starter-web'
    implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
    implementation 'org.springframework.boot:spring-boot-starter-security'
    implementation 'org.springframework.boot:spring-boot-starter-validation'
    implementation 'org.springframework.boot:spring-boot-starter-actuator'
    implementation 'org.springframework.boot:spring-boot-starter-mail'
    implementation 'org.springframework.boot:spring-boot-starter-data-redis'
    implementation 'org.springframework.boot:spring-boot-starter-cache'
    implementation 'org.springframework.boot:spring-boot-starter-aop'

    // ============================================================
    // DEVELOPER TOOLS (dev only — excluded from production jar)
    // ============================================================
    developmentOnly 'org.springframework.boot:spring-boot-devtools'

    // ============================================================
    // DATABASE
    // ============================================================
    runtimeOnly "org.postgresql:postgresql:${postgresqlVersion}"
    implementation "org.flywaydb:flyway-core:${flywayVersion}"
    implementation "org.flywaydb:flyway-database-postgresql:${flywayVersion}"

    // ============================================================
    // LOMBOK
    // ============================================================
    compileOnly "org.projectlombok:lombok:${lombokVersion}"
    annotationProcessor "org.projectlombok:lombok:${lombokVersion}"
    testCompileOnly "org.projectlombok:lombok:${lombokVersion}"
    testAnnotationProcessor "org.projectlombok:lombok:${lombokVersion}"

    // ============================================================
    // MAPSTRUCT
    // ============================================================
    implementation "org.mapstruct:mapstruct:${mapstructVersion}"
    annotationProcessor "org.mapstruct:mapstruct-processor:${mapstructVersion}"
    // Required when using Lombok + MapStruct together:
    annotationProcessor "org.projectlombok:lombok-mapstruct-binding:0.2.0"

    // ============================================================
    // JWT
    // ============================================================
    implementation 'io.jsonwebtoken:jjwt-api:0.12.6'
    runtimeOnly 'io.jsonwebtoken:jjwt-impl:0.12.6'
    runtimeOnly 'io.jsonwebtoken:jjwt-jackson:0.12.6'

    // ============================================================
    // OPENAPI / SWAGGER
    // ============================================================
    implementation "org.springdoc:springdoc-openapi-starter-webmvc-ui:${springdocVersion}"

    // ============================================================
    // CONFIGURATION PROCESSOR (for @ConfigurationProperties IDE support)
    // ============================================================
    annotationProcessor 'org.springframework.boot:spring-boot-configuration-processor'

    // ============================================================
    // TEST DEPENDENCIES
    // ============================================================
    testImplementation 'org.springframework.boot:spring-boot-starter-test'
    testImplementation 'org.springframework.security:spring-security-test'

    // H2 in-memory database (for @DataJpaTest slice tests)
    testRuntimeOnly 'com.h2database:h2'

    // Testcontainers (for integration tests with real PostgreSQL)
    testImplementation platform("org.testcontainers:testcontainers-bom:${testcontainersVersion}")
    testImplementation 'org.testcontainers:junit-jupiter'
    testImplementation 'org.testcontainers:postgresql'

    // WireMock (for mocking external HTTP dependencies in tests)
    testImplementation 'org.wiremock:wiremock-standalone:3.9.1'
}
```

---

## 6. Main `build.gradle` (Single Module)

```groovy
// build.gradle
// This is the main build file. It declares plugins and applies
// the separate dependency and plugin configuration files.

plugins {
    id 'java'
    id 'org.springframework.boot' version "${springBootVersion}"
    id 'io.spring.dependency-management' version "${springDepManagementVersion}"
}

// Load versions from gradle.properties (they are auto-available as project properties)
// e.g., springBootVersion, lombokVersion, etc.

group = project.group
version = project.version
description = project.description

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)   // Use Java 21 (LTS)
    }
}

// Apply shared configuration files
apply from: 'gradle/plugins.gradle'
apply from: 'gradle/dependencies.gradle'

// Annotation processor argument: ensure MapStruct uses Spring component model
compileJava {
    options.annotationProcessorGeneratedSourcesDirectory =
        file("${buildDir}/generated/sources/annotationProcessor/java/main")
    options.compilerArgs += [
        '-Amapstruct.defaultComponentModel=spring',
        '-Amapstruct.suppressGeneratorTimestamp=true'
    ]
}

// ============================================================
// TEST CONFIGURATION
// ============================================================
tasks.named('test') {
    useJUnitPlatform()
    jvmArgs '-XX:+EnableDynamicAgentLoading'   // Required for Mockito on JDK 21+
    testLogging {
        events 'passed', 'skipped', 'failed'
        showStandardStreams = false
        exceptionFormat = 'full'
    }
    systemProperty 'spring.profiles.active', 'test'
}

// ============================================================
// JAR CONFIGURATION
// ============================================================
jar {
    enabled = false   // Disable the plain jar — only the Spring Boot fat jar is needed
}

bootJar {
    archiveFileName = "${rootProject.name}-${version}.jar"
}

// ============================================================
// SPRING BOOT BUILD INFO (adds build info to actuator /info)
// ============================================================
springBoot {
    buildInfo()
}
```

---

## 7. Root `build.gradle` (Multi-Module)

```groovy
// Root build.gradle for multi-module projects

plugins {
    id 'java'
    id 'org.springframework.boot' version "${springBootVersion}" apply false
    id 'io.spring.dependency-management' version "${springDepManagementVersion}" apply false
}

// Configuration applied to ALL subprojects
subprojects {
    apply plugin: 'java'
    apply plugin: 'io.spring.dependency-management'

    group = rootProject.group
    version = rootProject.version

    java {
        toolchain {
            languageVersion = JavaLanguageVersion.of(21)
        }
    }

    dependencyManagement {
        imports {
            mavenBom "org.springframework.boot:spring-boot-dependencies:${springBootVersion}"
        }
    }

    repositories {
        mavenCentral()
    }

    tasks.named('test') {
        useJUnitPlatform()
    }
}

// The submodule that produces the executable JAR applies Spring Boot plugin
// This is done in the submodule's own build.gradle:
// apply plugin: 'org.springframework.boot'
```

### Submodule `build.gradle` (e.g., `api/build.gradle`)

```groovy
// api/build.gradle
apply plugin: 'org.springframework.boot'
apply from: rootProject.file('gradle/dependencies.gradle')
apply from: rootProject.file('gradle/plugins.gradle')

dependencies {
    implementation project(':service')
    implementation project(':common')
}

bootJar {
    archiveFileName = "api-${version}.jar"
}
```

---

## 8. Dependency Version Management via BOM

Spring Boot's dependency management plugin already imports the Spring BOM, so most Spring dependencies do NOT need explicit versions:

```groovy
// DO — version managed by Spring BOM
implementation 'org.springframework.boot:spring-boot-starter-web'
testImplementation 'org.springframework.boot:spring-boot-starter-test'

// DO — specify version for non-Spring dependencies
implementation "org.mapstruct:mapstruct:${mapstructVersion}"
implementation "org.springdoc:springdoc-openapi-starter-webmvc-ui:${springdocVersion}"

// DON'T — don't specify a version for Spring-managed dependencies
// implementation 'org.springframework.boot:spring-boot-starter-web:3.3.5'  // redundant
```

---

## 9. Gradle Wrapper Configuration

```properties
# gradle/wrapper/gradle-wrapper.properties
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.10-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
```

Always use the **latest stable Gradle 8.x** release. Regenerate with:

```bash
./gradlew wrapper --gradle-version=8.10 --distribution-type=bin
```

**DO** commit the `gradlew`, `gradlew.bat`, and `gradle/wrapper/` directory to source control.
**DON'T** commit the `.gradle/` directory — add it to `.gitignore`.

---

## 10. `.gitignore` (Gradle-specific entries)

```gitignore
# Gradle
.gradle/
build/
out/

# Do NOT ignore:
# gradle/wrapper/gradle-wrapper.jar
# gradlew
# gradlew.bat
```

---

## 11. Complete Annotated Example — Single Module Project

Here is a complete, production-ready single module Spring Boot project build configuration.

### `settings.gradle`

```groovy
rootProject.name = 'user-management-service'
```

### `gradle.properties`

```properties
version=1.0.0
group=com.company.usermanagement
description=User Management REST API

org.gradle.jvmargs=-Xmx2048m -Xms512m -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8
org.gradle.caching=true
org.gradle.parallel=true
org.gradle.configuration-cache=true

springBootVersion=3.3.5
springDepManagementVersion=1.1.6
lombokVersion=1.18.34
mapstructVersion=1.6.2
springdocVersion=2.5.0
flywayVersion=10.17.3
postgresqlVersion=42.7.4
testcontainersVersion=1.20.2
```

### `gradle/plugins.gradle`

```groovy
apply plugin: 'java'
apply plugin: 'org.springframework.boot'
apply plugin: 'io.spring.dependency-management'

repositories {
    mavenCentral()
}

configurations {
    compileOnly {
        extendsFrom annotationProcessor
    }
}
```

### `gradle/dependencies.gradle`

```groovy
dependencies {

    // Spring Boot Starters
    implementation 'org.springframework.boot:spring-boot-starter-web'
    implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
    implementation 'org.springframework.boot:spring-boot-starter-security'
    implementation 'org.springframework.boot:spring-boot-starter-validation'
    implementation 'org.springframework.boot:spring-boot-starter-actuator'
    implementation 'org.springframework.boot:spring-boot-starter-mail'
    implementation 'org.springframework.boot:spring-boot-starter-data-redis'
    implementation 'org.springframework.boot:spring-boot-starter-cache'

    // DevTools
    developmentOnly 'org.springframework.boot:spring-boot-devtools'

    // Database
    runtimeOnly "org.postgresql:postgresql:${postgresqlVersion}"
    implementation "org.flywaydb:flyway-core:${flywayVersion}"
    implementation "org.flywaydb:flyway-database-postgresql:${flywayVersion}"

    // Lombok
    compileOnly "org.projectlombok:lombok:${lombokVersion}"
    annotationProcessor "org.projectlombok:lombok:${lombokVersion}"
    testCompileOnly "org.projectlombok:lombok:${lombokVersion}"
    testAnnotationProcessor "org.projectlombok:lombok:${lombokVersion}"

    // MapStruct
    implementation "org.mapstruct:mapstruct:${mapstructVersion}"
    annotationProcessor "org.mapstruct:mapstruct-processor:${mapstructVersion}"
    annotationProcessor "org.projectlombok:lombok-mapstruct-binding:0.2.0"

    // JWT
    implementation 'io.jsonwebtoken:jjwt-api:0.12.6'
    runtimeOnly 'io.jsonwebtoken:jjwt-impl:0.12.6'
    runtimeOnly 'io.jsonwebtoken:jjwt-jackson:0.12.6'

    // OpenAPI
    implementation "org.springdoc:springdoc-openapi-starter-webmvc-ui:${springdocVersion}"

    // Config Processor
    annotationProcessor 'org.springframework.boot:spring-boot-configuration-processor'

    // Test
    testImplementation 'org.springframework.boot:spring-boot-starter-test'
    testImplementation 'org.springframework.security:spring-security-test'
    testRuntimeOnly 'com.h2database:h2'
    testImplementation platform("org.testcontainers:testcontainers-bom:${testcontainersVersion}")
    testImplementation 'org.testcontainers:junit-jupiter'
    testImplementation 'org.testcontainers:postgresql'
}
```

### `build.gradle`

```groovy
plugins {
    id 'java'
    id 'org.springframework.boot' version "${springBootVersion}"
    id 'io.spring.dependency-management' version "${springDepManagementVersion}"
}

group = project.group
version = project.version
description = project.description

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
}

apply from: 'gradle/plugins.gradle'
apply from: 'gradle/dependencies.gradle'

compileJava {
    options.annotationProcessorGeneratedSourcesDirectory =
        file("${buildDir}/generated/sources/annotationProcessor/java/main")
    options.compilerArgs += [
        '-Amapstruct.defaultComponentModel=spring',
        '-Amapstruct.suppressGeneratorTimestamp=true'
    ]
}

tasks.named('test') {
    useJUnitPlatform()
    jvmArgs '-XX:+EnableDynamicAgentLoading'
    testLogging {
        events 'passed', 'skipped', 'failed'
        exceptionFormat = 'full'
    }
    systemProperty 'spring.profiles.active', 'test'
}

jar {
    enabled = false
}

bootJar {
    archiveFileName = "${rootProject.name}-${version}.jar"
}

springBoot {
    buildInfo()
}
```

---

## 12. Lombok + MapStruct Annotation Processor Order

When using both Lombok and MapStruct, the annotation processor order matters. Lombok MUST run before MapStruct. Ensure the binding artifact is present:

```groovy
annotationProcessor "org.projectlombok:lombok:${lombokVersion}"
annotationProcessor "org.projectlombok:lombok-mapstruct-binding:0.2.0"
annotationProcessor "org.mapstruct:mapstruct-processor:${mapstructVersion}"
```

**DO** always add `lombok-mapstruct-binding` when using both.
**DON'T** swap the order of the annotation processors.

---

## 13. Common Gradle Tasks Reference

```bash
# Build the project
./gradlew build

# Run tests only
./gradlew test

# Run the application
./gradlew bootRun

# Run with a specific profile
./gradlew bootRun --args='--spring.profiles.active=dev'

# Build the fat jar
./gradlew bootJar

# Skip tests during build
./gradlew build -x test

# Show all dependencies
./gradlew dependencies

# Show outdated dependencies
./gradlew dependencyUpdates   # requires 'com.github.ben-manes.versions' plugin

# Clean build directory
./gradlew clean

# Refresh dependencies (clear Gradle cache)
./gradlew build --refresh-dependencies
```

---

## 14. Dependency Update Plugin (Optional but Recommended)

```groovy
// In build.gradle plugins block
id 'com.github.ben-manes.versions' version '0.51.0'
```

Run `./gradlew dependencyUpdates` to identify outdated libraries.

---

## 15. Quick Reference: Dependency Scope Rules

| Scope                | When to Use                                                 |
|----------------------|-------------------------------------------------------------|
| `implementation`     | Compile and runtime — the standard scope                    |
| `runtimeOnly`        | Only needed at runtime (JDBC drivers, JWT impl)             |
| `compileOnly`        | Only at compile time (Lombok — not in final jar)            |
| `annotationProcessor`| Annotation processing tools (Lombok, MapStruct)             |
| `developmentOnly`    | Local dev only — excluded from production jar (DevTools)    |
| `testImplementation` | Test compile and runtime (JUnit, Mockito, Testcontainers)   |
| `testRuntimeOnly`    | Test runtime only (H2, JUnit Platform Launcher)             |
