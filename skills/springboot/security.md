# Spring Boot Security — AI Agent Context

This file defines the authoritative patterns for implementing Spring Security in Spring Boot 3.x projects.
Agents MUST follow these patterns when generating or modifying security-related code.

---

## Core Principles

- Use Spring Security 6+. NEVER extend `WebSecurityConfigurerAdapter` (removed in Spring Security 6).
- All security configuration is done via a `SecurityFilterChain` bean.
- REST APIs are stateless: disable CSRF, disable sessions.
- Use JWT for authentication. Never store tokens in server-side sessions.
- Always hash passwords with `BCryptPasswordEncoder`. Never store plain-text passwords.
- Enable method-level security with `@EnableMethodSecurity`.

---

## SecurityConfig — Full Structure

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity(prePostEnabled = true)
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthenticationFilter jwtAuthFilter;
    private final UserDetailsService userDetailsService;
    private final AuthenticationEntryPoint authenticationEntryPoint;
    private final AccessDeniedHandler accessDeniedHandler;

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf(AbstractHttpConfigurer::disable)
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .sessionManagement(session ->
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/v1/auth/**").permitAll()
                .requestMatchers("/actuator/health").permitAll()
                .requestMatchers("/v3/api-docs/**", "/swagger-ui/**").permitAll()
                .anyRequest().authenticated()
            )
            .exceptionHandling(ex -> ex
                .authenticationEntryPoint(authenticationEntryPoint)
                .accessDeniedHandler(accessDeniedHandler)
            )
            .authenticationProvider(authenticationProvider())
            .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class);

        return http.build();
    }

    @Bean
    public AuthenticationProvider authenticationProvider() {
        DaoAuthenticationProvider provider = new DaoAuthenticationProvider();
        provider.setUserDetailsService(userDetailsService);
        provider.setPasswordEncoder(passwordEncoder());
        return provider;
    }

    @Bean
    public AuthenticationManager authenticationManager(AuthenticationConfiguration config)
            throws Exception {
        return config.getAuthenticationManager();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(List.of("https://app.example.com"));
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("Authorization", "Content-Type"));
        config.setAllowCredentials(true);
        config.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
```

DO:
- Declare `SecurityFilterChain` as a `@Bean` inside a `@Configuration` class.
- Always disable CSRF for REST APIs (`AbstractHttpConfigurer::disable`).
- Set `SessionCreationPolicy.STATELESS` for JWT-based APIs.
- Add `jwtAuthFilter` before `UsernamePasswordAuthenticationFilter`.
- Define CORS using `CorsConfigurationSource` bean, not `@CrossOrigin` on controllers.

DON'T:
- NEVER extend `WebSecurityConfigurerAdapter`.
- NEVER use `http.csrf().disable()` (deprecated fluent API) — use the lambda DSL.
- NEVER expose sensitive actuator endpoints without authentication.
- NEVER allow wildcard origins (`*`) with `allowCredentials(true)`.

---

## JWT Utility Class

```java
@Component
public class JwtService {

    @Value("${application.security.jwt.secret-key}")
    private String secretKey;

    @Value("${application.security.jwt.expiration}")
    private long jwtExpiration;

    @Value("${application.security.jwt.refresh-token.expiration}")
    private long refreshExpiration;

    public String extractUsername(String token) {
        return extractClaim(token, Claims::getSubject);
    }

    public <T> T extractClaim(String token, Function<Claims, T> claimsResolver) {
        final Claims claims = extractAllClaims(token);
        return claimsResolver.apply(claims);
    }

    public String generateToken(UserDetails userDetails) {
        return generateToken(Map.of(), userDetails);
    }

    public String generateToken(Map<String, Object> extraClaims, UserDetails userDetails) {
        return buildToken(extraClaims, userDetails, jwtExpiration);
    }

    public String generateRefreshToken(UserDetails userDetails) {
        return buildToken(Map.of(), userDetails, refreshExpiration);
    }

    private String buildToken(
            Map<String, Object> extraClaims,
            UserDetails userDetails,
            long expiration) {
        return Jwts.builder()
            .claims(extraClaims)
            .subject(userDetails.getUsername())
            .issuedAt(new Date(System.currentTimeMillis()))
            .expiration(new Date(System.currentTimeMillis() + expiration))
            .signWith(getSignInKey(), Jwts.SIG.HS256)
            .compact();
    }

    public boolean isTokenValid(String token, UserDetails userDetails) {
        final String username = extractUsername(token);
        return username.equals(userDetails.getUsername()) && !isTokenExpired(token);
    }

    private boolean isTokenExpired(String token) {
        return extractExpiration(token).before(new Date());
    }

    private Date extractExpiration(String token) {
        return extractClaim(token, Claims::getExpiration);
    }

    private Claims extractAllClaims(String token) {
        return Jwts.parser()
            .verifyWith(getSignInKey())
            .build()
            .parseSignedClaims(token)
            .getPayload();
    }

    private SecretKey getSignInKey() {
        byte[] keyBytes = Decoders.BASE64.decode(secretKey);
        return Keys.hmacShaKeyFor(keyBytes);
    }
}
```

DO:
- Use `io.jsonwebtoken:jjwt-api`, `jjwt-impl`, `jjwt-jackson` (version 0.12+).
- Store the JWT secret key in application properties (externalized from code), loaded via `@Value`.
- Use `Jwts.SIG.HS256` (jjwt 0.12+ API). NEVER use deprecated `SignatureAlgorithm.HS256`.
- Set expiration on every token.
- Validate both signature and expiration in `isTokenValid`.

DON'T:
- NEVER hardcode secret keys in source code.
- NEVER log tokens or claims.
- NEVER use a secret key shorter than 256 bits for HMAC-SHA256.

---

## JWT Authentication Filter

```java
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtService jwtService;
    private final UserDetailsService userDetailsService;

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        final String authHeader = request.getHeader("Authorization");

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            filterChain.doFilter(request, response);
            return;
        }

        final String jwt = authHeader.substring(7);
        final String userEmail;

        try {
            userEmail = jwtService.extractUsername(jwt);
        } catch (JwtException e) {
            filterChain.doFilter(request, response);
            return;
        }

        if (userEmail != null && SecurityContextHolder.getContext().getAuthentication() == null) {
            UserDetails userDetails = userDetailsService.loadUserByUsername(userEmail);

            if (jwtService.isTokenValid(jwt, userDetails)) {
                UsernamePasswordAuthenticationToken authToken =
                    new UsernamePasswordAuthenticationToken(
                        userDetails,
                        null,
                        userDetails.getAuthorities()
                    );
                authToken.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                SecurityContextHolder.getContext().setAuthentication(authToken);
            }
        }

        filterChain.doFilter(request, response);
    }
}
```

DO:
- Extend `OncePerRequestFilter` to guarantee single execution per request.
- Extract the token from the `Authorization: Bearer <token>` header.
- Set `SecurityContextHolder` only when the token is valid and no authentication exists yet.
- Catch `JwtException` and continue the filter chain (do not throw — let the entry point handle it).
- Call `filterChain.doFilter` in all code paths.

DON'T:
- NEVER throw exceptions from within `doFilterInternal` — always continue the chain.
- NEVER skip calling `filterChain.doFilter`.

---

## UserDetailsService Implementation

```java
@Service
@RequiredArgsConstructor
public class UserDetailsServiceImpl implements UserDetailsService {

    private final UserRepository userRepository;

    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        return userRepository.findByEmail(username)
            .orElseThrow(() ->
                new UsernameNotFoundException("User not found: " + username));
    }
}
```

Notes:
- `User` entity should implement `UserDetails` directly, or adapt it via a wrapper.
- The "username" field is the user's email in most applications.

---

## User Entity Implementing UserDetails

```java
@Entity
@Table(name = "users")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class User implements UserDetails {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    private String email;

    private String password;

    @Enumerated(EnumType.STRING)
    private Role role;

    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return List.of(new SimpleGrantedAuthority("ROLE_" + role.name()));
    }

    @Override
    public String getUsername() {
        return email;
    }

    @Override
    public boolean isAccountNonExpired() { return true; }

    @Override
    public boolean isAccountNonLocked() { return true; }

    @Override
    public boolean isCredentialsNonExpired() { return true; }

    @Override
    public boolean isEnabled() { return true; }
}
```

---

## Role-Based Access Control

### Method-Level Security

```java
// Require @EnableMethodSecurity on SecurityConfig

@RestController
@RequestMapping("/api/v1/admin")
public class AdminController {

    @GetMapping("/users")
    @PreAuthorize("hasRole('ADMIN')")
    public List<UserResponse> getAllUsers() { ... }

    @DeleteMapping("/users/{id}")
    @PreAuthorize("hasRole('ADMIN') or #id == authentication.principal.id")
    public void deleteUser(@PathVariable UUID id) { ... }

    @GetMapping("/reports")
    @PreAuthorize("hasAnyRole('ADMIN', 'MANAGER')")
    public List<Report> getReports() { ... }
}
```

DO:
- Annotate `@EnableMethodSecurity(prePostEnabled = true)` on `SecurityConfig`.
- Use `@PreAuthorize` for access control at the method level.
- Use Spring Expression Language (SpEL) to reference method parameters for ownership checks.

DON'T:
- NEVER rely solely on URL-based security for sensitive operations.
- NEVER use `@Secured` (older API) — prefer `@PreAuthorize`.

---

## Exception Handling

### AuthenticationEntryPoint

```java
@Component
public class JwtAuthenticationEntryPoint implements AuthenticationEntryPoint {

    private final ObjectMapper objectMapper;

    public JwtAuthenticationEntryPoint(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    public void commence(
            HttpServletRequest request,
            HttpServletResponse response,
            AuthenticationException authException) throws IOException {

        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);

        Map<String, Object> body = Map.of(
            "status", 401,
            "error", "Unauthorized",
            "message", authException.getMessage(),
            "path", request.getServletPath()
        );

        objectMapper.writeValue(response.getOutputStream(), body);
    }
}
```

### AccessDeniedHandler

```java
@Component
public class CustomAccessDeniedHandler implements AccessDeniedHandler {

    private final ObjectMapper objectMapper;

    public CustomAccessDeniedHandler(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @Override
    public void handle(
            HttpServletRequest request,
            HttpServletResponse response,
            AccessDeniedException accessDeniedException) throws IOException {

        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setStatus(HttpServletResponse.SC_FORBIDDEN);

        Map<String, Object> body = Map.of(
            "status", 403,
            "error", "Forbidden",
            "message", "You do not have permission to access this resource.",
            "path", request.getServletPath()
        );

        objectMapper.writeValue(response.getOutputStream(), body);
    }
}
```

DO:
- Always return JSON error responses (not HTML) from `AuthenticationEntryPoint` and `AccessDeniedHandler`.
- Return `401 Unauthorized` for missing/invalid tokens.
- Return `403 Forbidden` for authenticated but unauthorized requests.

---

## Token Refresh Pattern

```java
@PostMapping("/refresh-token")
public ResponseEntity<AuthResponse> refreshToken(HttpServletRequest request) {
    final String authHeader = request.getHeader(HttpHeaders.AUTHORIZATION);

    if (authHeader == null || !authHeader.startsWith("Bearer ")) {
        return ResponseEntity.badRequest().build();
    }

    final String refreshToken = authHeader.substring(7);
    final String userEmail = jwtService.extractUsername(refreshToken);

    if (userEmail != null) {
        UserDetails user = userDetailsService.loadUserByUsername(userEmail);

        if (jwtService.isTokenValid(refreshToken, user)) {
            String accessToken = jwtService.generateToken(user);
            return ResponseEntity.ok(AuthResponse.builder()
                .accessToken(accessToken)
                .refreshToken(refreshToken)
                .build());
        }
    }

    return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
}
```

---

## SecurityContext Access Pattern

```java
// In a service method — retrieve the currently authenticated user
public User getCurrentUser() {
    Authentication authentication = SecurityContextHolder.getContext().getAuthentication();

    if (authentication == null || !authentication.isAuthenticated()) {
        throw new IllegalStateException("No authenticated user in context");
    }

    return (User) authentication.getPrincipal();
}

// In a controller via method parameter injection (preferred for controllers)
@GetMapping("/me")
public UserResponse getMe(@AuthenticationPrincipal User currentUser) {
    return userMapper.toResponse(currentUser);
}
```

DO:
- Prefer `@AuthenticationPrincipal` injection in controllers over manual `SecurityContextHolder` access.
- Use `SecurityContextHolder.getContext().getAuthentication()` in services where injection is not available.
- Cast `.getPrincipal()` only after verifying `authentication.isAuthenticated()`.

---

## Application Properties

```yaml
application:
  security:
    jwt:
      secret-key: 404E635266556A586E3272357538782F413F4428472B4B6250645367566B5970
      expiration: 86400000       # 1 day in ms
      refresh-token:
        expiration: 604800000    # 7 days in ms
```

---

## Dependencies (Maven)

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-security</artifactId>
</dependency>
<dependency>
    <groupId>io.jsonwebtoken</groupId>
    <artifactId>jjwt-api</artifactId>
    <version>0.12.6</version>
</dependency>
<dependency>
    <groupId>io.jsonwebtoken</groupId>
    <artifactId>jjwt-impl</artifactId>
    <version>0.12.6</version>
    <scope>runtime</scope>
</dependency>
<dependency>
    <groupId>io.jsonwebtoken</groupId>
    <artifactId>jjwt-jackson</artifactId>
    <version>0.12.6</version>
    <scope>runtime</scope>
</dependency>
```

---

## Summary Checklist

- [ ] `SecurityFilterChain` bean declared, no `WebSecurityConfigurerAdapter`
- [ ] CSRF disabled
- [ ] Session policy set to `STATELESS`
- [ ] JWT filter extends `OncePerRequestFilter`, added before `UsernamePasswordAuthenticationFilter`
- [ ] `AuthenticationEntryPoint` returns JSON `401`
- [ ] `AccessDeniedHandler` returns JSON `403`
- [ ] Passwords encoded with `BCryptPasswordEncoder`
- [ ] `@EnableMethodSecurity` on config class
- [ ] Secret key externalized to application properties
- [ ] CORS configured via `CorsConfigurationSource` bean
- [ ] Public endpoints explicitly permitted (auth, health, docs)
- [ ] Token refresh endpoint implemented
