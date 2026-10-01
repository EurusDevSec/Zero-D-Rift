[CmdletBinding()]
param(
    [string]$RepoRoot
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$contextPath = Join-Path $RepoRoot ".agent\workflows\active_context.md"

if (-not (Test-Path -LiteralPath $contextPath -PathType Leaf)) {
    Write-Error "Missing active context: $contextPath"
    exit 1
}

$content = Get-Content -Raw -LiteralPath $contextPath
$lines = Get-Content -LiteralPath $contextPath

if ($content -notmatch '(?s)^---\s*\r?\n(.*?)\r?\n---') {
    $errors.Add("active_context.md has no valid leading front matter block")
    $frontMatter = ""
} else {
    $frontMatter = $Matches[1]
}

$requiredKeys = @(
    "project",
    "status",
    "active_phase",
    "active_task",
    "active_spec",
    "current_learning",
    "authority",
    "last_reviewed"
)

$values = @{}
foreach ($key in $requiredKeys) {
    $match = [regex]::Match($frontMatter, "(?m)^$([regex]::Escape($key)):\s*(.+?)\s*$")
    if (-not $match.Success) {
        $errors.Add("missing front matter key: $key")
    } else {
        $values[$key] = $match.Groups[1].Value.Trim().Trim('"', "'")
    }
}

foreach ($pointerKey in @("active_spec", "current_learning")) {
    if ($values.ContainsKey($pointerKey)) {
        $target = Join-Path $RepoRoot ($values[$pointerKey] -replace '/', '\')
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            $errors.Add("$pointerKey target does not exist: $($values[$pointerKey])")
        }
    }
}

if ($frontMatter -match '(?m)^git_(head|state):') {
    $errors.Add("deprecated live Git field found; re-query Git instead of embedding authoritative state")
}

foreach ($heading in @(
    "# Active Context",
    "## Current verified state",
    "## Open decisions and blockers",
    "## Next safe action",
    "## Context expansion",
    "## Checkpoint rule"
)) {
    if ($content -notmatch [regex]::Escape($heading)) {
        $errors.Add("missing required section: $heading")
    }
}

if ($lines.Count -gt 90) {
    $warnings.Add("active_context.md has $($lines.Count) lines; review for duplicated or historical content")
}

Write-Output "CONTEXT_LINES=$($lines.Count)"
foreach ($warning in $warnings) { Write-Warning $warning }
foreach ($errorMessage in $errors) { Write-Output "ERROR=$errorMessage" }

if ($errors.Count -gt 0) {
    Write-Output "CONTEXT_CHECK=FAIL"
    exit 1
}

Write-Output "CONTEXT_CHECK=PASS"
