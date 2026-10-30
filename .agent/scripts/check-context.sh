#!/usr/bin/env bash
# Validate the structure and pointers of .agent/workflows/active_context.md.
# Usage: .agent/scripts/check-context.sh [repo_root]
# Exit 0 with CONTEXT_CHECK=PASS, or exit 1 with ERROR= lines and CONTEXT_CHECK=FAIL.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${1:-$(cd "$script_dir/../.." && pwd)}"
context_path="$repo_root/.agent/workflows/active_context.md"

errors=()
warnings=()

if [[ ! -f "$context_path" ]]; then
    echo "Missing active context: $context_path" >&2
    exit 1
fi

# Strip CR so files with Windows line endings behave like LF files.
content="$(tr -d '\r' < "$context_path")"
# awk counts a final line even when the file has no trailing newline.
line_count="$(awk 'END { print NR }' "$context_path")"

# Front matter: first line is ---, block ends at the next line starting with ---.
front_matter=""
if [[ "$(head -n 1 <<< "$content")" =~ ^---[[:space:]]*$ ]] &&
    tail -n +2 <<< "$content" | grep -q '^---'; then
    front_matter="$(tail -n +2 <<< "$content" | sed '/^---/,$d')"
else
    errors+=("active_context.md has no valid leading front matter block")
fi

required_keys=(
    project
    status
    active_phase
    active_task
    active_spec
    current_learning
    authority
    last_reviewed
)

declare -A values=()
for key in "${required_keys[@]}"; do
    line="$(grep -m 1 "^${key}:[[:space:]]*[^[:space:]]" <<< "$front_matter" || true)"
    if [[ -z "$line" ]]; then
        errors+=("missing front matter key: $key")
        continue
    fi
    value="${line#"${key}:"}"
    # Trim surrounding whitespace, then one layer of surrounding quotes.
    value="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        -e "s/^[\"']//" -e "s/[\"']\$//" <<< "$value")"
    values[$key]="$value"
done

for pointer_key in active_spec current_learning; do
    if [[ -n "${values[$pointer_key]:-}" && ! -f "$repo_root/${values[$pointer_key]}" ]]; then
        errors+=("$pointer_key target does not exist: ${values[$pointer_key]}")
    fi
done

if grep -Eq '^git_(head|state):' <<< "$front_matter"; then
    errors+=("deprecated live Git field found; re-query Git instead of embedding authoritative state")
fi

required_headings=(
    "# Active Context"
    "## Current verified state"
    "## Open decisions and blockers"
    "## Next safe action"
    "## Context expansion"
    "## Checkpoint rule"
)
for heading in "${required_headings[@]}"; do
    if ! grep -qF -- "$heading" <<< "$content"; then
        errors+=("missing required section: $heading")
    fi
done

if (( line_count > 90 )); then
    warnings+=("active_context.md has $line_count lines; review for duplicated or historical content")
fi

echo "CONTEXT_LINES=$line_count"
for warning in "${warnings[@]+"${warnings[@]}"}"; do
    echo "WARNING: $warning" >&2
done
for error_message in "${errors[@]+"${errors[@]}"}"; do
    echo "ERROR=$error_message"
done

if (( ${#errors[@]} > 0 )); then
    echo "CONTEXT_CHECK=FAIL"
    exit 1
fi

echo "CONTEXT_CHECK=PASS"
