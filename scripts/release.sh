#!/usr/bin/env bash
#
# Build release bundles for the workspace apps.
#
#   ./scripts/release.sh --web                   # all four apps
#   ./scripts/release.sh --web patient doctor    # just those two
#   ./scripts/release.sh --web --clean           # flutter clean first
#
# Netlify uploads are manual, so the run ends by printing the directory to
# drag across for each app it built.

set -euo pipefail

# Workspace order matches pubspec.yaml.
APPS=(patient doctor assistant admin)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BUILD_WEB=false
CLEAN=false
SELECTED=()

usage() {
  cat <<'EOF'
Usage: ./scripts/release.sh --web [app...] [--clean]

Targets:
  --web            flutter build web for each selected app

Options:
  --clean          flutter clean in each app before building
  -h, --help       show this message

Apps (default: all): patient, doctor, assistant, admin
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --web)   BUILD_WEB=true; shift ;;
    --clean) CLEAN=true; shift ;;
    -h|--help) usage; exit 0 ;;
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

if [[ "$BUILD_WEB" == false ]]; then
  echo "release.sh: no target given; --web is currently the only one" >&2
  usage >&2
  exit 2
fi

if [[ ${#SELECTED[@]} -eq 0 ]]; then
  SELECTED=("${APPS[@]}")
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "release.sh: flutter is not on PATH" >&2
  exit 1
fi

# Stop on the first failure: a half-built set is not something to ship.
for app in "${SELECTED[@]}"; do
  dir="$ROOT/apps/${app}_app"
  echo ""
  echo "==> ${app}_app"

  if [[ "$CLEAN" == true ]]; then
    (cd "$dir" && flutter clean)
  fi

  started=$SECONDS
  (cd "$dir" && flutter build web)
  echo "    done in $((SECONDS - started))s"
done

echo ""
echo "Built ${#SELECTED[@]} app(s). Upload these to Netlify:"
for app in "${SELECTED[@]}"; do
  out="$ROOT/apps/${app}_app/build/web"
  printf '  %-10s %s (%s)\n' "$app" "$out" "$(du -sh "$out" | cut -f1)"
done
