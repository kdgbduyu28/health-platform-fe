#!/usr/bin/env bash
#
# Build the workspace apps for the web and deploy them to Cloudflare Pages.
#
#   ./scripts/release.sh                         # build + deploy all four apps
#   ./scripts/release.sh patient doctor          # just those two
#   ./scripts/release.sh --clean                 # flutter clean first
#   ./scripts/release.sh --no-deploy             # build only, print the folders
#
# Each app goes to its own Pages project, served at <project>.pages.dev.
# Deploys are production deploys whatever git branch you are on, and a dirty
# working tree is allowed: what ships is what is on disk.

set -euo pipefail

# Workspace order matches pubspec.yaml.
APPS=(patient doctor assistant admin)

# Cloudflare Pages project per app; each is served at <project>.pages.dev.
# A case, not an associative array: macOS ships bash 3.2.
pages_project() {
  case "$1" in
    patient)   echo rowphpatient ;;
    doctor)    echo rowphdoctor ;;
    assistant) echo rowphassistant ;;
    admin)     echo rowphadmin ;;
  esac
}

# Pinned to a major so a new wrangler cannot change the deploy under us.
WRANGLER=(npx --yes wrangler@4)

# Without this, wrangler can stop to ask about usage metrics and the run
# hangs with no visible prompt. Stdin is closed on every call for the same
# reason.
export WRANGLER_SEND_METRICS=false

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CLEAN=false
DEPLOY=true
SELECTED=()

usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh [app...] [--clean] [--no-deploy]

Builds each selected app for the web, then deploys it to Cloudflare Pages.

Options:
  --clean          flutter clean in each app before building
  --no-deploy      build only; print the build folders instead of deploying
  --web            accepted for compatibility (web is the only target)
  -h, --help       show this message

Apps (default: all): patient, doctor, assistant, admin
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --web)       shift ;;
    --clean)     CLEAN=true; shift ;;
    --deploy)    DEPLOY=true; shift ;;
    --no-deploy) DEPLOY=false; shift ;;
    -h|--help)   usage; exit 0 ;;
    -*)
      echo "release.sh: unknown option '$1'" >&2
      usage >&2
      exit 2
      ;;
    *)
      # A bare word is an app name; validate it against the known set.
      matched=false
      for app in "${APPS[@]}"; do
        [[ "$1" == "$app" ]] && matched=true && break
      done
      if [[ "$matched" == false ]]; then
        echo "release.sh: unknown app '$1' (expected one of: ${APPS[*]})" >&2
        exit 2
      fi
      SELECTED+=("$1")
      shift
      ;;
  esac
done

if [[ ${#SELECTED[@]} -eq 0 ]]; then
  SELECTED=("${APPS[@]}")
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "release.sh: flutter is not on PATH" >&2
  exit 1
fi

# Check the Cloudflare login before spending minutes on builds that could not
# be shipped anyway.
if [[ "$DEPLOY" == true ]]; then
  if ! command -v npx >/dev/null 2>&1; then
    echo "release.sh: npx (Node.js) is not on PATH; needed for wrangler" >&2
    exit 1
  fi
  echo "==> checking Cloudflare login"
  if ! whoami_out="$("${WRANGLER[@]}" whoami </dev/null 2>&1)" \
      || ! grep -qi "you are logged in" <<<"$whoami_out"; then
    echo "$whoami_out" >&2
    echo "" >&2
    echo "release.sh: not signed in to Cloudflare." >&2
    echo "  Run: npx wrangler@4 login   (or pass --no-deploy)" >&2
    exit 1
  fi
  # Show which account this is going to, so a wrong login is caught here.
  grep -i "you are logged in" <<<"$whoami_out" | sed 's/^/    /' || true
fi

# Stop on the first failure: a half-built set is not something to ship.
for app in "${SELECTED[@]}"; do
  dir="$ROOT/apps/${app}_app"
  echo ""
  echo "==> building ${app}_app"

  if [[ "$CLEAN" == true ]]; then
    (cd "$dir" && flutter clean)
  fi

  started=$SECONDS
  (cd "$dir" && flutter build web)
  echo "    done in $((SECONDS - started))s"
done

if [[ "$DEPLOY" == false ]]; then
  echo ""
  echo "Built ${#SELECTED[@]} app(s), not deployed:"
  for app in "${SELECTED[@]}"; do
    out="$ROOT/apps/${app}_app/build/web"
    printf '  %-10s %s (%s)\n' "$app" "$out" "$(du -sh "$out" | cut -f1)"
  done
  exit 0
fi

# Every app is built before any is deployed, so a build failure never leaves
# the live apps on a mix of old and new code.
#
# --branch main makes it a production deploy; otherwise wrangler uses the
# current git branch and a feature branch would land as a preview.
for app in "${SELECTED[@]}"; do
  project="$(pages_project "$app")"
  echo ""
  echo "==> deploying ${app}_app to ${project}.pages.dev"
  "${WRANGLER[@]}" pages deploy "$ROOT/apps/${app}_app/build/web" \
    --project-name "$project" --branch main --commit-dirty=true </dev/null
done

echo ""
echo "Deployed ${#SELECTED[@]} app(s):"
for app in "${SELECTED[@]}"; do
  printf '  %-10s https://%s.pages.dev\n' "$app" "$(pages_project "$app")"
done
