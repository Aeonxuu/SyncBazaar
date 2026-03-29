$ErrorActionPreference = 'Stop'

function Get-HookPayload {
    try {
        if (-not [Console]::IsInputRedirected) {
            return $null
        }
        $raw = [Console]::In.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }
        return $raw | ConvertFrom-Json -Depth 25
    } catch {
        return $null
    }
}

function Should-RunForTool {
    param(
        [object]$payload
    )

    if ($null -eq $payload) {
        return $true
    }

    $toolName = ''
    if ($payload.PSObject.Properties.Name -contains 'toolName') {
        $toolName = [string]$payload.toolName
    } elseif ($payload.PSObject.Properties.Name -contains 'tool_name') {
        $toolName = [string]$payload.tool_name
    }

    if ([string]::IsNullOrWhiteSpace($toolName)) {
        return $true
    }

    $editTools = @(
        'apply_patch',
        'edit',
        'write',
        'create_file',
        'str_replace',
        'rename',
        'delete'
    )

    return $editTools -contains $toolName
}

function Emit-Message {
    param(
        [string]$text
    )

    @{ continue = $true; systemMessage = $text } | ConvertTo-Json -Compress
}

function Add-DartPathsFromObject {
    param(
        [object]$value,
        [ref]$bucket
    )

    if ($null -eq $value) {
        return
    }

    if ($value -is [string]) {
        if ($value -like '*.dart') {
            $bucket.Value += $value
        }
        return
    }

    if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
        foreach ($item in $value) {
            Add-DartPathsFromObject -value $item -bucket $bucket
        }
        return
    }

    foreach ($prop in $value.PSObject.Properties) {
        Add-DartPathsFromObject -value $prop.Value -bucket $bucket
    }
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Emit-Message 'Hook skipped: flutter not available.'
    exit 0
}

$payload = Get-HookPayload
if (-not (Should-RunForTool -payload $payload)) {
    Emit-Message 'Hook skipped: non-edit tool.'
    exit 0
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
Push-Location $projectRoot

try {
    $targets = @()

    if (Get-Command git -ErrorAction SilentlyContinue) {
        $changed = @(git diff --name-only -- '*.dart')
        if ($LASTEXITCODE -eq 0 -and $changed.Count -gt 0) {
            $targets += $changed
        }
    }

    if ($targets.Count -eq 0 -and $null -ne $payload) {
        Add-DartPathsFromObject -value $payload -bucket ([ref]$targets)
    }

    $targets = $targets |
        Where-Object {
            $_ -like 'lib/*.dart' -or
            $_ -like 'test/*.dart' -or
            $_ -like 'integration_test/*.dart' -or
            $_ -like '*.dart'
        } |
        ForEach-Object {
            if ([System.IO.Path]::IsPathRooted($_)) {
                $_
            } else {
                Join-Path $projectRoot $_
            }
        } |
        Where-Object { Test-Path $_ } |
        Select-Object -Unique

    if ($targets.Count -eq 0) {
        Emit-Message 'Hook check: no analyzable Dart targets found.'
        exit 0
    }

    flutter analyze @targets | Out-Host
    if ($LASTEXITCODE -eq 0) {
        Emit-Message 'flutter analyze passed for changed Dart files.'
    } else {
        Emit-Message 'flutter analyze found issues in changed Dart files.'
    }
} finally {
    Pop-Location
}

exit 0
