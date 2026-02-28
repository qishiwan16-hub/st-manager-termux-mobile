#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MARK_START="/* ST_MOBILE_UI_START */"
MARK_END="/* ST_MOBILE_UI_END */"
ACTION="apply"

if [ "${1:-}" = "--remove" ]; then
  ACTION="remove"
  shift
elif [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'HELP_EOF'
Usage:
  bash scripts/patch-mobile-ui.sh           # apply/update mobile UI patch
  bash scripts/patch-mobile-ui.sh --remove  # remove mobile UI patch

Environment:
  APP_DIR=/path/to/app                      # optional app directory
HELP_EOF
  exit 0
fi

log_info() {
  printf '[mobile-ui] %s\n' "$1"
}

log_warn() {
  printf '[mobile-ui] WARN: %s\n' "$1"
}

resolve_css_file() {
  local html_file="$APP_DIR/.next/server/app/index.html"
  local rel_path css_candidate fallback_css

  if [ -f "$html_file" ]; then
    rel_path="$(grep -oE '/_next/static/css/[^"]+\.css' "$html_file" | head -n 1 || true)"
    if [ -n "$rel_path" ]; then
      css_candidate="$APP_DIR/.next/${rel_path#/_next/}"
      if [ -f "$css_candidate" ]; then
        printf '%s' "$css_candidate"
        return 0
      fi
    fi
  fi

  fallback_css="$(find "$APP_DIR/.next/static/css" -maxdepth 1 -type f -name '*.css' 2>/dev/null | sort | head -n 1 || true)"
  if [ -n "$fallback_css" ]; then
    printf '%s' "$fallback_css"
    return 0
  fi

  return 1
}

strip_patch_block() {
  local target_file="$1"
  awk -v start="$MARK_START" -v end="$MARK_END" '
    index($0, start) { skipping=1; next }
    index($0, end) { skipping=0; next }
    !skipping { print }
  ' "$target_file"
}

trim_trailing_blank_lines() {
  local target_file="$1"
  awk '
    { lines[NR] = $0 }
    END {
      last = NR
      while (last > 0 && lines[last] ~ /^[[:space:]]*$/) {
        last--
      }
      for (i = 1; i <= last; i++) {
        print lines[i]
      }
    }
  ' "$target_file"
}

append_patch_block() {
  cat <<'PATCH_EOF'
/* ST_MOBILE_UI_START */
@media (max-width: 900px) {
  html,
  body {
    height: 100%;
    overflow: hidden;
  }

  body > .flex.h-screen.overflow-hidden {
    display: flex;
    flex-direction: column;
    height: 100dvh;
    overflow: hidden;
  }

  body > .flex.h-screen.overflow-hidden > aside {
    width: 100% !important;
    max-width: none !important;
    min-height: 0;
    border-right: 0 !important;
    border-bottom: 1px solid hsl(var(--sidebar-border));
  }

  body > .flex.h-screen.overflow-hidden > aside > .flex.items-center.h-14.px-4.border-b {
    height: 3.25rem;
    padding: 0 0.75rem;
    border-bottom: 0;
  }

  body > .flex.h-screen.overflow-hidden > aside > .flex.items-center.h-14.px-4.border-b h1 {
    font-size: 1rem;
    max-width: 70vw;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  body > .flex.h-screen.overflow-hidden > aside nav {
    display: flex;
    flex: 0 0 auto;
    gap: 0.375rem;
    padding: 0.5rem 0.5rem 0.625rem;
    overflow-x: auto;
    overflow-y: hidden;
    white-space: nowrap;
    scrollbar-width: none;
    -webkit-overflow-scrolling: touch;
  }

  body > .flex.h-screen.overflow-hidden > aside nav::-webkit-scrollbar {
    display: none;
  }

  body > .flex.h-screen.overflow-hidden > aside nav > a {
    flex: 0 0 auto;
    display: inline-flex;
  }

  body > .flex.h-screen.overflow-hidden > aside nav > a > div {
    padding: 0.5rem 0.625rem;
    gap: 0.375rem;
    border-radius: 0.5rem;
  }

  body > .flex.h-screen.overflow-hidden > aside nav > a > div svg {
    width: 1rem;
    height: 1rem;
  }

  body > .flex.h-screen.overflow-hidden > aside nav > a > div span {
    font-size: 0.8125rem;
    line-height: 1.2;
  }

  body > .flex.h-screen.overflow-hidden > aside > .p-2.border-t {
    padding: 0.375rem 0.5rem;
    border-top: 0;
  }

  body > .flex.h-screen.overflow-hidden > aside > .p-2.border-t button {
    height: 2rem;
    padding: 0.25rem 0.5rem;
    justify-content: center;
  }

  body > .flex.h-screen.overflow-hidden > aside > .p-2.border-t button span {
    display: none;
  }

  body > .flex.h-screen.overflow-hidden > main {
    flex: 1 1 auto;
    min-height: 0;
    overflow-y: auto;
    -webkit-overflow-scrolling: touch;
  }

  body > .flex.h-screen.overflow-hidden > main > .container.mx-auto.p-6.max-w-7xl {
    max-width: 100% !important;
    padding: 0.75rem !important;
  }

  .max-w-sm,
  .sm\:max-w-md,
  .sm\:max-w-lg {
    max-width: 100% !important;
  }

  .hidden.sm\:inline,
  [class*="hidden sm:inline"] {
    display: none !important;
  }

  .grid.grid-cols-2.md\:grid-cols-3.lg\:grid-cols-4.xl\:grid-cols-5 {
    grid-template-columns: repeat(2, minmax(0, 1fr)) !important;
    gap: 0.5rem !important;
  }
}

@media (max-width: 480px) {
  body > .flex.h-screen.overflow-hidden > aside > .flex.items-center.h-14.px-4.border-b h1 {
    max-width: 62vw;
    font-size: 0.95rem;
  }

  body > .flex.h-screen.overflow-hidden > aside nav > a > div {
    padding: 0.44rem 0.56rem;
  }

  body > .flex.h-screen.overflow-hidden > main > .container.mx-auto.p-6.max-w-7xl {
    padding: 0.5rem !important;
  }

  h2.text-3xl.font-bold.tracking-tight {
    font-size: 1.35rem;
    line-height: 1.25;
  }
}
/* ST_MOBILE_UI_END */
PATCH_EOF
}

main() {
  local css_file tmp_file

  if ! css_file="$(resolve_css_file)"; then
    log_warn "no css file found under .next/static/css, skipping"
    exit 0
  fi

  log_info "target css: $css_file"
  tmp_file="$(mktemp "${css_file}.tmp.XXXXXX")"

  strip_patch_block "$css_file" >"$tmp_file"
  trim_trailing_blank_lines "$tmp_file" >"${tmp_file}.trimmed"
  mv "${tmp_file}.trimmed" "$tmp_file"

  if [ "$ACTION" = "apply" ]; then
    printf '\n' >>"$tmp_file"
    append_patch_block >>"$tmp_file"
  fi

  if cmp -s "$css_file" "$tmp_file"; then
    rm -f "$tmp_file"
    log_info "no change needed"
    exit 0
  fi

  chmod --reference="$css_file" "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$css_file"

  if [ "$ACTION" = "apply" ]; then
    log_info "mobile ui patch applied"
  else
    log_info "mobile ui patch removed"
  fi
}

main "$@"
