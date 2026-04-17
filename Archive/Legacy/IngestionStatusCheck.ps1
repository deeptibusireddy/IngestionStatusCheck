<#
.SYNOPSIS
    Find URLs from an input list that do not exist in the content database.

.DESCRIPTION
    Pure PowerShell - no Python, no EXE, no admin rights required.
    Requires the ImportExcel module (auto-installed on first run, no admin needed).

.EXAMPLE
    .\IngestionStatusCheck.ps1 -InputFile "C:\Path\To\YourURLs.xlsx" -InputSheet "Sheet1" -InputNoHeader
#>
[CmdletBinding()]
param(
    [string]$InputFile,

    [string]$InputSheet   = "Sheet1",
    [switch]$InputNoHeader,
    [string]$InputColumn,

    [string]$DbFile,
    [string]$DbSheet,
    [string]$DbUrlColumn  = "DocumentLink",

    [string]$BlockedFile,
    [string]$BlockedSheet,
    [string]$BlockedUrlColumn = "ArticlePublicLink",

    [string]$OutputFile,
    [string]$AuditOutputFile,
    [string]$OutputFolder = "audit_results",
    [string]$OutputTag,
    [switch]$PromptForOutputTag,

    [switch]$NoResolveRedirects,
    [int]$TimeoutSec = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Constants ────────────────────────────────────────────────────────────────

$FALLBACK_SOURCES = @{
    ingested = @("IngestedURLs.xlsx")
    blocked  = @("BlockedURLs.xlsx")
}

$TRACKING_PREFIXES = "utm_", "mc_"
$TRACKING_KEYS     = [System.Collections.Generic.HashSet[string]]@(
    "gclid","fbclid","msclkid","igshid","yclid","_hsenc","_hsmi"
)
$GUID_RE = [regex]"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

function Test-LooksLikeUrl {
    param([string]$Value)
    if (-not $Value) { return $false }
    return ($Value.Trim() -match '^(?i)https?://')
}

function Get-SafeTag {
    param([string]$Tag)
    if (-not $Tag) { return "" }
    $clean = $Tag.Trim()
    if (-not $clean) { return "" }

    foreach ($ch in [System.IO.Path]::GetInvalidFileNameChars()) {
        $clean = $clean.Replace([string]$ch, "-")
    }

    # Keep file names readable and avoid repeated separators.
    $clean = ($clean -replace '\s+', '-') -replace '-+', '-'
    return $clean.Trim('-')
}

function Prompt-ForInputFile {
    $scriptDir = Split-Path -Parent $PSCommandPath

    while ($true) {
        $entered = Read-Host "Enter input file path (.xlsx/.csv/.txt)"
        if (-not $entered) {
            Write-Host "Input file path is required." -ForegroundColor Yellow
            continue
        }

        # Accept raw, quoted, or single-quoted values pasted by users.
        $candidate = $entered.Trim().Trim('"').Trim("'")
        if (-not $candidate) {
            Write-Host "Input file path is required." -ForegroundColor Yellow
            continue
        }

        $candidates = [System.Collections.Generic.List[string]]::new()
        $candidates.Add($candidate)

        if (-not [System.IO.Path]::IsPathRooted($candidate)) {
            $candidates.Add((Join-Path (Get-Location) $candidate))
            $candidates.Add((Join-Path $scriptDir $candidate))
        }

        $resolved = $null
        foreach ($c in $candidates) {
            if (Test-Path $c -PathType Leaf) {
                $resolved = (Resolve-Path $c).Path
                break
            }
        }

        if ($resolved) {
            return $resolved
        }

        Write-Host "File not found: $candidate" -ForegroundColor Yellow
        Write-Host "Tip: enter full path or just file name if it is in the current/script folder." -ForegroundColor DarkYellow
    }
}

# ── Module setup ─────────────────────────────────────────────────────────────

function Read-XlsxViaExcelCom {
        param([string]$Path, [string]$Sheet, [string]$Column, [switch]$NoHeader)

        Write-Host "  Opening $([System.IO.Path]::GetFileName($Path)) via Excel..."
        $xl = New-Object -ComObject Excel.Application
        $xl.Visible = $false
        $xl.DisplayAlerts = $false
        try {
            $wb   = $xl.Workbooks.Open($Path, 0, $true)  # read-only
            $ws   = if ($Sheet) { $wb.Sheets.Item($Sheet) } else { $wb.ActiveSheet }
            $used = $ws.UsedRange
            $rows = $used.Rows.Count
            $cols = $used.Columns.Count

            $headers = @()
            for ($c = 1; $c -le $cols; $c++) { $headers += "$($ws.Cells.Item(1,$c).Text)".Trim() }

            $effectiveNoHeader = $NoHeader

            # Auto-detect if the first row is data (URL) when no explicit mode is provided.
            if (-not $NoHeader -and -not $Column) {
                $firstCell = "$($ws.Cells.Item(1,1).Text)".Trim()
                if (Test-LooksLikeUrl -Value $firstCell) {
                    $effectiveNoHeader = $true
                    Write-Host "  Auto-detected input format: no header row"
                }
            }

            $colIdx = 1
            if (-not $effectiveNoHeader -and $Column) {
                for ($c = 0; $c -lt $headers.Count; $c++) {
                    if ($headers[$c] -eq $Column) { $colIdx = $c + 1; break }
                }
            }

            $startRow = if ($effectiveNoHeader) { 1 } else { 2 }
            Write-Host "  Reading $($rows - $startRow + 1) data rows..."

            # Read entire column as array — orders of magnitude faster than cell-by-cell
            $colRange = $ws.Range($ws.Cells.Item($startRow, $colIdx), $ws.Cells.Item($rows, $colIdx))
            $vals = $colRange.Value2

            $urls = [System.Collections.Generic.List[string]]::new()
            if ($vals -is [System.Object[,]]) {
                $len = $vals.GetUpperBound(0)
                for ($i = 1; $i -le $len; $i++) {
                    $v = "$($vals[$i,1])".Trim()
                    if ($v -and $v -ne "") { $urls.Add($v) }
                }
            } elseif ($vals) {
                $v = "$vals".Trim()
                if ($v) { $urls.Add($v) }
            }
            return ,$urls.ToArray()
        } finally {
            try { $wb.Close($false) } catch { }
            try { $xl.Quit() } catch { }
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($xl) | Out-Null
        }
}

# ── URL helpers ───────────────────────────────────────────────────────────────

function Normalize-Url {
    param([string]$Raw)
    $value = if ($Raw) { $Raw.Trim() } else { "" }
    if (-not $value) { return "" }

    $uri = $null
    try { $uri = [System.Uri]::new($value) } catch { return "" }
    if ($uri.Scheme -notin "http","https") { return "" }

    $scheme  = $uri.Scheme
    $urlHost = $uri.Host.ToLower()

    # Include non-default ports
    $isDefault = ($scheme -eq "http"  -and $uri.Port -eq 80) -or
                 ($scheme -eq "https" -and $uri.Port -eq 443)
    if (-not $isDefault -and $uri.Port -ne -1) { $urlHost = "${urlHost}:$($uri.Port)" }

    # Strip trailing slash
    $path = $uri.AbsolutePath
    if ($path.Length -gt 1 -and $path.EndsWith("/")) { $path = $path.Substring(0, $path.Length - 1) }

    # Filter tracking params, sort remainder
    $qItems = [System.Collections.Generic.List[string]]::new()
    if ($uri.Query) {
        foreach ($pair in $uri.Query.TrimStart("?").Split("&")) {
            if (-not $pair) { continue }
            $k = ([System.Uri]::UnescapeDataString($pair.Split("=",2)[0])).ToLower()
            $skip = $false
            foreach ($p in $TRACKING_PREFIXES) { if ($k.StartsWith($p)) { $skip = $true; break } }
            if ($skip -or $TRACKING_KEYS.Contains($k)) { continue }
            $qItems.Add($pair)
        }
        $qItems.Sort()
    }

    $result = "${scheme}://${urlHost}${path}"
    if ($qItems.Count) { $result += "?" + ($qItems -join "&") }
    return $result
}

function Remove-QueryString {
    param([string]$Url)
    if (-not $Url) { return "" }
    $i = $Url.IndexOf("?")
    if ($i -ge 0) { return $Url.Substring(0, $i) }
    return $Url
}

function Get-Guids {
    param([string]$Text)
    $safe = if ($Text) { $Text } else { "" }
    return @($GUID_RE.Matches($safe) | ForEach-Object { $_.Value.ToLower() })
}

function Test-LoginRequired {
    param([string]$InputUrl, [string]$ResolvedUrl, [string]$ResolveError)

    if ($ResolvedUrl) {
        try {
            $u = [System.Uri]::new($ResolvedUrl)
            $h = $u.Host.ToLower()
            $p = $u.AbsolutePath.ToLower()
            $q = $u.Query.ToLower()
            if (($p -match "_signin|/signin") -and ($h -match "visualstudio\.com|microsoftonline\.com|login\.live\.com")) { return $true }
            if ($q -match "realm=dev\.azure\.com")           { return $true }
            if ($q -match "reply_to=.*dev\.azure\.com")      { return $true }
        } catch { }
    }

    # A 403/401 from the HTTP probe only means anonymous access was denied —
    # the URL may still exist in the DB and should be matched normally.
    # Only treat as not-testable when the URL actually redirected to a sign-in page.
    return $false
}

function Resolve-FinalUrl {
    param([string]$Url, [int]$Ms)
    $lastErr = ""
    foreach ($method in "HEAD","GET") {
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
            $req = [System.Net.HttpWebRequest]::Create($Url)
            $req.Method = $method
            $req.Timeout = $Ms
            $req.UserAgent = "ingestion-link-audit/1.0"
            $req.AllowAutoRedirect = $true
            $resp = $req.GetResponse()
            $final = $resp.ResponseUri.ToString()
            $resp.Close()
            return @{ Url = $final; Error = $null }
        } catch {
            $lastErr = "${method}: $($_.Exception.Message)"
        }
    }
    return @{ Url = $null; Error = $lastErr }
}

# ── File discovery ────────────────────────────────────────────────────────────

function Find-DataFile {
    param([string]$Label)
    $filenames = $FALLBACK_SOURCES[$Label]
    if (-not $filenames) { return $null }

    if ($filenames -isnot [System.Array]) {
        $filenames = @($filenames)
    }

    $userHome = [System.Environment]::GetFolderPath("UserProfile")
    $scriptDir = Split-Path -Parent $PSCommandPath

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($filename in $filenames) {
        $candidates.Add((Join-Path $scriptDir $filename))
        $candidates.Add((Join-Path (Get-Location) $filename))
    }

    # Auto-discover any OneDrive-synced SharePoint libraries under ~/Microsoft/
    $msDir = Join-Path $userHome "Microsoft"
    if (Test-Path $msDir -PathType Container) {
        Get-ChildItem $msDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            foreach ($filename in $filenames) {
                $candidates.Add((Join-Path $_.FullName $filename))
            }
        }
    }

    foreach ($filename in $filenames) {
        $candidates.Add((Join-Path $userHome "OneDrive - Microsoft\MCfS Team Stuff\Desktop\$filename"))
        $candidates.Add((Join-Path $userHome "OneDrive - Microsoft\$filename"))
        $candidates.Add((Join-Path $userHome "Desktop\$filename"))
    }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c -PathType Leaf)) { return $c }
    }
    return $null
}

function Resolve-DataSource {
    param([string]$Source, [string]$Label)
    if ($Source -and (Test-Path $Source -PathType Leaf)) { return $Source }

    $local = Find-DataFile -Label $Label
    if ($local) {
        Write-Host "Using local $Label source: $local"
        return $local
    }
    $expected = $FALLBACK_SOURCES[$Label]
    if ($expected -is [System.Array]) { $expected = $expected -join " or " }
    throw "Could not find $Label data file ($expected). " +
          "Place it in the same folder as this script, or sync the SharePoint library via OneDrive."
}

# ── Read URLs from file ───────────────────────────────────────────────────────

function Read-Urls {
    param([string]$Path, [string]$Sheet, [switch]$NoHeader, [string]$Column)

    $ext = [System.IO.Path]::GetExtension($Path).ToLower()

    if ($ext -in ".txt",".list") {
        return @(Get-Content $Path | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
    }

    if ($ext -eq ".csv") {
        $effectiveNoHeader = $NoHeader

        # Auto-detect if the first CSV row appears to be a URL value.
        if (-not $NoHeader -and -not $Column) {
            $firstLine = Get-Content -Path $Path -TotalCount 1 -ErrorAction SilentlyContinue
            if ($firstLine) {
                $firstValue = ($firstLine -split ',', 2)[0].Trim().Trim('"')
                if (Test-LooksLikeUrl -Value $firstValue) {
                    $effectiveNoHeader = $true
                    Write-Host "  Auto-detected input format: CSV has no header row"
                }
            }
        }

        if ($effectiveNoHeader) {
            return @(Import-Csv -Path $Path -Header "url" | Where-Object { $_.url } | ForEach-Object { $_.url.Trim() })
        }
        $data = Import-Csv -Path $Path
        $col  = if ($Column) { $Column } else { $data[0].PSObject.Properties.Name | Select-Object -First 1 }
        return @($data | Where-Object { $_.$col } | ForEach-Object { ($_.$col).Trim() })
    }

    if ($ext -eq ".xlsx") {
        # Use Excel COM (fast for large files, available on all Microsoft machines)
        return Read-XlsxViaExcelCom -Path $Path -Sheet $Sheet -Column $Column -NoHeader:$NoHeader
    }

    throw "Unsupported file type: $ext"
}

# ── Build lookup sets ─────────────────────────────────────────────────────────

function Build-LookupSets {
    param(
        [string[]]$Urls,
        [string]$Label = "URLs"
    )

    $total = [Math]::Max($Urls.Count, 1)
    $i = 0
    $full = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $guid = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($u in $Urls) {
        $i++
        if (($i % 5000) -eq 0 -or $i -eq $Urls.Count) {
            Write-Progress -Activity "Building $Label lookup" -Status "$i / $($Urls.Count)" -PercentComplete ([int]($i * 100 / $total))
            Write-Host "Indexed $i of $($Urls.Count) $Label rows..."
        }
        $n = Normalize-Url $u
        if ($n) {
            [void]$full.Add($n)
            foreach ($g in (Get-Guids $n)) { [void]$guid.Add($g) }
        }
    }
    Write-Progress -Activity "Building $Label lookup" -Completed
    return @{ Full = $full; Path = @{}; Guid = $guid }
}

# ── Classify one URL ──────────────────────────────────────────────────────────

function Classify-Url {
    param([string]$InputUrl, [string]$ResolvedUrl, [string]$ResolveError, [hashtable]$Db, [hashtable]$Blocked)

    $toCheck = @($InputUrl)
    if ($ResolvedUrl) { $toCheck += $ResolvedUrl }

    $iFulls = [System.Collections.Generic.HashSet[string]]::new()
    $iGuids = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($u in $toCheck) {
        $n = Normalize-Url $u
        if ($n) { [void]$iFulls.Add($n) }
        $safeU = if ($u) { $u } else { "" }
        foreach ($g in (Get-Guids $safeU)) { [void]$iGuids.Add($g) }
    }
    $guidsStr = ($iGuids | Sort-Object) -join ","

    $isLoginRequired = Test-LoginRequired -InputUrl $InputUrl -ResolvedUrl $ResolvedUrl -ResolveError $ResolveError

    if ($Blocked) {
        $bHit = $null
        foreach ($f in $iFulls) { if ($Blocked.Full.Contains($f)) { $bHit = $f; break } }
        if ($bHit) { return @{ Status = "blocked"; MatchReason = "blocked"; MatchedValue = $bHit } }
    }

    foreach ($f in $iFulls) { if ($Db.Full.Contains($f)) { return @{ Status = "found"; MatchReason = "full-url"; MatchedValue = $f } } }
    foreach ($g in $iGuids) { if ($Db.Guid.Contains($g)) { return @{ Status = "found"; MatchReason = "guid"; MatchedValue = $g } } }

    if ($isLoginRequired) {
        return @{ Status = "not-testable"; MatchReason = "login-required"; MatchedValue = "" }
    }

    return @{ Status = "missing"; MatchReason = "no-match"; MatchedValue = "" }
}

# ── Main ──────────────────────────────────────────────────────────────────────

# Resolve DB and blocked sources
$dbPath      = Resolve-DataSource -Source $DbFile      -Label "ingested"
$blockedPath = Resolve-DataSource -Source $BlockedFile  -Label "blocked"

if (-not $InputFile) {
    $InputFile = Prompt-ForInputFile
}

$InputFile = $InputFile.Trim().Trim('"')
if (-not (Test-Path $InputFile -PathType Leaf)) {
    throw "Input file not found: $InputFile"
}
$InputFile = (Resolve-Path $InputFile).Path

# Default output paths in a subfolder next to the input file
$inputPath = (Resolve-Path $InputFile).Path
$inputDir  = Split-Path -Parent $inputPath
$inputBase = [System.IO.Path]::GetFileNameWithoutExtension($InputFile)
$stamp     = Get-Date -Format "yyyyMMdd_HHmmss"

if ((-not $OutputTag) -and ($PromptForOutputTag -or -not $PSBoundParameters.ContainsKey('OutputTag'))) {
    $enteredTag = Read-Host "Optional output tag (example: teamA or run42). Press Enter to skip"
    if ($enteredTag) { $OutputTag = $enteredTag }
}

$safeTag = Get-SafeTag -Tag $OutputTag
$suffix = if ($safeTag) { "${safeTag}_${stamp}" } else { $stamp }

if (-not $OutputFile -or -not $AuditOutputFile) {
    $outputRoot = if ([System.IO.Path]::IsPathRooted($OutputFolder)) {
        $OutputFolder
    } else {
        Join-Path $inputDir $OutputFolder
    }

    if (-not (Test-Path $outputRoot -PathType Container)) {
        New-Item -Path $outputRoot -ItemType Directory -Force | Out-Null
    }

    if (-not $OutputFile)      { $OutputFile      = Join-Path $outputRoot "${inputBase}_truly_missing_${suffix}.csv" }
    if (-not $AuditOutputFile) { $AuditOutputFile = Join-Path $outputRoot "${inputBase}_match_audit_${suffix}.csv" }
}

# Load files
Write-Host "Loading input URLs..."
$inputUrls = Read-Urls -Path $InputFile -Sheet $InputSheet -NoHeader:$InputNoHeader -Column $InputColumn
Write-Host "Input URLs: $($inputUrls.Count)"

Write-Host "Loading DB (large file, this may take a minute)..."
$dbUrls = Read-Urls -Path $dbPath -Sheet $DbSheet -Column $DbUrlColumn
Write-Host "DB URLs: $($dbUrls.Count)"
Write-Host "Building DB lookup indexes..."
$dbSets = Build-LookupSets -Urls $dbUrls -Label "DB"

Write-Host "Loading blocked list..."
$blockedUrls = Read-Urls -Path $blockedPath -Sheet $BlockedSheet -Column $BlockedUrlColumn
Write-Host "Blocked URLs loaded: $($blockedUrls.Count)"
Write-Host "Building blocked lookup indexes..."
$blockedSets = Build-LookupSets -Urls $blockedUrls -Label "blocked"

Write-Host "Detected DB GUIDs: $($dbSets.Guid.Count)"

# Resolve redirects (sequential — PS doesn't have easy thread pools in 5.1)
$resolveMap = @{}
$totalInput = [Math]::Max($inputUrls.Count, 1)
if (-not $NoResolveRedirects) {
    Write-Host "Resolving redirects for $($inputUrls.Count) URLs..."
    $ms = $TimeoutSec * 1000
    $i  = 0
    foreach ($url in $inputUrls) {
        $i++
        Write-Progress -Activity "Resolving redirects" -Status "$i / $($inputUrls.Count)" -PercentComplete ([int]($i * 100 / $totalInput))
        if (($i % 50) -eq 0 -or $i -eq $inputUrls.Count) {
            Write-Host "Resolved $i of $($inputUrls.Count) input URLs..."
        }
        $resolveMap[$url] = Resolve-FinalUrl -Url $url -Ms $ms
    }
    Write-Progress -Activity "Resolving redirects" -Completed
} else {
    $i = 0
    foreach ($url in $inputUrls) {
        $i++
        Write-Progress -Activity "Preparing inputs" -Status "$i / $($inputUrls.Count)" -PercentComplete ([int]($i * 100 / $totalInput))
        if (($i % 200) -eq 0 -or $i -eq $inputUrls.Count) {
            Write-Host "Prepared $i of $($inputUrls.Count) input URLs..."
        }
        $resolveMap[$url] = @{ Url = $null; Error = $null }
    }
    Write-Progress -Activity "Preparing inputs" -Completed
}

# Classify
Write-Host "Classifying URLs..."
$allResults = [System.Collections.Generic.List[PSCustomObject]]::new()
$i = 0
foreach ($url in $inputUrls) {
    $i++
    Write-Progress -Activity "Classifying URLs" -Status "$i / $($inputUrls.Count)" -PercentComplete ([int]($i * 100 / $totalInput))
    if (($i % 50) -eq 0 -or $i -eq $inputUrls.Count) {
        Write-Host "Classified $i of $($inputUrls.Count) input URLs..."
    }
    $r   = $resolveMap[$url]
    $cls = Classify-Url -InputUrl $url -ResolvedUrl $r.Url -ResolveError $r.Error -Db $dbSets -Blocked $blockedSets
    $allResults.Add([PSCustomObject]@{
        input_url     = $url
        resolved_url  = if ($r.Url)   { "$($r.Url)" }   else { "" }
        status        = $cls.Status
        match_reason  = $cls.MatchReason
        matched_value = $cls.MatchedValue
        resolve_error = if ($r.Error) { "$($r.Error)" } else { "" }
    })
}
Write-Progress -Activity "Classifying URLs" -Completed

# Write outputs
$missing     = @($allResults | Where-Object { $_.status -eq "missing" })
$blocked_out = @($allResults | Where-Object { $_.status -eq "blocked" })
$notTestable = @($allResults | Where-Object { $_.status -eq "not-testable" })
$found       = @($allResults | Where-Object { $_.status -eq "found" })

$missing  | Export-Csv -Path $OutputFile      -NoTypeInformation -Encoding UTF8
$allResults | Export-Csv -Path $AuditOutputFile -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Found URLs:        $($found.Count)"
Write-Host "Blocked URLs:      $($blocked_out.Count)"
Write-Host "Not testable URLs: $($notTestable.Count)"
Write-Host "Truly missing:     $($missing.Count)"
Write-Host ""
Write-Host "Missing output: $OutputFile"
Write-Host "Audit output:   $AuditOutputFile"
