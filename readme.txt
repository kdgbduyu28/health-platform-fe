Build web for all four apps:

./scripts/release.sh --web

(or: melos run build:web)

Subset, and clean first:

./scripts/release.sh --web patient doctor
./scripts/release.sh --web --clean


Build specific app:

Patient:

flutter build web --project-dir apps/patient_app

Doctor:

flutter build web --project-dir apps/doctor_app

Assistant:

flutter build web --project-dir apps/assistant_app

Admin web:

flutter build web --project-dir apps/admin_app


