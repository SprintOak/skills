# ESLint and Prettier Configuration for React + TypeScript

This document defines the canonical ESLint and Prettier setup for React + TypeScript projects. This configuration enforces code quality, consistency, and catches real bugs before they reach review.

---

## Package Installation

```bash
npm install --save-dev \
  eslint \
  @typescript-eslint/parser \
  @typescript-eslint/eslint-plugin \
  eslint-plugin-react \
  eslint-plugin-react-hooks \
  eslint-plugin-jsx-a11y \
  eslint-plugin-import \
  eslint-config-prettier \
  prettier
```

---

## ESLint Configuration — `.eslintrc.json`

This is the full recommended configuration. Copy this into `.eslintrc.json` at the project root.

```json
{
  "root": true,
  "env": {
    "browser": true,
    "es2020": true,
    "node": true
  },
  "parser": "@typescript-eslint/parser",
  "parserOptions": {
    "ecmaVersion": "latest",
    "sourceType": "module",
    "ecmaFeatures": {
      "jsx": true
    },
    "project": "./tsconfig.json"
  },
  "settings": {
    "react": {
      "version": "detect"
    },
    "import/resolver": {
      "typescript": {
        "alwaysTryTypes": true,
        "project": "./tsconfig.json"
      }
    }
  },
  "plugins": [
    "@typescript-eslint",
    "react",
    "react-hooks",
    "jsx-a11y",
    "import"
  ],
  "extends": [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
    "plugin:@typescript-eslint/recommended-requiring-type-checking",
    "plugin:react/recommended",
    "plugin:react/jsx-runtime",
    "plugin:react-hooks/recommended",
    "plugin:jsx-a11y/recommended",
    "plugin:import/recommended",
    "plugin:import/typescript",
    "prettier"
  ],
  "rules": {
    // ── TypeScript ──────────────────────────────────────────────────────────
    "@typescript-eslint/no-explicit-any": "error",
    "@typescript-eslint/no-unused-vars": [
      "error",
      {
        "argsIgnorePattern": "^_",
        "varsIgnorePattern": "^_",
        "destructuredArrayIgnorePattern": "^_"
      }
    ],
    "@typescript-eslint/consistent-type-imports": [
      "error",
      { "prefer": "type-imports", "fixStyle": "inline-type-imports" }
    ],
    "@typescript-eslint/no-non-null-assertion": "error",
    "@typescript-eslint/no-floating-promises": "error",
    "@typescript-eslint/await-thenable": "error",
    "@typescript-eslint/no-misused-promises": [
      "error",
      { "checksVoidReturn": { "attributes": false } }
    ],
    "@typescript-eslint/prefer-nullish-coalescing": "warn",
    "@typescript-eslint/prefer-optional-chain": "warn",

    // ── React ───────────────────────────────────────────────────────────────
    "react-hooks/rules-of-hooks": "error",
    "react-hooks/exhaustive-deps": "warn",
    "react/prop-types": "off",
    "react/display-name": "error",
    "react/no-array-index-key": "warn",
    "react/self-closing-comp": ["error", { "component": true, "html": false }],
    "react/jsx-curly-brace-presence": [
      "error",
      { "props": "never", "children": "never" }
    ],

    // ── Accessibility ───────────────────────────────────────────────────────
    "jsx-a11y/anchor-is-valid": [
      "error",
      {
        "components": ["Link"],
        "specialLink": ["to"]
      }
    ],
    "jsx-a11y/no-autofocus": "warn",

    // ── Import order ────────────────────────────────────────────────────────
    "import/order": [
      "error",
      {
        "groups": [
          "builtin",
          "external",
          "internal",
          ["parent", "sibling", "index"],
          "type"
        ],
        "pathGroups": [
          {
            "pattern": "react",
            "group": "external",
            "position": "before"
          },
          {
            "pattern": "@/**",
            "group": "internal"
          }
        ],
        "pathGroupsExcludedImportTypes": ["react"],
        "newlines-between": "always",
        "alphabetize": {
          "order": "asc",
          "caseInsensitive": true
        }
      }
    ],
    "import/no-duplicates": "error",
    "import/no-self-import": "error",
    "import/no-cycle": ["error", { "maxDepth": 3 }],
    "import/no-unused-modules": ["warn", { "unusedExports": true }],

    // ── General ─────────────────────────────────────────────────────────────
    "no-console": [
      "warn",
      {
        "allow": ["warn", "error"]
      }
    ],
    "no-debugger": "error",
    "no-alert": "error",
    "prefer-const": "error",
    "no-var": "error",
    "eqeqeq": ["error", "always", { "null": "ignore" }],
    "object-shorthand": ["error", "always"],
    "no-nested-ternary": "error"
  },
  "overrides": [
    {
      "files": ["**/*.test.ts", "**/*.test.tsx", "**/*.spec.ts", "**/*.spec.tsx"],
      "env": {
        "jest": true
      },
      "rules": {
        "@typescript-eslint/no-explicit-any": "off",
        "import/no-unused-modules": "off"
      }
    },
    {
      "files": ["vite.config.ts", "jest.config.ts", "*.config.ts"],
      "rules": {
        "import/no-unused-modules": "off"
      }
    }
  ]
}
```

---

## Alternative: Flat Config (`eslint.config.js`)

If using ESLint v9+ with the flat config format:

```js
// eslint.config.js
import js from '@eslint/js';
import tseslint from 'typescript-eslint';
import reactPlugin from 'eslint-plugin-react';
import reactHooksPlugin from 'eslint-plugin-react-hooks';
import jsxA11yPlugin from 'eslint-plugin-jsx-a11y';
import importPlugin from 'eslint-plugin-import';
import prettierConfig from 'eslint-config-prettier';

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        project: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
    plugins: {
      react: reactPlugin,
      'react-hooks': reactHooksPlugin,
      'jsx-a11y': jsxA11yPlugin,
      import: importPlugin,
    },
    settings: {
      react: { version: 'detect' },
    },
    rules: {
      '@typescript-eslint/no-explicit-any': 'error',
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      // ... (same rules as above)
    },
  },
  prettierConfig,
);
```

---

## Prettier Configuration — `.prettierrc`

```json
{
  "printWidth": 100,
  "tabWidth": 2,
  "useTabs": false,
  "semi": true,
  "singleQuote": true,
  "quoteProps": "as-needed",
  "jsxSingleQuote": false,
  "trailingComma": "all",
  "bracketSpacing": true,
  "bracketSameLine": false,
  "arrowParens": "always",
  "endOfLine": "lf",
  "embeddedLanguageFormatting": "auto"
}
```

### Key setting explanations:

| Setting | Value | Reason |
|---|---|---|
| `printWidth` | `100` | 80 is too narrow for TypeScript generics; 120 is too wide for split screens |
| `singleQuote` | `true` | Consistent with most TypeScript/JavaScript conventions |
| `trailingComma` | `"all"` | Cleaner diffs — adding/removing items doesn't change the previous line |
| `arrowParens` | `"always"` | `(x) => x` is clearer than `x => x` and avoids confusion with generics |
| `bracketSameLine` | `false` | JSX closing `>` on its own line for readability |
| `endOfLine` | `"lf"` | Cross-platform consistency |

---

## `.eslintignore`

```
# Build output
dist/
build/
out/

# Dependencies
node_modules/

# Auto-generated files
src/routeTree.gen.ts
src/vite-env.d.ts
coverage/

# Config files that can't be typed
*.config.cjs
```

---

## `.prettierignore`

```
# Build output
dist/
build/
out/

# Dependencies
node_modules/

# Lock files — do not format
package-lock.json
yarn.lock
pnpm-lock.yaml

# Auto-generated
src/routeTree.gen.ts
coverage/

# Static assets
public/
```

---

## VSCode Settings

Add this to `.vscode/settings.json` to enable format-on-save and auto-fix for all team members:

```json
{
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll.eslint": "explicit",
    "source.organizeImports": "never"
  },
  "editor.tabSize": 2,
  "editor.insertSpaces": true,
  "files.eol": "\n",
  "typescript.preferences.importModuleSpecifier": "non-relative",
  "typescript.updateImportsOnFileMove.enabled": "always",
  "eslint.validate": [
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact"
  ],
  "[typescript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[typescriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },
  "[json]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  }
}
```

Also add `.vscode/extensions.json` to recommend required extensions:

```json
{
  "recommendations": [
    "esbenp.prettier-vscode",
    "dbaeumer.vscode-eslint",
    "bradlc.vscode-tailwindcss",
    "ms-vscode.vscode-typescript-next"
  ]
}
```

---

## `package.json` Scripts

```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "lint": "eslint src --ext .ts,.tsx --report-unused-disable-directives --max-warnings 0",
    "lint:fix": "eslint src --ext .ts,.tsx --fix",
    "format": "prettier --write \"src/**/*.{ts,tsx,css,json}\"",
    "format:check": "prettier --check \"src/**/*.{ts,tsx,css,json}\"",
    "type-check": "tsc --noEmit",
    "validate": "npm run type-check && npm run lint && npm run format:check"
  }
}
```

- `lint` — reports errors, fails CI on any warning (`--max-warnings 0`).
- `lint:fix` — auto-fixes fixable issues in development.
- `format` — writes Prettier formatting to all matching files.
- `format:check` — checks formatting without writing (used in CI).
- `type-check` — runs the TypeScript compiler without emitting output.
- `validate` — runs all checks in sequence; run before pushing or opening a PR.

---

## ESLint + Prettier Integration

Prettier and ESLint can conflict when ESLint has formatting rules. `eslint-config-prettier` solves this by disabling all ESLint rules that Prettier handles.

**The rule:** Prettier handles all formatting. ESLint handles code quality.

```json
// In .eslintrc.json extends — "prettier" must be LAST to override everything
"extends": [
  "eslint:recommended",
  "plugin:@typescript-eslint/recommended",
  "plugin:react/recommended",
  "plugin:react-hooks/recommended",
  "plugin:jsx-a11y/recommended",
  "prettier"  // ← must be last
]
```

Do NOT use `eslint-plugin-prettier`. It runs Prettier as an ESLint rule and shows Prettier errors as ESLint errors, which slows down linting significantly. Instead, run Prettier separately (as shown in the scripts above).

---

## Rule Explanations: Why Each Rule Matters

### `@typescript-eslint/no-explicit-any: "error"`

`any` disables TypeScript's type checker entirely. Every `any` in the codebase is a potential runtime error hiding in plain sight.

```ts
// This error is caught at runtime, not compile time, because of any
function parseUser(data: any) {
  return data.user.profil.name; // typo: 'profil' instead of 'profile' — no error!
}
```

### `@typescript-eslint/no-unused-vars: "error"`

Unused variables are dead code that misleads future readers. The `argsIgnorePattern: "^_"` allows intentional unused parameters to be prefixed with `_`.

```ts
// CORRECT — intentionally unused parameter
array.map((_item, index) => index);
```

### `react-hooks/rules-of-hooks: "error"`

Violating the rules of hooks causes React's internal state tracking to break in unpredictable ways. This rule prevents those bugs statically.

### `react-hooks/exhaustive-deps: "warn"`

Stale closures are one of the most common bugs in React. Missing dependencies in `useEffect` or `useCallback` dependency arrays cause components to read stale values.

This is a `warn` (not `error`) because there are rare legitimate reasons to intentionally omit a dependency (e.g., you only want an effect to run once). When ignoring, add a comment:

```ts
useEffect(() => {
  initializeOnce(); // intentionally run only on mount
  // eslint-disable-next-line react-hooks/exhaustive-deps
}, []);
```

### `no-console: ["warn", { "allow": ["warn", "error"] }]`

`console.log` left in production code pollutes browser consoles and can leak sensitive data. `console.warn` and `console.error` are allowed because they indicate genuine issues worth surfacing.

### `import/no-cycle: "error"`

Circular imports cause hard-to-debug initialization order errors and prevent tree-shaking. Detecting them statically prevents the problem entirely.

### `react/no-array-index-key: "warn"`

Using array index as a React key causes incorrect behavior when the list is reordered, filtered, or has items added/removed. Items retain old state because React uses the key to match DOM nodes to component instances.

---

## Common ESLint Disable Patterns and When They Are Acceptable

```ts
// Acceptable — third-party library missing types, tracked in issue
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const instance = new LegacyLibrary() as any;

// Acceptable — intentional single-run effect
useEffect(() => {
  setupAnalytics();
  // eslint-disable-next-line react-hooks/exhaustive-deps
}, []);

// NOT acceptable — hiding real problems
/* eslint-disable @typescript-eslint/no-explicit-any */
// ...entire file uses any
/* eslint-enable @typescript-eslint/no-explicit-any */
```

Never disable rules for an entire file unless the file is auto-generated and cannot be modified (e.g., `routeTree.gen.ts`).

---

## Pre-commit Hook with lint-staged

Enforce linting and formatting on every commit using `husky` and `lint-staged`:

```bash
npm install --save-dev husky lint-staged
npx husky init
```

```json
// package.json
{
  "lint-staged": {
    "src/**/*.{ts,tsx}": [
      "eslint --fix --max-warnings 0",
      "prettier --write"
    ],
    "src/**/*.{css,json,md}": [
      "prettier --write"
    ]
  }
}
```

```sh
# .husky/pre-commit
npx lint-staged
```

This ensures no commit can introduce linting errors or unformatted code.
