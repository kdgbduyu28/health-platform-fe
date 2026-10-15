import { defineConfig } from 'vitest/config';

// The logic tests: models, parsing, routing decisions, calendar maths.
// They import modules directly (not the package barrel), so none of them
// pulls in React Native.
export default defineConfig({
  test: {
    include: ['packages/shared/test/**/*.test.ts'],
    environment: 'node',
    globals: true,
    // Dates in the tests are local; pin the zone so they mean the same
    // everywhere (the clinics are in Manila).
    env: { TZ: 'Asia/Manila' },
  },
});
