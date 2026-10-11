Mock backend tests were run using TypeScript (`tsc`) and Node.js. Tests do not contact Stripe or Supabase and do not charge any card.

Compile and test from the repository root:

```sh
tsc --target es2022 --lib es2022,dom --skipLibCheck --outDir /tmp/flotaryx-tests tests/deno-test-globals.d.ts supabase/functions/flotaryx-billing-manage/index.ts
cp /tmp/flotaryx-tests/index.js tests/billing-manage.compiled.mjs
node tests/billing-manage.test.mjs
```

The packaged compiled test helper is included for a quick smoke test, but recompiling is recommended after code changes.
