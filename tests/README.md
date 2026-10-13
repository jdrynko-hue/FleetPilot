Mock backend tests run against the current TypeScript source using Node.js 24. Tests do not contact Stripe or Supabase and do not charge any card.

Compile and test from the repository root:

```sh
node --experimental-strip-types --test tests/checkout.test.mjs tests/billing-manage.test.mjs
```

The full-regression workflow runs these tests alongside Flutter analysis and tests. The legacy compiled helper is not used by the suite.
