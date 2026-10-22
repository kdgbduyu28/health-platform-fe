#!/usr/bin/env bash
#
# Build the workspace apps for the web and deploy them to Cloudflare Pages.
#
#   ./scripts/release.sh                         # build + deploy all four apps
#   ./scripts/release.sh patient doctor          # just those two
#   ./scripts/release.sh --clean                 # clear the bundler cache first
#   ./scripts/release.sh --no-deploy             # build only, print the folders
#   ./scripts/release.sh --apk                   # Android: tag + push; GitHub builds all four APKs into Releases
#   ./scripts/release.sh --apk=v1.2.0            # same, with an explicit version (default: apps/patient/app.json)
#
# Each app goes to its own Pages project, served at <project>.pages.dev.
# Deploys are production deploys whatever git branch you are on, and a dirty
# working tree is allowed: what ships is what is on disk.

set -euo pipefail

# Workspace order matches package.json.
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
APK=false
APK_TAG=
SELECTED=()

usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh [app...] [--clean] [--no-deploy]

Builds each selected app for the web, then deploys it to Cloudflare Pages.

Options:
  --clean          clear each app's bundler cache and old build first
  --no-deploy      build only; print the build folders instead of deploying
  --apk[=vX.Y.Z]   Android instead of web: tag this commit and push the tag; GitHub
                   Actions builds all four APKs and attaches them to the repo's Releases
  --web            accepted for compatibility (web is the default target)
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
    --apk)       APK=true; shift ;;
    --apk=*)     APK=true; APK_TAG="${1#--apk=}"; shift ;;
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

# --apk: tag this commit and push the tag. GitHub Actions
# (.github/workflows/android-release.yml) builds the APK from that tag and attaches it to
# the repository's Releases page, so nothing is built here and it costs nothing.
release_apk() {
  local tag="$1"
  cd "$ROOT"
  [[ -n "$tag" ]] || tag="v$(node -p 'require("./apps/patient/app.json").expo.version')"
  [[ "$tag" == v* ]] || tag="v$tag"
  if ! git remote get-url origin >/dev/null 2>&1; then
    echo "release.sh: no GitHub remote yet; create the repo and push it first" >&2
    exit 1
  fi
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "release.sh: commit your changes first; the APK is built from GitHub, not this folder" >&2
    exit 1
  fi
  git fetch --quiet origin
  if ! git merge-base --is-ancestor HEAD '@{u}' 2>/dev/null; then
    echo "release.sh: push this branch first (git push); the APK is built from GitHub" >&2
    exit 1
  fi
  if git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null \
      || git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null; then
    echo "release.sh: $tag already exists; bump the version or pass --apk=vX.Y.Z" >&2
    exit 1
  fi
  git tag -a "$tag" -m "$tag"
  git push --quiet origin "refs/tags/$tag"
  local repo
  repo="$(git remote get-url origin | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
  echo "Tagged $tag; GitHub Actions is building the APK (15-25 min):"
  echo "  progress: https://github.com/$repo/actions/workflows/android-release.yml"
  echo "  download: https://github.com/$repo/releases/tag/$tag"
}

if [[ "$APK" == true ]]; then
  release_apk "$APK_TAG"
  exit 0
fi

if [[ ${#SELECTED[@]} -eq 0 ]]; then
  SELECTED=("${APPS[@]}")
fi

if ! command -v npx >/dev/null 2>&1; then
  echo "release.sh: npx (Node.js) is not on PATH" >&2
  exit 1
fi
if [[ ! -d "$ROOT/node_modules" ]]; then
  echo "release.sh: dependencies are not installed; run: npm install" >&2
  exit 1
fi

# Check the Cloudflare login before spending minutes on builds that could not
# be shipped anyway.
if [[ "$DEPLOY" == true ]]; then
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
#
# Each app is exported as a static single-page site into apps/<app>/dist,
# with the files in its public/ folder (_redirects, push_sw.js, icons)
# copied alongside. EXPO_PUBLIC_* variables set in the environment are baked
# into the bundle; without them the defaults in supabase_config.ts apply.
for app in "${SELECTED[@]}"; do
  dir="$ROOT/apps/${app}"
  echo ""
  echo "==> building ${app}"

  extra=()
  if [[ "$CLEAN" == true ]]; then
    rm -rf "$dir/dist" "$dir/.expo"
    extra=(--clear)
  fi

  started=$SECONDS
  (cd "$dir" && rm -rf dist && npx expo export --platform web --output-dir dist ${extra[@]+"${extra[@]}"} </dev/null)
  echo "    done in $((SECONDS - started))s"
done

if [[ "$DEPLOY" == false ]]; then
  echo ""
  echo "Built ${#SELECTED[@]} app(s), not deployed:"
  for app in "${SELECTED[@]}"; do
    out="$ROOT/apps/${app}/dist"
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
  echo "==> deploying ${app} to ${project}.pages.dev"
  "${WRANGLER[@]}" pages deploy "$ROOT/apps/${app}/dist" \
    --project-name "$project" --branch main --commit-dirty=true </dev/null
done

echo ""
echo "Deployed ${#SELECTED[@]} app(s):"
for app in "${SELECTED[@]}"; do
  printf '  %-10s https://%s.pages.dev\n' "$app" "$(pages_project "$app")"
done
