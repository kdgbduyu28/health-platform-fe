import { describe, expect, it } from 'vitest';

import { demoLogins, demoLoginsFor } from '../src/config/demo_logins';
import { appRoles } from '../src/models/app_role';

describe('demoLoginsFor', () => {
  it('gives every app at least one account, and only its own', () => {
    for (const app of appRoles) {
      const logins = demoLoginsFor(app);
      expect(logins.length).toBeGreaterThan(0);
      expect(logins.every((d) => d.app === app)).toBe(true);
    }
  });

  it('offers the two admins in the admin app', () => {
    expect(demoLoginsFor('admin').map((d) => d.email)).toEqual(['admin@clinic.ph', 'admin@brightsmile.ph']);
  });

  it('lists each account once', () => {
    expect(new Set(demoLogins.map((d) => d.email)).size).toBe(demoLogins.length);
  });
});
