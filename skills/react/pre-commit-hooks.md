# React Pre-Commit Hooks

## Stack

- **Husky v9** — git hook management
- **lint-staged** — run linters only on staged files
- **commitlint** — enforce conventional commit messages
- **@commitlint/config-conventional** — standard commit rules

```bash
npm install -D husky lint-staged @commitlint/cli @commitlint/config-conventional
```

---

## Setup Steps

### 1. Initialize Husky

```bash
npx husky init
```

This creates a `.husky/` directory and adds a `prepare` script to `package.json`.

```json
// package.json (added automatically)
{
  "scripts": {
    "prepare": "husky"
  }
}
```

### 2. Create the pre-commit hook

```bash
# .husky/pre-commit
echo "npx lint-staged" > .husky/pre-commit
```

Or write the file directly:

```sh
# .husky/pre-commit
#!/usr/bin/env sh
npx lint-staged
```

### 3. Create the commit-msg hook

```bash
echo "npx --no -- commitlint --edit \$1" > .husky/commit-msg
```

```sh
# .husky/commit-msg
#!/usr/bin/env sh
npx --no -- commitlint --edit $1
```

### 4. Create the pre-push hook (optional — run tests before push)

```sh
# .husky/pre-push
#!/usr/bin/env sh
npm test -- --run
```

Make all hooks executable:

```bash
chmod +x .husky/pre-commit .husky/commit-msg .husky/pre-push
```

---

## lint-staged Configuration

Configure in `package.json` to run ESLint and Prettier only on staged TypeScript/React files.

```json
// package.json
{
  "lint-staged": {
    "*.{ts,tsx}": [
      "eslint --fix --max-warnings=0",
      "prettier --write"
    ],
    "*.{js,jsx}": [
      "eslint --fix --max-warnings=0",
      "prettier --write"
    ],
    "*.{json,css,scss,md}": [
      "prettier --write"
    ]
  }
}
```

Key options:
- `--fix` — auto-fix fixable ESLint violations before staging
- `--max-warnings=0` — treat any ESLint warning as an error and block the commit
- `prettier --write` — format the file in place

DON'T: Run linters on the entire project in lint-staged — that negates the performance benefit. lint-staged passes only the staged files to each command.

---

## commitlint Configuration

```json
// .commitlintrc.json
{
  "extends": ["@commitlint/config-conventional"],
  "rules": {
    "type-enum": [
      2,
      "always",
      [
        "feat",
        "fix",
        "docs",
        "style",
        "refactor",
        "test",
        "chore",
        "build",
        "ci",
        "perf",
        "revert"
      ]
    ],
    "type-case": [2, "always", "lower-case"],
    "type-empty": [2, "never"],
    "scope-case": [2, "always", "lower-case"],
    "subject-empty": [2, "never"],
    "subject-full-stop": [2, "never", "."],
    "subject-case": [2, "never", ["sentence-case", "start-case", "pascal-case", "upper-case"]],
    "header-max-length": [2, "always", 100],
    "body-leading-blank": [1, "always"],
    "footer-leading-blank": [1, "always"]
  }
}
```

---

## Conventional Commit Format

```
type(scope): subject

[optional body]

[optional footer(s)]
```

### Examples

```
feat(auth): add OAuth2 login with GitHub

fix(cart): prevent duplicate items when adding same product twice

docs(readme): update local development setup instructions

refactor(api): extract fetch logic into useApiQuery hook

test(UserProfile): add test for error state when user not found

chore(deps): upgrade react-query to v5

perf(ProductList): virtualize list to reduce DOM nodes

revert: feat(auth): add OAuth2 login with GitHub

Reverts commit a1b2c3d
```

### Commit Types

| Type | When to use |
|------|-------------|
| `feat` | A new user-facing feature |
| `fix` | A bug fix |
| `docs` | Documentation changes only |
| `style` | Formatting, whitespace — no logic change |
| `refactor` | Code restructure without feature or fix |
| `test` | Adding or updating tests |
| `chore` | Maintenance tasks (tooling, config) |
| `build` | Build system or external dependency changes |
| `ci` | CI/CD pipeline changes |
| `perf` | Performance improvements |
| `revert` | Reverting a previous commit |

DO: Keep the subject line under 100 characters.
DO: Write subjects in imperative mood ("add feature" not "added feature").
DON'T: Use a capital letter to start the subject.
DON'T: End the subject with a period.

---

## Full package.json scripts

```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "test": "vitest",
    "test:run": "vitest run",
    "test:coverage": "vitest run --coverage",
    "lint": "eslint . --max-warnings=0",
    "lint:fix": "eslint . --fix",
    "format": "prettier --write .",
    "format:check": "prettier --check .",
    "typecheck": "tsc --noEmit",
    "prepare": "husky",
    "validate": "npm run typecheck && npm run lint && npm run test:run"
  },
  "lint-staged": {
    "*.{ts,tsx}": [
      "eslint --fix --max-warnings=0",
      "prettier --write"
    ],
    "*.{js,jsx}": [
      "eslint --fix --max-warnings=0",
      "prettier --write"
    ],
    "*.{json,css,scss,md}": [
      "prettier --write"
    ]
  }
}
```

The `validate` script runs the same checks locally that CI runs, making it easy to verify everything before pushing.

---

## Skipping Hooks

Use `--no-verify` only in genuine emergencies (CI is down, critical hotfix needed immediately). Always document why the hook was skipped.

```bash
# EMERGENCY ONLY — document the reason in the commit message or PR
git commit --no-verify -m "fix: hotfix payment crash — skipping hooks, CI broken (tracked in JIRA-1234)"

git push --no-verify
```

DON'T: Make `--no-verify` a habit. If hooks are too slow or noisy, fix them instead of skipping them.
DON'T: Add `--no-verify` to npm scripts.

---

## CI Enforcement

Hooks run locally and can be skipped with `--no-verify`. Always enforce the same checks in CI so the main branch is protected regardless.

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm

      - run: npm ci

      - name: Type check
        run: npm run typecheck

      - name: Lint
        run: npm run lint

      - name: Format check
        run: npm run format:check

      - name: Test
        run: npm run test:coverage

      - name: Build
        run: npm run build
```

DO: Run the same `validate` checks in CI that hooks run locally.
DON'T: Rely solely on local hooks to enforce code quality — developers can bypass them.

---

## Troubleshooting

### Husky hooks not running

```bash
# Verify husky is installed and hooks directory exists
ls .husky/

# Ensure hooks are executable
chmod +x .husky/pre-commit .husky/commit-msg .husky/pre-push

# Re-run husky init if hooks are missing
npx husky init

# Verify prepare script ran (usually runs after npm install)
npm run prepare
```

### lint-staged not finding files

```bash
# Test lint-staged manually to see what files it detects
npx lint-staged --debug

# Ensure files are actually staged
git status

# Verify the glob pattern in lint-staged config
# "*.{ts,tsx}" matches root-level files — use "**/*.{ts,tsx}" for all subdirectories
```

Note: lint-staged globs are applied relative to the project root. The pattern `*.{ts,tsx}` matches only files in the root. Use `**/*.{ts,tsx}` to match files in any subdirectory.

```json
// Correct glob for all TypeScript files in the project
{
  "lint-staged": {
    "**/*.{ts,tsx}": ["eslint --fix --max-warnings=0", "prettier --write"]
  }
}
```

### commitlint not validating

```bash
# Test a commit message manually
echo "feat: test message" | npx commitlint

# Verify the config file is found
npx commitlint --print-config

# Check the hook file content
cat .husky/commit-msg
```

### Hooks slow down commits too much

- Move slow checks (tests) to `pre-push` instead of `pre-commit`
- Run type checking in CI only, not pre-commit (use lint-staged for lint + format)
- Use `--cache` flag with ESLint for repeated runs

```json
// Faster lint-staged with ESLint caching
{
  "lint-staged": {
    "**/*.{ts,tsx}": [
      "eslint --fix --cache --max-warnings=0",
      "prettier --write"
    ]
  }
}
```
