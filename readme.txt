Clinic platform front end: four web apps (patient, doctor, assistant,
admin) built with React Native for Web and Expo Router, sharing one package.

  apps/patient, apps/doctor, apps/assistant, apps/admin
      each app's routes (app/) and its own screens (src/)
  packages/shared
      everything the apps share: models, data access, screens, widgets


Set up once:

npm install


Run an app locally (opens in the browser):

npm run web:patient
npm run web:doctor
npm run web:assistant
npm run web:admin


Check the code:

npm run typecheck
npm test


Build and deploy all four apps to Cloudflare Pages:

./scripts/release.sh

Subset, clean first, or build without deploying:

./scripts/release.sh patient doctor
./scripts/release.sh --clean
./scripts/release.sh --no-deploy      (or: npm run build:web)

Each build lands in apps/<app>/dist.


Configuration is read at build time from EXPO_PUBLIC_* variables; without
them the defaults in packages/shared/src/config/supabase_config.ts apply:

EXPO_PUBLIC_SUPABASE_URL, EXPO_PUBLIC_SUPABASE_KEY,
EXPO_PUBLIC_VAPID_PUBLIC_KEY, EXPO_PUBLIC_TURNSTILE_SITE_KEY ("off" turns
the sign-in check off), EXPO_PUBLIC_LEGAL_OPERATOR, EXPO_PUBLIC_LEGAL_EMAIL
