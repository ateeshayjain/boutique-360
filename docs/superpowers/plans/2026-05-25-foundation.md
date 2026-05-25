# Foundation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a deployable Next.js 15 + Supabase + Vercel skeleton with staff auth, base schema, integrations wired (Inngest/Sentry/Resend), and CI/CD — ready for feature modules (CRM, Catalog, Commerce, etc.) to build on without scaffolding work.

**Architecture:** Single Next.js 15 (App Router) repo with route groups `(public)` and `(admin)`. Supabase provides Postgres + Auth + Storage + Realtime. RLS scoped by `boutique_id` via JWT claim + Postgres `current_setting`. Background jobs via Inngest. Per-PR Vercel preview deploys with Supabase branch DBs.

**Tech Stack:** Next.js 15 (App Router, RSC), TypeScript strict, pnpm, Tailwind CSS, shadcn/ui, Supabase (Postgres 15 + Auth + Storage), Vercel, Inngest, Sentry, Resend, Vitest + React Testing Library, Playwright, Husky + lint-staged + commitlint, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-05-25-boutique-360-design.md`

---

## File Structure

```
boutique-360/
├── .github/
│   └── workflows/
│       └── ci.yml                          # typecheck, lint, test, build, supabase dry-run
├── .husky/
│   ├── pre-commit                          # lint-staged
│   └── commit-msg                          # commitlint
├── docs/
│   └── superpowers/                        # specs/, plans/ (already exists)
├── public/
├── src/
│   ├── app/
│   │   ├── (public)/
│   │   │   └── page.tsx                    # placeholder home
│   │   ├── (admin)/
│   │   │   ├── layout.tsx                  # auth-gated wrapper
│   │   │   └── admin/
│   │   │       ├── page.tsx                # dashboard stub
│   │   │       └── sign-in/page.tsx        # magic-link form
│   │   ├── api/
│   │   │   ├── health/route.ts             # health check endpoint
│   │   │   ├── inngest/route.ts            # Inngest webhook
│   │   │   └── auth/callback/route.ts      # Supabase auth callback
│   │   ├── layout.tsx                      # root
│   │   └── globals.css                     # tailwind base
│   ├── lib/
│   │   ├── supabase/
│   │   │   ├── client.ts                   # browser client
│   │   │   ├── server.ts                   # server client w/ cookies
│   │   │   ├── service-role.ts             # privileged client (jobs only)
│   │   │   ├── context.ts                  # setBoutiqueContext helper
│   │   │   └── types.ts                    # generated types (gitignored or committed)
│   │   ├── inngest/
│   │   │   ├── client.ts                   # Inngest client init
│   │   │   └── functions/
│   │   │       └── ping.ts                 # sample function for smoke test
│   │   ├── sentry/
│   │   │   └── config.ts                   # shared sentry config
│   │   ├── resend/
│   │   │   └── client.ts                   # Resend wrapper + base email layout
│   │   ├── settings/
│   │   │   ├── get.ts                      # read+decrypt settings
│   │   │   └── set.ts                      # write+encrypt settings
│   │   ├── events/
│   │   │   └── emit.ts                     # append to events table
│   │   └── env.ts                          # zod-validated env vars
│   ├── components/
│   │   └── ui/                             # shadcn/ui drops here
│   ├── middleware.ts                       # auth + boutique_id context
│   └── sentry.{client,server,edge}.config.ts
├── supabase/
│   ├── config.toml                         # supabase CLI config
│   ├── migrations/
│   │   ├── 0001_init_extensions.sql        # pgsodium, pgcrypto, uuid
│   │   ├── 0002_boutiques.sql              # boutiques table
│   │   ├── 0003_staff_users.sql            # staff_users + role enum
│   │   ├── 0004_events.sql                 # append-only audit/event stream
│   │   ├── 0005_settings.sql               # encrypted per-boutique settings
│   │   ├── 0006_rls_helpers.sql            # set_boutique_id() function + base policies
│   │   └── 0007_updated_at_trigger.sql     # trigger function for updated_at
│   └── seed.sql                            # dev seed: one boutique + one owner
├── tests/
│   ├── unit/
│   │   ├── env.test.ts
│   │   ├── settings.test.ts
│   │   ├── events.test.ts
│   │   ├── rls.test.ts
│   │   └── health.test.ts
│   └── e2e/
│       ├── auth.spec.ts
│       └── health.spec.ts
├── .env.example                            # all required env vars documented
├── .gitignore
├── .nvmrc                                  # node version pin
├── .prettierrc
├── .prettierignore
├── commitlint.config.cjs
├── eslint.config.mjs
├── next.config.mjs
├── package.json
├── playwright.config.ts
├── pnpm-workspace.yaml                     # future-proof for packages/
├── postcss.config.mjs
├── README.md
├── tailwind.config.ts
├── tsconfig.json
└── vitest.config.ts
```

**Decomposition principle:** every file under `src/lib/` exposes ≤5 named exports with one responsibility. No file >300 lines in this plan. Tests live next to features under `tests/` mirroring `src/` structure.

---

## Chunk 1: Repo scaffold & tooling

### Task 1.1: Initialize pnpm + Next.js 15 + TypeScript strict

**Files:**
- Create: `package.json`, `pnpm-workspace.yaml`, `.nvmrc`, `tsconfig.json`, `next.config.mjs`, `tailwind.config.ts`, `postcss.config.mjs`, `src/app/layout.tsx`, `src/app/globals.css`, `src/app/(public)/page.tsx`, `.gitignore`

- [ ] **Step 1: Init repo + Node pin**

```bash
cd "/Users/ateeshayjain/WIP Apps/boutique-360"
echo "v20.18.0" > .nvmrc
nvm install && nvm use
corepack enable
corepack prepare pnpm@9.12.0 --activate
```

- [ ] **Step 2: Scaffold Next.js 15 (non-interactive)**

```bash
pnpm dlx create-next-app@15 . --ts --tailwind --app --src-dir --import-alias "@/*" --no-eslint --no-turbopack --use-pnpm --yes
```

Expected: `package.json`, `src/app/`, Tailwind configured. If prompts appear, accept defaults.

- [ ] **Step 3: Replace tsconfig for strict mode**

Overwrite `tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["dom", "dom.iterable", "ES2022"],
    "allowJs": false,
    "skipLibCheck": true,
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "forceConsistentCasingInFileNames": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
```

- [ ] **Step 4: Add pnpm-workspace.yaml**

```yaml
packages:
  - .
```

- [ ] **Step 5: Replace home page with placeholder**

`src/app/page.tsx`:

```tsx
export default function Home() {
  return (
    <main className="flex min-h-screen items-center justify-center">
      <h1 className="text-4xl font-semibold">Boutique 360</h1>
    </main>
  );
}
```

(Delete any boilerplate from `create-next-app` in `src/app/globals.css` beyond Tailwind directives.)

- [ ] **Step 6: Verify dev server boots**

Run: `pnpm dev`
Expected: `http://localhost:3000` renders "Boutique 360".
Stop with Ctrl-C.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: scaffold Next.js 15 + TS strict + Tailwind"
```

---

### Task 1.2: Add Vitest + React Testing Library

**Files:**
- Create: `vitest.config.ts`, `tests/setup.ts`, `tests/unit/sanity.test.ts`
- Modify: `package.json` (scripts), `tsconfig.json` (add `tests` to include)

- [ ] **Step 1: Install deps**

```bash
pnpm add -D vitest @vitest/coverage-v8 @testing-library/react @testing-library/jest-dom @testing-library/user-event jsdom @vitejs/plugin-react
```

- [ ] **Step 2: Create vitest.config.ts**

```ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "node:path";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    setupFiles: ["./tests/setup.ts"],
    globals: true,
    include: ["tests/unit/**/*.test.{ts,tsx}"],
    coverage: { reporter: ["text", "html"], include: ["src/**"] },
  },
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
});
```

- [ ] **Step 3: Create tests/setup.ts**

```ts
import "@testing-library/jest-dom/vitest";
```

- [ ] **Step 4: Write the failing sanity test**

`tests/unit/sanity.test.ts`:

```ts
import { describe, expect, it } from "vitest";

describe("sanity", () => {
  it("runs", () => {
    expect(1 + 1).toBe(2);
  });
});
```

- [ ] **Step 5: Add scripts to package.json**

Add under `"scripts"`:

```json
"test": "vitest run",
"test:watch": "vitest",
"test:coverage": "vitest run --coverage"
```

- [ ] **Step 6: Run test**

Run: `pnpm test`
Expected: 1 passed.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "test: add Vitest + RTL with sanity check"
```

---

### Task 1.3: Add Playwright

**Files:**
- Create: `playwright.config.ts`, `tests/e2e/smoke.spec.ts`
- Modify: `package.json` (scripts), `.gitignore`

- [ ] **Step 1: Install Playwright**

```bash
pnpm dlx playwright@latest install --with-deps chromium
pnpm add -D @playwright/test
```

- [ ] **Step 2: Create playwright.config.ts**

```ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? "github" : "html",
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL ?? "http://localhost:3000",
    trace: "on-first-retry",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: "pnpm dev",
    url: "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
```

- [ ] **Step 3: Write the failing e2e smoke test**

`tests/e2e/smoke.spec.ts`:

```ts
import { expect, test } from "@playwright/test";

test("home page renders", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Boutique 360" })).toBeVisible();
});
```

- [ ] **Step 4: Append to .gitignore**

```
/test-results/
/playwright-report/
/playwright/.cache/
```

- [ ] **Step 5: Add scripts to package.json**

```json
"test:e2e": "playwright test",
"test:e2e:ui": "playwright test --ui"
```

- [ ] **Step 6: Run e2e**

Run: `pnpm test:e2e`
Expected: 1 passed (1 chromium).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "test: add Playwright e2e with smoke test"
```

---

### Task 1.4: ESLint + Prettier

**Files:**
- Create: `eslint.config.mjs`, `.prettierrc`, `.prettierignore`
- Modify: `package.json`

- [ ] **Step 1: Install**

```bash
pnpm add -D eslint @eslint/js typescript-eslint eslint-config-next eslint-plugin-react-hooks eslint-plugin-tailwindcss prettier prettier-plugin-tailwindcss
```

- [ ] **Step 2: Create eslint.config.mjs (flat config)**

**Note:** `eslint-config-next` in Next 15 ships flat-config support via `@next/eslint-plugin-next`. Verify the package's current README on install — if `next()` factory isn't exported in your installed version, use the plugin-based form below.

```js
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import nextPlugin from "@next/eslint-plugin-next";

export default [
  js.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  {
    plugins: { "@next/next": nextPlugin },
    rules: {
      ...nextPlugin.configs.recommended.rules,
      ...nextPlugin.configs["core-web-vitals"].rules,
    },
  },
  {
    languageOptions: {
      parserOptions: { project: "./tsconfig.json" },
    },
    rules: {
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
      "@typescript-eslint/consistent-type-imports": "error",
    },
  },
  { ignores: [".next/", "node_modules/", "supabase/.branches/", "tests/e2e/.report/"] },
];
```

Adjust the install command to swap `eslint-config-next` for `@next/eslint-plugin-next` if needed:

```bash
pnpm add -D @next/eslint-plugin-next
```

- [ ] **Step 3: Create .prettierrc**

```json
{
  "semi": true,
  "singleQuote": false,
  "trailingComma": "all",
  "printWidth": 100,
  "plugins": ["prettier-plugin-tailwindcss"]
}
```

- [ ] **Step 4: Create .prettierignore**

```
.next
node_modules
pnpm-lock.yaml
supabase/.branches
```

- [ ] **Step 5: Add scripts to package.json**

```json
"lint": "eslint .",
"format": "prettier --write .",
"format:check": "prettier --check ."
```

- [ ] **Step 6: Run lint + format check**

Run: `pnpm lint && pnpm format`
Expected: no errors (autofix any).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: ESLint flat config + Prettier with Tailwind plugin"
```

---

### Task 1.5: Husky + lint-staged + commitlint

**Files:**
- Create: `.husky/pre-commit`, `.husky/commit-msg`, `commitlint.config.cjs`
- Modify: `package.json`

- [ ] **Step 1: Install**

```bash
pnpm add -D husky lint-staged @commitlint/cli @commitlint/config-conventional
pnpm dlx husky init
```

- [ ] **Step 2: Create commitlint.config.cjs**

```js
module.exports = { extends: ["@commitlint/config-conventional"] };
```

- [ ] **Step 3: Configure lint-staged in package.json**

```json
"lint-staged": {
  "*.{ts,tsx,js,mjs,cjs}": ["eslint --fix", "prettier --write"],
  "*.{json,md,yml,yaml,css}": ["prettier --write"]
}
```

- [ ] **Step 4: Replace .husky/pre-commit**

```sh
pnpm exec lint-staged
```

- [ ] **Step 5: Create .husky/commit-msg**

```sh
pnpm exec commitlint --edit "$1"
```

- [ ] **Step 6: Verify by attempting a bad commit message**

```bash
git commit --allow-empty -m "bad message" || echo "expected fail"
```

Expected: commitlint rejects.

- [ ] **Step 7: Commit (good message)**

```bash
git add -A
git commit -m "chore: add Husky + lint-staged + commitlint"
```

---

### Task 1.6: shadcn/ui base + Button

**Files:**
- Create: `components.json` (shadcn), `src/components/ui/button.tsx`, `src/lib/utils.ts`
- Modify: `tailwind.config.ts`, `src/app/globals.css`

- [ ] **Step 1: Init shadcn/ui**

```bash
pnpm dlx shadcn@latest init -d
pnpm dlx shadcn@latest add button
```

Accept defaults: New York style, neutral base, CSS variables.

- [ ] **Step 2: Verify Button renders**

Modify `src/app/page.tsx`:

```tsx
import { Button } from "@/components/ui/button";

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4">
      <h1 className="text-4xl font-semibold">Boutique 360</h1>
      <Button>Hello</Button>
    </main>
  );
}
```

- [ ] **Step 3: Run dev + visually confirm**

Run: `pnpm dev` → open `localhost:3000` → see styled button. Stop.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add shadcn/ui base + Button"
```

---

## Chunk 2: Supabase setup, base schema, RLS pattern

### Task 2.1: Install Supabase CLI + init local

**Files:**
- Create: `supabase/config.toml` (auto-generated), `supabase/seed.sql` (empty stub)

- [ ] **Step 1: Install Supabase CLI**

```bash
brew install supabase/tap/supabase || pnpm add -D supabase
```

(Prefer brew; falls back to local devDep.)

- [ ] **Step 2: Init Supabase project**

```bash
supabase init
```

Accept defaults.

- [ ] **Step 3: Start local stack**

```bash
supabase start
```

Expected: Postgres on `localhost:54322`, Studio on `localhost:54323`, API on `localhost:54321`. Note printed `service_role` and `anon` keys.

- [ ] **Step 4: Commit**

```bash
git add supabase/
git commit -m "chore: init Supabase local stack"
```

---

### Task 2.2: Migration 0001 — extensions

**Files:**
- Create: `supabase/migrations/0001_init_extensions.sql`

- [ ] **Step 1: Write migration**

```sql
-- 0001_init_extensions.sql
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;
create extension if not exists pgsodium;   -- column-level encryption
create extension if not exists "pg_trgm";  -- search indexes
```

- [ ] **Step 2: Apply locally**

```bash
supabase db reset
```

Expected: migration applied, no errors. (`db reset` re-runs all migrations on a fresh local DB.)

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0001_init_extensions.sql
git commit -m "feat(db): enable required Postgres extensions"
```

---

### Task 2.3: Migration 0002 — boutiques table

**Files:**
- Create: `supabase/migrations/0002_boutiques.sql`

- [ ] **Step 1: Write migration**

```sql
-- 0002_boutiques.sql
create table public.boutiques (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  gstin text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.boutiques is
  'Top-level tenant entity. v1 has one row; forward-compatible for multi-tenant.';

create index boutiques_slug_idx on public.boutiques (slug);

alter table public.boutiques enable row level security;

-- Service role only for v1 writes; staff read their own boutique (policy added in 0006)
create policy "boutiques_service_role_all"
  on public.boutiques for all
  to service_role using (true) with check (true);
```

- [ ] **Step 2: Apply + verify**

```bash
supabase db reset
psql postgresql://postgres:postgres@localhost:54322/postgres -c "\d public.boutiques"
```

Expected: table exists with all columns.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0002_boutiques.sql
git commit -m "feat(db): boutiques table with RLS enabled"
```

---

### Task 2.4: Migration 0003 — staff_users table

**Files:**
- Create: `supabase/migrations/0003_staff_users.sql`

- [ ] **Step 1: Write migration**

```sql
-- 0003_staff_users.sql
create type public.staff_role as enum ('owner', 'manager', 'staff');

create table public.staff_users (
  id uuid primary key references auth.users (id) on delete cascade,
  boutique_id uuid not null references public.boutiques (id) on delete cascade,
  name text not null,
  role public.staff_role not null default 'staff',
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index staff_users_boutique_idx on public.staff_users (boutique_id);

alter table public.staff_users enable row level security;

create policy "staff_users_self_read"
  on public.staff_users for select
  to authenticated
  using (id = auth.uid());

create policy "staff_users_service_role_all"
  on public.staff_users for all
  to service_role using (true) with check (true);
```

- [ ] **Step 2: Apply + verify**

```bash
supabase db reset
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0003_staff_users.sql
git commit -m "feat(db): staff_users table linked to auth.users"
```

---

### Task 2.5: Migration 0004 — events (append-only)

**Files:**
- Create: `supabase/migrations/0004_events.sql`

- [ ] **Step 1: Write migration**

```sql
-- 0004_events.sql
create table public.events (
  id uuid primary key default gen_random_uuid(),
  boutique_id uuid not null references public.boutiques (id) on delete cascade,
  actor_type text not null check (actor_type in ('staff','customer','system','webhook')),
  actor_id uuid,
  event_name text not null,
  payload_json jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

create index events_boutique_occurred_idx on public.events (boutique_id, occurred_at desc);
create index events_name_idx on public.events (event_name);

-- Append-only: deny update/delete to everyone but service role
alter table public.events enable row level security;

create policy "events_read_own_boutique"
  on public.events for select
  to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);

create policy "events_insert_own_boutique"
  on public.events for insert
  to authenticated
  with check (boutique_id = (current_setting('app.boutique_id', true))::uuid);

create policy "events_service_role_all"
  on public.events for all
  to service_role using (true) with check (true);

-- Explicitly: no update, no delete policies for authenticated → blocked
```

- [ ] **Step 2: Apply**

```bash
supabase db reset
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0004_events.sql
git commit -m "feat(db): events append-only stream with RLS"
```

---

### Task 2.6: Migration 0005 — encrypted settings

**Files:**
- Create: `supabase/migrations/0005_settings.sql`

- [ ] **Step 1: Write migration**

```sql
-- 0005_settings.sql
-- Per-boutique key-value config. Value is encrypted via pgsodium for secret keys.
create table public.settings (
  boutique_id uuid not null references public.boutiques (id) on delete cascade,
  key text not null,
  value_json jsonb,                          -- non-secret config
  value_encrypted bytea,                     -- pgsodium-encrypted secret
  is_secret boolean not null default false,
  updated_by uuid references auth.users (id),
  updated_at timestamptz not null default now(),
  primary key (boutique_id, key),
  check ((is_secret = false and value_json is not null and value_encrypted is null)
      or (is_secret = true  and value_encrypted is not null and value_json is null))
);

comment on column public.settings.value_encrypted is
  'pgsodium-encrypted secret. Use settings.get_secret() / set_secret() functions.';

alter table public.settings enable row level security;

create policy "settings_read_own_boutique"
  on public.settings for select
  to authenticated
  using (boutique_id = (current_setting('app.boutique_id', true))::uuid);

create policy "settings_service_role_all"
  on public.settings for all
  to service_role using (true) with check (true);
```

- [ ] **Step 2: Apply**

```bash
supabase db reset
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0005_settings.sql
git commit -m "feat(db): settings table with encrypted-secret support"
```

---

### Task 2.7: Migration 0006 — RLS helper function

**Files:**
- Create: `supabase/migrations/0006_rls_helpers.sql`

- [ ] **Step 1: Write migration**

```sql
-- 0006_rls_helpers.sql
-- Helper: set the per-request boutique_id GUC from the current user's staff record.
create or replace function public.set_boutique_id_from_user()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  bid uuid;
begin
  select boutique_id into bid from public.staff_users where id = auth.uid() and active = true;
  if bid is null then
    raise exception 'no active staff record for user %', auth.uid();
  end if;
  perform set_config('app.boutique_id', bid::text, true);   -- local to txn
end;
$$;

grant execute on function public.set_boutique_id_from_user() to authenticated;

-- Self-read policy for boutiques (now that we have helper)
create policy "boutiques_read_own"
  on public.boutiques for select
  to authenticated
  using (id = (current_setting('app.boutique_id', true))::uuid);
```

- [ ] **Step 2: Apply**

```bash
supabase db reset
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0006_rls_helpers.sql
git commit -m "feat(db): set_boutique_id_from_user RPC + boutiques read policy"
```

---

### Task 2.8: Migration 0007 — updated_at trigger

**Files:**
- Create: `supabase/migrations/0007_updated_at_trigger.sql`

- [ ] **Step 1: Write migration**

```sql
-- 0007_updated_at_trigger.sql
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger boutiques_updated_at
  before update on public.boutiques
  for each row execute function public.set_updated_at();

create trigger staff_users_updated_at
  before update on public.staff_users
  for each row execute function public.set_updated_at();

create trigger settings_updated_at
  before update on public.settings
  for each row execute function public.set_updated_at();
```

- [ ] **Step 2: Apply**

```bash
supabase db reset
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0007_updated_at_trigger.sql
git commit -m "feat(db): updated_at trigger on mutable tables"
```

---

### Task 2.9: Seed script

**Files:**
- Create: `supabase/seed.sql`

- [ ] **Step 1: Write seed**

```sql
-- supabase/seed.sql
-- Dev-only seed. Creates one boutique. Owner staff_users row is added when first
-- magic-link signup binds via the auth callback (Task 3.4).
insert into public.boutiques (id, name, slug, gstin)
values ('00000000-0000-0000-0000-000000000001', 'Boutique 360 Dev', 'boutique-360-dev', '07AAAAA0000A1Z5')
on conflict (id) do nothing;
```

- [ ] **Step 2: Apply + verify**

```bash
supabase db reset
psql postgresql://postgres:postgres@localhost:54322/postgres -c "select id, name from public.boutiques;"
```

Expected: one row.

- [ ] **Step 3: Commit**

```bash
git add supabase/seed.sql
git commit -m "chore(db): seed dev boutique"
```

---

### Task 2.10: Generate TypeScript types

**Files:**
- Create: `src/lib/supabase/types.ts`
- Modify: `package.json` (script)

- [ ] **Step 1: Add script to package.json**

```json
"db:types": "supabase gen types typescript --local > src/lib/supabase/types.ts",
"db:reset": "supabase db reset",
"db:diff": "supabase db diff --use-migra"
```

- [ ] **Step 2: Generate types**

```bash
mkdir -p src/lib/supabase
pnpm db:types
```

Expected: file `src/lib/supabase/types.ts` contains `export type Database = { ... }`.

- [ ] **Step 3: Commit**

```bash
git add src/lib/supabase/types.ts package.json
git commit -m "feat(db): generated TypeScript types"
```

---

### Task 2.11: Env validation + Supabase client helpers

**Files:**
- Create: `src/lib/env.ts`, `src/lib/supabase/client.ts`, `src/lib/supabase/server.ts`, `src/lib/supabase/service-role.ts`, `src/lib/supabase/context.ts`, `tests/unit/env.test.ts`, `.env.example`

- [ ] **Step 1: Install Supabase SSR + zod**

```bash
pnpm add @supabase/supabase-js @supabase/ssr zod
```

- [ ] **Step 2: Write the failing env test**

`tests/unit/env.test.ts`:

```ts
import { describe, expect, it } from "vitest";

describe("env", () => {
  it("throws on missing required vars", async () => {
    const original = process.env.NEXT_PUBLIC_SUPABASE_URL;
    delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    await expect(import("@/lib/env?bust=" + Date.now())).rejects.toThrow();
    process.env.NEXT_PUBLIC_SUPABASE_URL = original;
  });
});
```

- [ ] **Step 3: Run test (expect fail — file doesn't exist)**

Run: `pnpm test tests/unit/env.test.ts`
Expected: FAIL.

- [ ] **Step 4: Create src/lib/env.ts**

```ts
import { z } from "zod";

const Schema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.string().url(),
  NEXT_PUBLIC_SUPABASE_ANON_KEY: z.string().min(1),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1).optional(), // server-only; optional on client
  SENTRY_DSN: z.string().url().optional(),
  INNGEST_EVENT_KEY: z.string().optional(),
  INNGEST_SIGNING_KEY: z.string().optional(),
  RESEND_API_KEY: z.string().optional(),
  RESEND_FROM_EMAIL: z.string().email().optional(),
  HEALTH_EVENT_STALENESS_SECONDS: z.coerce.number().default(3600), // 1hr
  APP_URL: z.string().url().default("http://localhost:3000"),
});

export const env = Schema.parse({
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
  SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
  SENTRY_DSN: process.env.SENTRY_DSN,
  INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
  INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
  RESEND_API_KEY: process.env.RESEND_API_KEY,
  RESEND_FROM_EMAIL: process.env.RESEND_FROM_EMAIL,
  HEALTH_EVENT_STALENESS_SECONDS: process.env.HEALTH_EVENT_STALENESS_SECONDS,
  APP_URL: process.env.APP_URL,
});
```

- [ ] **Step 5: Re-run test**

Run: `pnpm test tests/unit/env.test.ts`
Expected: PASS.

- [ ] **Step 6: Create Supabase clients**

`src/lib/supabase/client.ts` (browser):

```ts
import { createBrowserClient } from "@supabase/ssr";
import { env } from "@/lib/env";
import type { Database } from "@/lib/supabase/types";

export function getBrowserClient() {
  return createBrowserClient<Database>(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
}
```

`src/lib/supabase/server.ts` (server with cookies):

```ts
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { env } from "@/lib/env";
import type { Database } from "@/lib/supabase/types";

export async function getServerClient() {
  const store = await cookies();
  return createServerClient<Database>(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
    cookies: {
      getAll: () => store.getAll(),
      setAll: (set) => {
        set.forEach(({ name, value, options }) => store.set(name, value, options));
      },
    },
  });
}
```

`src/lib/supabase/service-role.ts` (server only — JOBS/WEBHOOKS):

```ts
import { createClient } from "@supabase/supabase-js";
import { env } from "@/lib/env";
import type { Database } from "@/lib/supabase/types";

let cached: ReturnType<typeof createClient<Database>> | undefined;

export function getServiceRoleClient() {
  if (!env.SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY is required for service-role client");
  }
  cached ??= createClient<Database>(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  return cached;
}
```

`src/lib/supabase/context.ts`:

```ts
import { getServerClient } from "./server";

/** Sets app.boutique_id GUC for the current request, scoped to this txn via RPC. */
export async function setBoutiqueContext() {
  const supabase = await getServerClient();
  const { error } = await supabase.rpc("set_boutique_id_from_user");
  if (error) throw error;
}
```

- [ ] **Step 7: Create .env.example**

```
NEXT_PUBLIC_SUPABASE_URL=http://localhost:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=<from `supabase start` output>
SUPABASE_SERVICE_ROLE_KEY=<from `supabase start` output>

SENTRY_DSN=
INNGEST_EVENT_KEY=
INNGEST_SIGNING_KEY=
RESEND_API_KEY=
RESEND_FROM_EMAIL=hello@boutique.com
HEALTH_EVENT_STALENESS_SECONDS=3600
APP_URL=http://localhost:3000
```

Copy to `.env.local` and fill from `supabase start` output.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(supabase): clients + env validation + context helper"
```

---

### Task 2.12: RLS smoke test against local DB

**Files:**
- Create: `tests/unit/rls.test.ts`

- [ ] **Step 1: Write the failing RLS test**

`tests/unit/rls.test.ts`:

```ts
import { createClient } from "@supabase/supabase-js";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const SUPABASE_URL = "http://localhost:54321";
const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

describe("RLS: events table", () => {
  const anon = createClient(SUPABASE_URL, ANON_KEY);
  const service = createClient(SUPABASE_URL, SERVICE_KEY);

  it("anon cannot read events", async () => {
    const { data, error } = await anon.from("events").select("*").limit(1);
    expect(error).toBeNull(); // RLS returns empty, not error
    expect(data).toEqual([]);
  });

  it("service role can insert events", async () => {
    const { error } = await service.from("events").insert({
      boutique_id: "00000000-0000-0000-0000-000000000001",
      actor_type: "system",
      event_name: "test.ping",
    });
    expect(error).toBeNull();
  });

  it("anon cannot delete events even with valid id", async () => {
    const { data: row } = await service
      .from("events")
      .insert({
        boutique_id: "00000000-0000-0000-0000-000000000001",
        actor_type: "system",
        event_name: "test.delete_attempt",
      })
      .select()
      .single();

    const { error: anonDelErr } = await anon.from("events").delete().eq("id", row!.id);
    // Anon has no delete policy → silently affects 0 rows; verify still present
    const { data: still } = await service.from("events").select("id").eq("id", row!.id).single();
    expect(still).not.toBeNull();
  });
});
```

- [ ] **Step 2: Run test (expect first run to require env file)**

Run: `pnpm test tests/unit/rls.test.ts`

If env missing: copy `.env.example` → `.env.local`, fill in local Supabase keys, prefix run:
`pnpm dlx dotenv-cli -e .env.local -- pnpm test tests/unit/rls.test.ts`

Add to `package.json`:

```json
"test:env": "dotenv -e .env.local -- vitest run"
```

And install: `pnpm add -D dotenv-cli`

Expected: all 3 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test(rls): events table append-only RLS smoke test"
```

---

## Chunk 3: Auth (staff magic-link) + middleware

### Task 3.1: Middleware — Supabase session refresh + admin gate

**Files:**
- Create: `src/middleware.ts`
- Modify: `src/lib/supabase/server.ts` (export middleware helper)

- [ ] **Step 1: Add middleware-specific Supabase helper**

Append to `src/lib/supabase/server.ts`:

```ts
import { createServerClient } from "@supabase/ssr";
import type { NextRequest, NextResponse } from "next/server";

export function getMiddlewareClient(req: NextRequest, res: NextResponse) {
  return createServerClient<Database>(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY, {
    cookies: {
      getAll: () => req.cookies.getAll(),
      setAll: (set) => {
        set.forEach(({ name, value, options }) => {
          req.cookies.set(name, value);
          res.cookies.set(name, value, options);
        });
      },
    },
  });
}
```

- [ ] **Step 2: Write middleware**

`src/middleware.ts`:

```ts
import { NextResponse, type NextRequest } from "next/server";
import { getMiddlewareClient } from "@/lib/supabase/server";

export async function middleware(req: NextRequest) {
  const res = NextResponse.next();
  const supabase = getMiddlewareClient(req, res);
  const { data } = await supabase.auth.getUser();

  const isAdmin = req.nextUrl.pathname.startsWith("/admin");
  const isAuthPage = req.nextUrl.pathname.startsWith("/admin/sign-in");

  if (isAdmin && !isAuthPage && !data.user) {
    const url = req.nextUrl.clone();
    url.pathname = "/admin/sign-in";
    url.searchParams.set("next", req.nextUrl.pathname);
    return NextResponse.redirect(url);
  }

  return res;
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"],
};
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(auth): middleware to gate /admin + refresh session"
```

---

### Task 3.2: Sign-in page (magic-link)

**Files:**
- Create: `src/app/(admin)/admin/sign-in/page.tsx`, `src/app/(admin)/admin/sign-in/actions.ts`

- [ ] **Step 1: Server action**

`src/app/(admin)/admin/sign-in/actions.ts`:

```ts
"use server";
import { z } from "zod";
import { getServerClient } from "@/lib/supabase/server";
import { env } from "@/lib/env";

const Input = z.object({ email: z.string().email() });

export async function sendMagicLink(formData: FormData) {
  const { email } = Input.parse({ email: formData.get("email") });
  const supabase = await getServerClient();
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: { emailRedirectTo: `${env.APP_URL}/api/auth/callback?next=/admin` },
  });
  if (error) return { ok: false, error: error.message };
  return { ok: true };
}
```

- [ ] **Step 2: Page**

`src/app/(admin)/admin/sign-in/page.tsx`:

```tsx
"use client";
import { useState, useTransition } from "react";
import { sendMagicLink } from "./actions";
import { Button } from "@/components/ui/button";

export default function SignInPage() {
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-6 p-6">
      <h1 className="text-2xl font-semibold">Boutique 360 staff sign-in</h1>
      {sent ? (
        <p className="text-sm">Check your email for a sign-in link.</p>
      ) : (
        <form
          action={(fd) =>
            start(async () => {
              const r = await sendMagicLink(fd);
              if (r.ok) setSent(true);
              else setError(r.error ?? "Unknown error");
            })
          }
          className="flex flex-col gap-3"
        >
          <input
            name="email"
            type="email"
            required
            placeholder="you@boutique.com"
            className="rounded border px-3 py-2"
          />
          <Button disabled={pending}>{pending ? "Sending…" : "Send magic link"}</Button>
          {error && <p className="text-sm text-red-600">{error}</p>}
        </form>
      )}
    </main>
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(auth): magic-link sign-in page + server action"
```

---

### Task 3.3: Auth callback route

**Files:**
- Create: `src/app/api/auth/callback/route.ts`

- [ ] **Step 1: Implement callback**

```ts
import { NextResponse, type NextRequest } from "next/server";
import { getServerClient } from "@/lib/supabase/server";

export async function GET(req: NextRequest) {
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const next = url.searchParams.get("next") ?? "/admin";

  if (!code) return NextResponse.redirect(new URL("/admin/sign-in?error=missing_code", req.url));

  const supabase = await getServerClient();
  const { error } = await supabase.auth.exchangeCodeForSession(code);
  if (error) return NextResponse.redirect(new URL(`/admin/sign-in?error=${encodeURIComponent(error.message)}`, req.url));

  return NextResponse.redirect(new URL(next, req.url));
}
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat(auth): code-exchange callback route"
```

---

### Task 3.4: First-login staff_users bootstrap

**Files:**
- Create: `src/lib/auth/ensure-staff.ts`
- Modify: `src/app/api/auth/callback/route.ts` (call ensure-staff)

**Rationale:** First-time owner signs up via magic-link; we need to create their `staff_users` row pointing at the seeded boutique. After v1 single-tenant, subsequent users come via invitation flow (not in this plan).

- [ ] **Step 1: Write the helper**

`src/lib/auth/ensure-staff.ts`:

```ts
import { getServiceRoleClient } from "@/lib/supabase/service-role";

const DEV_BOUTIQUE_ID = "00000000-0000-0000-0000-000000000001";

/**
 * On first login, create a staff_users row for the auth user.
 * Idempotent: no-op if row already exists.
 * In v1 (single tenant), all new staff bind to DEV_BOUTIQUE_ID with role 'owner' for the first user,
 * 'staff' for subsequent. Replace with invitation flow in Plan 2.
 */
export async function ensureStaffRecord(userId: string, email: string) {
  const db = getServiceRoleClient();

  const { data: existing } = await db.from("staff_users").select("id").eq("id", userId).maybeSingle();
  if (existing) return;

  const { count } = await db.from("staff_users").select("*", { count: "exact", head: true });
  const role = (count ?? 0) === 0 ? "owner" : "staff";

  await db.from("staff_users").insert({
    id: userId,
    boutique_id: DEV_BOUTIQUE_ID,
    name: email.split("@")[0] ?? "Staff",
    role,
  });
}
```

- [ ] **Step 2: Wire into callback**

In `src/app/api/auth/callback/route.ts`, after `exchangeCodeForSession`:

```ts
const { data: userData } = await supabase.auth.getUser();
if (userData.user) {
  const { ensureStaffRecord } = await import("@/lib/auth/ensure-staff");
  await ensureStaffRecord(userData.user.id, userData.user.email!);
}
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(auth): bootstrap staff_users record on first sign-in"
```

---

### Task 3.5: Admin layout + sign-out

**Files:**
- Create: `src/app/(admin)/admin/layout.tsx`, `src/app/(admin)/admin/page.tsx`, `src/app/(admin)/admin/sign-out/route.ts`

- [ ] **Step 1: Sign-out route**

```ts
// src/app/(admin)/admin/sign-out/route.ts
import { NextResponse } from "next/server";
import { getServerClient } from "@/lib/supabase/server";
import { env } from "@/lib/env";

export async function POST() {
  const supabase = await getServerClient();
  await supabase.auth.signOut();
  return NextResponse.redirect(new URL("/admin/sign-in", env.APP_URL));
}
```

- [ ] **Step 2: Layout with header + boutique-context call**

```tsx
// src/app/(admin)/admin/layout.tsx
import { redirect } from "next/navigation";
import { getServerClient } from "@/lib/supabase/server";
import { setBoutiqueContext } from "@/lib/supabase/context";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const supabase = await getServerClient();
  const { data } = await supabase.auth.getUser();
  if (!data.user) redirect("/admin/sign-in");

  try {
    await setBoutiqueContext();
  } catch {
    redirect("/admin/sign-in?error=no_staff_record");
  }

  return (
    <div className="flex min-h-screen flex-col">
      <header className="flex items-center justify-between border-b px-6 py-3">
        <span className="font-semibold">Boutique 360 admin</span>
        <form action="/admin/sign-out" method="post">
          <button className="text-sm underline">Sign out</button>
        </form>
      </header>
      <main className="flex-1 p-6">{children}</main>
    </div>
  );
}
```

- [ ] **Step 3: Stub dashboard**

```tsx
// src/app/(admin)/admin/page.tsx
export default function AdminDashboardPage() {
  return <h1 className="text-2xl font-semibold">Dashboard (coming in Plan 2)</h1>;
}
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(admin): layout, dashboard stub, sign-out"
```

---

### Task 3.6: E2E test — sign-in redirect flow

**Files:**
- Create: `tests/e2e/auth.spec.ts`

- [ ] **Step 1: Write the failing e2e test**

```ts
import { expect, test } from "@playwright/test";

test("unauthed /admin redirects to /admin/sign-in", async ({ page }) => {
  await page.goto("/admin");
  await expect(page).toHaveURL(/\/admin\/sign-in/);
  await expect(page.getByRole("heading", { name: /staff sign-in/i })).toBeVisible();
});

test("sign-in form submits and shows success state", async ({ page }) => {
  await page.goto("/admin/sign-in");
  await page.getByPlaceholder(/you@boutique.com/i).fill("dev@example.com");
  await page.getByRole("button", { name: /send magic link/i }).click();
  await expect(page.getByText(/check your email/i)).toBeVisible();
});
```

- [ ] **Step 2: Run**

Run: `pnpm test:e2e tests/e2e/auth.spec.ts`
Expected: both pass (local Supabase accepts any email for magic-link in dev, returns success without delivery).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test(e2e): admin sign-in redirect + magic-link form"
```

---

## Chunk 4: Integrations wiring (Sentry, Inngest, Resend, settings, events)

### Task 4.1: Events emit helper + test

**Files:**
- Create: `src/lib/events/emit.ts`, `tests/unit/events.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/unit/events.test.ts
import { describe, expect, it } from "vitest";
import { emitEvent } from "@/lib/events/emit";
import { getServiceRoleClient } from "@/lib/supabase/service-role";

describe("emitEvent", () => {
  it("appends a row to events", async () => {
    const before = await getServiceRoleClient().from("events").select("*", { count: "exact", head: true });
    await emitEvent({
      boutiqueId: "00000000-0000-0000-0000-000000000001",
      actorType: "system",
      eventName: "test.emit",
      payload: { foo: "bar" },
    });
    const after = await getServiceRoleClient().from("events").select("*", { count: "exact", head: true });
    expect((after.count ?? 0) - (before.count ?? 0)).toBe(1);
  });
});
```

- [ ] **Step 2: Run (expect FAIL — file missing)**

```bash
pnpm test:env tests/unit/events.test.ts
```

- [ ] **Step 3: Implement**

```ts
// src/lib/events/emit.ts
import { getServiceRoleClient } from "@/lib/supabase/service-role";

export type EventInput = {
  boutiqueId: string;
  actorType: "staff" | "customer" | "system" | "webhook";
  actorId?: string;
  eventName: string;
  payload?: Record<string, unknown>;
};

export async function emitEvent(input: EventInput) {
  const db = getServiceRoleClient();
  const { error } = await db.from("events").insert({
    boutique_id: input.boutiqueId,
    actor_type: input.actorType,
    actor_id: input.actorId ?? null,
    event_name: input.eventName,
    payload_json: input.payload ?? {},
  });
  if (error) throw error;
}
```

- [ ] **Step 4: Re-run test**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(events): emitEvent helper with append-only contract"
```

---

### Task 4.2: Settings get/set helpers (non-secret first)

**Files:**
- Create: `src/lib/settings/get.ts`, `src/lib/settings/set.ts`, `tests/unit/settings.test.ts`

- [ ] **Step 1: Create the index re-export first (so the test's import target exists, then fails at "function not implemented")**

`src/lib/settings/index.ts`:

```ts
export { getSetting } from "./get";
export { setSetting } from "./set";
```

Create stubs so the imports resolve:

```ts
// src/lib/settings/get.ts
export async function getSetting<T>(_boutiqueId: string, _key: string): Promise<T | null> {
  throw new Error("not implemented");
}

// src/lib/settings/set.ts
export async function setSetting(_boutiqueId: string, _key: string, _value: unknown): Promise<void> {
  throw new Error("not implemented");
}
```

- [ ] **Step 2: Write the failing test (non-secret only)**

```ts
// tests/unit/settings.test.ts
import { describe, expect, it } from "vitest";
import { getSetting, setSetting } from "@/lib/settings";

const BID = "00000000-0000-0000-0000-000000000001";

describe("settings (non-secret)", () => {
  it("round-trips a JSON value", async () => {
    await setSetting(BID, "brand_color", { hex: "#a83232" });
    const v = await getSetting<{ hex: string }>(BID, "brand_color");
    expect(v).toEqual({ hex: "#a83232" });
  });

  it("returns null for missing key", async () => {
    const v = await getSetting(BID, "nope_" + Date.now());
    expect(v).toBeNull();
  });
});
```

- [ ] **Step 3: Run test (FAIL — "not implemented")**

```bash
pnpm test:env tests/unit/settings.test.ts
```

- [ ] **Step 4: Implement get**

```ts
// src/lib/settings/get.ts
import { getServiceRoleClient } from "@/lib/supabase/service-role";

export async function getSetting<T>(boutiqueId: string, key: string): Promise<T | null> {
  const db = getServiceRoleClient();
  const { data, error } = await db
    .from("settings")
    .select("value_json, is_secret")
    .eq("boutique_id", boutiqueId)
    .eq("key", key)
    .maybeSingle();
  if (error) throw error;
  if (!data) return null;
  if (data.is_secret) throw new Error(`Setting ${key} is secret; use getSecret()`);
  return (data.value_json as T) ?? null;
}
```

- [ ] **Step 5: Implement set**

```ts
// src/lib/settings/set.ts
import { getServiceRoleClient } from "@/lib/supabase/service-role";

export async function setSetting(boutiqueId: string, key: string, value: unknown) {
  const db = getServiceRoleClient();
  const { error } = await db.from("settings").upsert(
    {
      boutique_id: boutiqueId,
      key,
      value_json: value as never,
      value_encrypted: null,
      is_secret: false,
    },
    { onConflict: "boutique_id,key" },
  );
  if (error) throw error;
}
```

- [ ] **Step 6: Re-run**

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(settings): non-secret get/set helpers"
```

**Note:** Secret get/set via pgsodium is deferred to Plan 5 (Commerce / first integration that needs Razorpay secrets). For now, secrets stay in Vercel env vars. This avoids scaffolding pgsodium wrappers nobody calls yet.

---

### Task 4.3: Sentry wiring

**Files:**
- Create: `src/sentry.server.config.ts`, `src/sentry.client.config.ts`, `src/sentry.edge.config.ts`
- Modify: `next.config.mjs`, `package.json`

- [ ] **Step 1: Install + run wizard**

```bash
pnpm dlx @sentry/wizard@latest -i nextjs
```

Wizard prompts: select Next.js, paste DSN (use `https://example@sentry.io/0` placeholder for now; replace in env), accept defaults.

- [ ] **Step 2: Move generated configs into src/**

The wizard creates files at repo root. Move:

```bash
git mv sentry.server.config.ts src/sentry.server.config.ts || true
git mv sentry.client.config.ts src/sentry.client.config.ts || true
git mv sentry.edge.config.ts   src/sentry.edge.config.ts   || true
```

Adjust `next.config.mjs` wrapper paths if needed.

- [ ] **Step 3: Replace DSN reads with env**

In each `sentry.*.config.ts`, replace hardcoded DSN with:

```ts
import { env } from "@/lib/env";
dsn: env.SENTRY_DSN,
```

And gate init:

```ts
if (!env.SENTRY_DSN) {
  // no-op in dev/local
} else {
  Sentry.init({ dsn: env.SENTRY_DSN, tracesSampleRate: 0.1 });
}
```

- [ ] **Step 4: Verify build**

```bash
pnpm build
```

Expected: succeeds (warnings OK).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(sentry): wire SDK gated on SENTRY_DSN env"
```

---

### Task 4.4: Inngest client + sample function

**Files:**
- Create: `src/lib/inngest/client.ts`, `src/lib/inngest/functions/ping.ts`, `src/app/api/inngest/route.ts`
- Modify: `package.json`

- [ ] **Step 1: Install**

```bash
pnpm add inngest
```

- [ ] **Step 2: Client**

```ts
// src/lib/inngest/client.ts
import { Inngest } from "inngest";
import { env } from "@/lib/env";

export const inngest = new Inngest({
  id: "boutique-360",
  eventKey: env.INNGEST_EVENT_KEY,
  signingKey: env.INNGEST_SIGNING_KEY,
});
```

- [ ] **Step 3: Sample function**

```ts
// src/lib/inngest/functions/ping.ts
import { inngest } from "../client";
import { emitEvent } from "@/lib/events/emit";

export const ping = inngest.createFunction(
  { id: "ping" },
  { event: "system/ping" },
  async ({ event }) => {
    await emitEvent({
      boutiqueId: (event.data as { boutiqueId: string }).boutiqueId,
      actorType: "system",
      eventName: "system.ping.handled",
      payload: { ts: Date.now() },
    });
    return { ok: true };
  },
);
```

- [ ] **Step 4: Route handler**

```ts
// src/app/api/inngest/route.ts
import { serve } from "inngest/next";
import { inngest } from "@/lib/inngest/client";
import { ping } from "@/lib/inngest/functions/ping";

export const { GET, POST, PUT } = serve({ client: inngest, functions: [ping] });
```

- [ ] **Step 5: Add dev script**

In `package.json`:

```json
"inngest:dev": "pnpm dlx inngest-cli@latest dev -u http://localhost:3000/api/inngest"
```

- [ ] **Step 6: Smoke test**

In one terminal: `pnpm dev`. In another: `pnpm inngest:dev`. Open Inngest dashboard at the printed URL, manually fire `system/ping` event with `{ "boutiqueId": "00000000-0000-0000-0000-000000000001" }`. Verify: function runs, new `events` row appears.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(inngest): client + ping function + serve endpoint"
```

---

### Task 4.5: Resend wrapper + base email

**Files:**
- Create: `src/lib/resend/client.ts`, `src/lib/resend/emails/base.tsx`

- [ ] **Step 1: Install**

```bash
pnpm add resend @react-email/components
```

- [ ] **Step 2: Client**

```ts
// src/lib/resend/client.ts
import { Resend } from "resend";
import { env } from "@/lib/env";

let cached: Resend | undefined;
export function getResend() {
  if (!env.RESEND_API_KEY) throw new Error("RESEND_API_KEY not set");
  cached ??= new Resend(env.RESEND_API_KEY);
  return cached;
}

export async function sendEmail(opts: { to: string; subject: string; react: React.ReactNode }) {
  const from = env.RESEND_FROM_EMAIL;
  if (!from) throw new Error("RESEND_FROM_EMAIL not set");
  return getResend().emails.send({ from, ...opts });
}
```

- [ ] **Step 3: Base email layout**

```tsx
// src/lib/resend/emails/base.tsx
import { Html, Head, Body, Container, Text } from "@react-email/components";

export function BaseEmail({ children }: { children: React.ReactNode }) {
  return (
    <Html>
      <Head />
      <Body style={{ fontFamily: "system-ui, sans-serif", margin: 0, padding: 24 }}>
        <Container style={{ maxWidth: 560 }}>
          {children}
          <Text style={{ marginTop: 32, color: "#888", fontSize: 12 }}>Sent by Boutique 360</Text>
        </Container>
      </Body>
    </Html>
  );
}
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(resend): client wrapper + base email layout"
```

---

## Chunk 5: Health endpoint, CI/CD, deployment

### Task 5.1: /api/health endpoint with TDD

**Files:**
- Create: `src/app/api/health/route.ts`, `tests/unit/health.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
// tests/unit/health.test.ts
import { describe, expect, it } from "vitest";
import { GET } from "@/app/api/health/route";

describe("/api/health", () => {
  it("returns ok with all required check keys", async () => {
    const res = await GET();
    const body = (await res.json()) as { status: string; checks: Record<string, unknown> };
    expect([200, 503]).toContain(res.status); // 503 acceptable if optional integrations unset locally
    expect(body.checks).toHaveProperty("db");
    expect(body.checks).toHaveProperty("events_recent");
    expect(body.checks).toHaveProperty("storage");
    expect(body.checks).toHaveProperty("inngest");
  });

  it("db check is ok when local Supabase reachable", async () => {
    const res = await GET();
    const body = (await res.json()) as { checks: Record<string, string> };
    expect(body.checks.db).toBe("ok");
  });
});
```

- [ ] **Step 2: Run (FAIL)**

```bash
pnpm test:env tests/unit/health.test.ts
```

- [ ] **Step 3: Implement**

Per spec §7 (Observability), `/api/health` checks: DB conn, Storage reachable, Inngest reachable, last events timestamp.

```ts
// src/app/api/health/route.ts
import { NextResponse } from "next/server";
import { getServiceRoleClient } from "@/lib/supabase/service-role";
import { env } from "@/lib/env";

export const dynamic = "force-dynamic";

type CheckResult = "ok" | "degraded" | "fail";

async function checkDb(): Promise<CheckResult> {
  try {
    const { error } = await getServiceRoleClient().from("boutiques").select("id").limit(1);
    return error ? "fail" : "ok";
  } catch {
    return "fail";
  }
}

async function checkStorage(): Promise<CheckResult> {
  try {
    const { error } = await getServiceRoleClient().storage.listBuckets();
    return error ? "fail" : "ok";
  } catch {
    return "fail";
  }
}

async function checkEventsRecent(): Promise<CheckResult> {
  try {
    const { data } = await getServiceRoleClient()
      .from("events")
      .select("occurred_at")
      .order("occurred_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (!data) return "degraded"; // empty in fresh DB is acceptable
    const ageSec = (Date.now() - new Date(data.occurred_at).getTime()) / 1000;
    return ageSec < env.HEALTH_EVENT_STALENESS_SECONDS ? "ok" : "degraded";
  } catch {
    return "fail";
  }
}

async function checkInngest(): Promise<CheckResult> {
  // In production we have signing/event keys; in local dev neither is set and Inngest
  // dev server runs separately. Probe the local /api/inngest route or the cloud event URL.
  if (!env.INNGEST_EVENT_KEY) return "degraded"; // unconfigured = degraded, not fail
  try {
    const res = await fetch("https://api.inngest.com/v1/health", { signal: AbortSignal.timeout(2000) });
    return res.ok ? "ok" : "fail";
  } catch {
    return "fail";
  }
}

export async function GET() {
  const [db, storage, events_recent, inngest] = await Promise.all([
    checkDb(),
    checkStorage(),
    checkEventsRecent(),
    checkInngest(),
  ]);
  const checks = { db, storage, events_recent, inngest };

  // Overall: ok only if no 'fail'. 'degraded' is acceptable (returns 200 with status='degraded').
  const hasFail = Object.values(checks).includes("fail");
  const hasDegraded = Object.values(checks).includes("degraded");
  const overall: "ok" | "degraded" | "fail" = hasFail ? "fail" : hasDegraded ? "degraded" : "ok";

  return NextResponse.json({ status: overall, checks }, { status: hasFail ? 503 : 200 });
}
```

- [ ] **Step 4: Re-run**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(health): /api/health with db + event-staleness checks"
```

---

### Task 5.2: GitHub Actions CI

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write workflow**

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  verify:
    runs-on: ubuntu-latest
    services:
      postgres: { image: postgres:15, env: { POSTGRES_PASSWORD: postgres }, ports: ["54322:5432"], options: --health-cmd="pg_isready -U postgres" --health-interval=5s --health-timeout=5s --health-retries=10 }
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9.12.0 }
      - uses: actions/setup-node@v4
        with: { node-version-file: ".nvmrc", cache: "pnpm" }
      - run: pnpm install --frozen-lockfile

      - name: Install Supabase CLI
        uses: supabase/setup-cli@v1
        with: { version: latest }

      - name: Start Supabase (local stack)
        run: supabase start
      - name: Capture Supabase env
        run: |
          echo "NEXT_PUBLIC_SUPABASE_URL=$(supabase status -o env | grep API_URL | cut -d= -f2)" >> $GITHUB_ENV
          echo "NEXT_PUBLIC_SUPABASE_ANON_KEY=$(supabase status -o env | grep ANON_KEY | cut -d= -f2)" >> $GITHUB_ENV
          echo "SUPABASE_SERVICE_ROLE_KEY=$(supabase status -o env | grep SERVICE_ROLE_KEY | cut -d= -f2)" >> $GITHUB_ENV
          echo "APP_URL=http://localhost:3000" >> $GITHUB_ENV

      - run: pnpm lint
      - run: pnpm test
      - run: pnpm build

      - name: Migration dry-run (fails on schema drift between migrations/ and live DB)
        run: |
          diff_output=$(supabase db diff --schema public)
          if [ -n "$diff_output" ]; then
            echo "::error::Schema drift detected — migrations don't match expected schema"
            echo "$diff_output"
            exit 1
          fi
          echo "✅ No schema drift"

      - run: pnpm dlx playwright install --with-deps chromium
      - run: pnpm test:e2e
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: GitHub Actions with Supabase local + e2e"
```

- [ ] **Step 3: Verify by pushing a throwaway PR**

```bash
git checkout -b ci-smoke
git commit --allow-empty -m "chore: trigger CI"
git push -u origin ci-smoke
gh pr create --fill
```

Expected: CI workflow runs green within ~5min. Address any failures here (likely env-var or Supabase CLI setup issues) before moving on. Close the PR when done; the workflow file is what we wanted to verify.

---

### Task 5.3: Bundle-size budget

**Files:**
- Modify: `next.config.mjs`, `package.json`, `.github/workflows/ci.yml`

- [ ] **Step 1: Install**

```bash
pnpm add -D @next/bundle-analyzer
```

- [ ] **Step 2: Update next.config.mjs (full file — composes with Sentry wrapper)**

The Sentry wizard in Chunk 4 wraps the config with `withSentryConfig`. Bundle analyzer must wrap **the user config**, then Sentry wraps the **result**. Order matters.

Replace `next.config.mjs` with:

```js
import { withSentryConfig } from "@sentry/nextjs";
import bundleAnalyzer from "@next/bundle-analyzer";

const withBundleAnalyzer = bundleAnalyzer({ enabled: process.env.ANALYZE === "true" });

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  experimental: { typedRoutes: true },
  images: { remotePatterns: [{ protocol: "https", hostname: "**.supabase.co" }] },
};

// Bundle analyzer wraps user config first
const wrappedConfig = withBundleAnalyzer(nextConfig);

// Sentry wraps the result
export default withSentryConfig(wrappedConfig, {
  silent: true,
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  widenClientFileUpload: true,
  hideSourceMaps: true,
  disableLogger: true,
});
```

(If the Sentry wizard generated additional options in Chunk 4 Task 4.3, merge them into the second arg of `withSentryConfig` here.)

- [ ] **Step 3: Discover the manifest key (one-time probe)**

Next 15's `app-build-manifest.json` key for the home route can be `"/"` or `"/page"` depending on minor version. Probe once:

```bash
pnpm build
node -e "console.log(Object.keys(JSON.parse(require('fs').readFileSync('.next/app-build-manifest.json','utf8')).pages))"
```

Note the key matching home (e.g. `/page` or `/`). Use whichever appears.

- [ ] **Step 4: Add a public-route size guard (script, key-tolerant)**

`scripts/check-bundle-size.mjs`:

```js
import fs from "node:fs";
import path from "node:path";

const STORE_LIMIT_KB = 250;
const manifestPath = ".next/app-build-manifest.json";

if (!fs.existsSync(manifestPath)) {
  console.error(`Missing ${manifestPath}. Run 'pnpm build' first.`);
  process.exit(1);
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const pages = manifest.pages ?? {};

// Tolerant lookup: Next 15 may key home as "/page" or "/" depending on version.
const homeKey = ["/page", "/", "/(public)/page"].find((k) => pages[k]);
if (!homeKey) {
  console.error(`Could not find home route in manifest. Available keys:`, Object.keys(pages));
  process.exit(1);
}

const files = pages[homeKey];
const totalBytes = files.reduce((acc, f) => acc + fs.statSync(path.join(".next", f)).size, 0);
const totalKb = totalBytes / 1024;
console.log(`Storefront ${homeKey} bundle: ${totalKb.toFixed(1)} KB (limit ${STORE_LIMIT_KB})`);

if (totalKb > STORE_LIMIT_KB) {
  console.error(`Exceeds ${STORE_LIMIT_KB} KB budget`);
  process.exit(1);
}
```

- [ ] **Step 5: Add to CI**

In `ci.yml` after `pnpm build`:

```yaml
      - run: node scripts/check-bundle-size.mjs
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "ci: enforce 250 KB bundle budget on storefront /"
```

---

### Task 5.4: README + onboarding doc

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Write README**

````markdown
# Boutique 360

Commercial-grade Boutique CRM + AI Try-On + Public Website.
Spec: `docs/superpowers/specs/2026-05-25-boutique-360-design.md`

## Prerequisites
- Node 20 (via nvm: `nvm use`)
- pnpm 9 (via corepack)
- Docker (for local Supabase)
- Supabase CLI (`brew install supabase/tap/supabase`)

## Setup
```bash
nvm use
corepack enable
pnpm install
supabase start              # prints local keys
cp .env.example .env.local  # fill SUPABASE keys from `supabase start`
pnpm db:reset               # runs migrations + seed
pnpm dev
```

## Common commands
- `pnpm dev` — Next.js dev server
- `pnpm inngest:dev` — Inngest dev runtime (separate terminal)
- `pnpm test` — unit tests (Vitest)
- `pnpm test:env` — unit tests requiring `.env.local`
- `pnpm test:e2e` — Playwright e2e
- `pnpm db:reset` — drop & re-apply all migrations + seed
- `pnpm db:types` — regenerate TypeScript types from current schema
- `pnpm lint` / `pnpm format` — code quality

## Architecture overview
See spec § 3-7. Highlights:
- Next.js 15 App Router, route groups `(public)` and `(admin)`
- Supabase (Postgres + Auth + Storage + Realtime) with RLS scoped by `boutique_id`
- Inngest for background jobs and webhooks
- Sentry, Resend, Vercel deployment

## Next plans
Foundation (this plan) → Plan 2: CRM Core + Loyalty → Plan 3: Catalog → …
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README with setup + command reference"
```

---

### Task 5.5: Deploy to Vercel staging

**Files:**
- Create: `vercel.json` (optional, for build env hints)

- [ ] **Step 1: Use Vercel CLI via dlx (no global install)**

```bash
pnpm dlx vercel@latest --version
```

- [ ] **Step 2: Manual — create staging Supabase project + Vercel environment**

a. In Supabase dashboard: create a new project named `boutique-360-staging`. Copy its URL + anon + service-role keys.

b. In Vercel dashboard for this project → **Settings → Environments**: create a custom environment named `staging` (Vercel Pro plan supports custom environments; on Hobby plan, use the built-in `preview` with a branch alias instead).

c. In **Settings → Environment Variables**: add for `staging`:
   - `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (from step a)
   - `SENTRY_DSN`, `SENTRY_ORG`, `SENTRY_PROJECT`
   - `INNGEST_EVENT_KEY`, `INNGEST_SIGNING_KEY` (from Inngest dashboard, create staging app)
   - `RESEND_API_KEY`, `RESEND_FROM_EMAIL`
   - `APP_URL=https://staging-boutique-360.vercel.app` (or your chosen staging domain)
   - `HEALTH_EVENT_STALENESS_SECONDS=3600`

- [ ] **Step 3: Link + deploy preview**

```bash
pnpm dlx vercel@latest link
pnpm dlx vercel@latest env pull .env.vercel.local
pnpm dlx vercel@latest deploy
```

The deploy command returns a preview URL. Verify it loads.

- [ ] **Step 4: Promote to staging environment**

If you created a custom `staging` environment in Step 2b:

```bash
pnpm dlx vercel@latest deploy --target=staging
```

Otherwise (Hobby plan fallback), use a `staging` branch and let preview deploys handle it:

```bash
git checkout -b staging
git push -u origin staging
# Vercel auto-deploys; add a domain alias in Vercel dashboard: staging.<domain> → staging branch
```

Verify: visit the printed URL or alias → see Boutique 360 placeholder. Visit `/admin` → redirected to sign-in. Visit `/api/health` → returns JSON with `status: "ok"` (or `"degraded"` if Inngest/staleness checks aren't fully wired yet — both are acceptable, only `"fail"` is a blocker).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore(deploy): initial Vercel staging deploy"
```

---

### Task 5.6: Better Stack uptime monitor (manual)

**Files:**
- Modify: `README.md` (add monitoring section)

- [ ] **Step 1: Manual setup**

1. Create Better Stack account, add monitor for `https://staging.<your-domain>/api/health`.
2. Set check interval: 1 minute.
3. Expect `status: ok` in JSON; alert on non-200.
4. Configure Slack / email alert routing.

- [ ] **Step 2: Document in README**

Append to `README.md`:

```markdown
## Observability
- **Errors:** Sentry (project: boutique-360)
- **Uptime:** Better Stack monitor on `/api/health` (1min interval)
- **Logs:** Vercel runtime logs + Supabase logs; aggregate to Axiom (planned in Plan 8)
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: monitoring section"
```

---

### Task 5.7: Verification checklist + handoff

- [ ] All migrations apply cleanly: `pnpm db:reset` returns no errors
- [ ] `pnpm test` passes: env, settings, events, rls, health tests
- [ ] `pnpm test:e2e` passes: smoke + auth redirect
- [ ] `pnpm build` succeeds with no type errors
- [ ] `pnpm lint` clean
- [ ] CI workflow runs end-to-end green on a throwaway PR
- [ ] Local sign-in flow: enter email → check Supabase Inbucket (`localhost:54324`) → click link → land on `/admin` → see dashboard stub
- [ ] `staff_users` row was created for first sign-in with role `owner`
- [ ] `/api/health` returns `status: "ok"` or `"degraded"` locally (degraded is OK if Inngest keys unset)
- [ ] Vercel staging deploys; sign-in works against staging Supabase

When all boxes are checked: **Foundation is done. Open PR, merge to main, and Plan 2 (CRM Core + Loyalty) can begin.**

---

## Notes for the implementing engineer

- **Trust the tests.** Run `pnpm test` after every step. Don't batch tasks.
- **Commit per task, not per chunk.** Granular commits = easier review and rollback.
- **If Supabase CLI fails:** delete `supabase/.branches/` and re-run `supabase start`. Docker leftovers are the usual culprit.
- **If you find a step is wrong or missing context:** stop and surface it. Don't improvise — the spec is intentionally tight.
- **RLS gotcha:** the `current_setting('app.boutique_id', true)` returns `''` (empty string) when unset, which fails the uuid cast. The `setBoutiqueContext()` call in `AdminLayout` is what makes admin queries work — never query authenticated tables without calling it first.
- **Magic-link in local dev:** Supabase serves a fake SMTP at `localhost:54324` (Inbucket). Visit it to retrieve the link.
