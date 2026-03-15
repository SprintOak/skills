# Pagination Skill Guide for Spring Boot (MongoDB / JPA)

## Overview

Pagination is used to fetch large datasets in smaller chunks to improve
performance and reduce memory usage.

Typical use cases: - Listing records - Audit logs - Reports

Spring Boot provides built-in pagination support through **Pageable**
and **Page** interfaces.

------------------------------------------------------------------------

# Request Pattern

Standard pagination query parameters:

    ?page=0&size=10&sort=createdAt,desc

Meaning:

    page → page number (starts from 0)
    size → records per page
    sort → field,direction

# Benefits

-   Reduces database load
-   Improves API performance
-   Prevents memory overflow
-   Supports infinite scroll UI