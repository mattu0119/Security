<#
作成日: 2026-02-13
作成者: Hiroshi Matsumoto
説明: Proofpoint POD を Logs Ingestion に送信するスクリプト
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $false)]
    [string]$DceEndpoint,

    [Parameter(Mandatory = $false)]
    [string]$DcrImmutableId,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [ValidateSet("PodMessage", "PodMailLog")]
    [string]$LogType,

    [Parameter(Mandatory = $false)]
    [string]$SkippedOutputPath,

    [Parameter(Mandatory = $false)]
    [bool]$PromptOnSkip = $true,

    [int]$MaxBatchBytes = 900000,
    [int]$MaxBatchCount = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Script:DefaultDceEndpoint = 'https://<DCE の情報>.eastus2-1.ingest.monitor.azure.com'
$Script:DefaultDcrImmutableId = '<DCR の ImmutableId>'
$Script:DefaultTenantId = '<Entra テナント ID>'
$Script:DefaultClientId = '<サービスプリンシパルのクライアント ID>'
$Script:DefaultClientSecretEncrypted = '<暗号化されたサービスプリンシパルのクライアントシークレット>'

<# Client Secret の Secure String を作成方法
暗号化文字列の作り方（1回だけ実行して貼り付け）
$ss = Read-Host -AsSecureString "Client secret"
$enc = $ss | ConvertFrom-SecureString
出てきた $enc の文字列を $Script:DefaultClientSecretEncrypted に貼り付け
#>

function Get-MonitorAccessToken {
    param(
        [Parameter(Mandatory = $true)][string]$TenantId,
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][SecureString]$ClientSecret
    )

    $secretPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
    )

    try {
        $body = @{ 
            client_id     = $ClientId
            client_secret = $secretPlain
            scope         = "https://monitor.azure.com/.default"
            grant_type    = "client_credentials"
        }

        $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $body
        return $tokenResponse.access_token
    } finally {
        Remove-Variable -Name secretPlain -ErrorAction SilentlyContinue
    }
}

function Invoke-LogsIngestionPost {
    param(
        [Parameter(Mandatory = $true)][string]$DceEndpoint,
        [Parameter(Mandatory = $true)][string]$DcrImmutableId,
        [Parameter(Mandatory = $true)][string]$StreamName,
        [Parameter(Mandatory = $true)][string]$AccessToken,
        [Parameter(Mandatory = $true)][string]$Body
    )

    $dceBase = $DceEndpoint.TrimEnd("/")
    $uri = "$dceBase/dataCollectionRules/$DcrImmutableId/streams/${StreamName}?api-version=2021-11-01-preview"

    $headers = @{ Authorization = "Bearer $AccessToken" }

    $maxRetries = 3
    for ($attempt = 0; $attempt -lt $maxRetries; $attempt++) {
        try {
            Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $Body -ContentType "application/json" | Out-Null
            return
        } catch {
            if ($attempt -ge ($maxRetries - 1)) {
                throw
            }
            Start-Sleep -Seconds ([math]::Pow(2, $attempt))
        }
    }
}

function Convert-LineToObject {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return [pscustomobject]@{ Obj = $null; ReasonCode = "EmptyLine"; ReasonDetail = $null }
    }

    $idx = $Line.IndexOf("{")
    if ($idx -lt 0) {
        return [pscustomobject]@{ Obj = $null; ReasonCode = "NoJsonStart"; ReasonDetail = $null }
    }

    $json = $Line.Substring($idx)
    if ($json.StartsWith("{{")) {
        $json = $json.Substring(1)
    }
    try {
        $obj = $json | ConvertFrom-Json -Depth 100
        return [pscustomobject]@{ Obj = $obj; ReasonCode = $null; ReasonDetail = $null }
    } catch {
        $msg = $_.Exception.Message
        return [pscustomobject]@{ Obj = $null; ReasonCode = "JsonParseError"; ReasonDetail = $msg }
    }
}

function Get-SkipReasonText {
    param(
        [Parameter(Mandatory = $false)][string]$ReasonCode,
        [Parameter(Mandatory = $false)][string]$ReasonDetail
    )

    switch ($ReasonCode) {
        "EmptyLine" { return "空行のためスキップ" }
        "NoJsonStart" { return "JSON開始文字({)が見つからないためスキップ" }
        "JsonParseError" { return "JSON解析に失敗したためスキップ" }
        default { return "不明な理由でスキップ" }
    }
}

function Get-PropValue {
    param(
        [Parameter(Mandatory = $true)]$Obj,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $prop = $Obj.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $null
    }

    return $prop.Value
}

function Map-Record {
    param(
        [Parameter(Mandatory = $true)]$Obj,
        [Parameter(Mandatory = $true)][string]$LogType
    )

    switch ($LogType) {
        "PodMailLog" {
            return [ordered]@{
                id       = Get-PropValue -Obj $Obj -Name "id"
                data     = Get-PropValue -Obj $Obj -Name "data"
                ts       = Get-PropValue -Obj $Obj -Name "ts"
                metadata = Get-PropValue -Obj $Obj -Name "metadata"
                pps      = Get-PropValue -Obj $Obj -Name "pps"
                sm       = Get-PropValue -Obj $Obj -Name "sm"
                tls      = Get-PropValue -Obj $Obj -Name "tls"
            }
        }
        "PodMessage" {
            return [ordered]@{
                guid     = Get-PropValue -Obj $Obj -Name "guid"
                ts       = Get-PropValue -Obj $Obj -Name "ts"
                connection = Get-PropValue -Obj $Obj -Name "connection"
                envelope = Get-PropValue -Obj $Obj -Name "envelope"
                msg      = Get-PropValue -Obj $Obj -Name "msg"
                pps      = Get-PropValue -Obj $Obj -Name "pps"
                metadata = Get-PropValue -Obj $Obj -Name "metadata"
                filter   = Get-PropValue -Obj $Obj -Name "filter"
                msgParts = Get-PropValue -Obj $Obj -Name "msgParts"
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "InputPath not found: $InputPath"
}

$inputItem = Get-Item -LiteralPath $InputPath
if ($inputItem.PSIsContainer) {
    throw "InputPath must be a file, not a directory: $InputPath"
}

if (-not $LogType) {
    $lowerName = $inputItem.Name.ToLowerInvariant()
    if ($lowerName -match "maillog") {
        $LogType = "PodMailLog"
    } elseif ($lowerName -match "message") {
        $LogType = "PodMessage"
    } else {
        throw "LogType not provided and could not be detected from file name. Use -LogType PodMessage or PodMailLog."
    }
}

$streamName = switch ($LogType) {
    "PodMailLog" { "Custom-ProofpointPodMailLog" }
    "PodMessage" { "Custom-ProofpointPodMessage" }
}

if (-not $DceEndpoint) {
    $DceEndpoint = $Script:DefaultDceEndpoint
}
if (-not $DcrImmutableId) {
    $DcrImmutableId = $Script:DefaultDcrImmutableId
}
if ($DceEndpoint -match "<DCE の情報>" -or $DcrImmutableId -match "<DCR の ImmutableId>") {
    throw "Set $Script:DefaultDceEndpoint and $Script:DefaultDcrImmutableId in the script, or pass -DceEndpoint / -DcrImmutableId."
}

if (-not $TenantId) {
    $TenantId = $Script:DefaultTenantId
}
if (-not $ClientId) {
    $ClientId = $Script:DefaultClientId
}
if (-not $ClientSecret) {
    if ($Script:DefaultClientSecretEncrypted -and ($Script:DefaultClientSecretEncrypted -notmatch "<encrypted-service-principal-client-secret>")) {
        $ClientSecret = ConvertTo-SecureString $Script:DefaultClientSecretEncrypted
    }
}
if ($TenantId -match "<Entra テナント ID>" -or $ClientId -match "<サービスプリンシパルのクライアント ID>") {
    throw "Set $Script:DefaultTenantId and $Script:DefaultClientId in the script, or pass -TenantId / -ClientId."
}
if (-not $ClientSecret) {
    throw "Provide -ClientSecret, or set $Script:DefaultClientSecretEncrypted in the script."
}

$accessToken = Get-MonitorAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

$batch = New-Object System.Collections.Generic.List[object]
$batchBytes = 0
$totalParsed = 0
$totalSent = 0
$totalSkipped = 0

$skippedOutputActual = $null
$skippedTempPath = $null
$lineNumber = 0

if ($SkippedOutputPath) {
    $skippedDir = Split-Path -Parent $SkippedOutputPath
    if ($skippedDir -and -not (Test-Path -LiteralPath $skippedDir)) {
        New-Item -ItemType Directory -Path $skippedDir | Out-Null
    }
    $skippedOutputActual = $SkippedOutputPath
    Set-Content -LiteralPath $skippedOutputActual -Value "" -Encoding UTF8
} elseif ($PromptOnSkip) {
    $skippedTempPath = Join-Path $env:TEMP ("ProofpointPodSkipped_{0}.log" -f ([guid]::NewGuid().ToString("N")))
    $skippedOutputActual = $skippedTempPath
    Set-Content -LiteralPath $skippedOutputActual -Value "" -Encoding UTF8
}

Get-Content -LiteralPath $InputPath -ReadCount 1000 | ForEach-Object {
    foreach ($line in $_) {
        $lineNumber++
        $result = Convert-LineToObject -Line $line
        if (-not $result.Obj) {
            $totalSkipped++
            if ($skippedOutputActual) {
                $reasonText = Get-SkipReasonText -ReasonCode $result.ReasonCode -ReasonDetail $result.ReasonDetail
                Add-Content -LiteralPath $skippedOutputActual -Value ("Line={0}`tReason={1}`t{2}" -f $lineNumber, $reasonText, $line) -Encoding UTF8
            }
            continue
        }

        $obj = $result.Obj

        $record = Map-Record -Obj $obj -LogType $LogType
        $batch.Add($record) | Out-Null
        $totalParsed++

        $recordJson = ($record | ConvertTo-Json -Depth 100)
        $batchBytes += $recordJson.Length

        if ($batch.Count -ge $MaxBatchCount -or $batchBytes -ge $MaxBatchBytes) {
            $payload = $batch | ConvertTo-Json -Depth 100
            Invoke-LogsIngestionPost -DceEndpoint $DceEndpoint -DcrImmutableId $DcrImmutableId -StreamName $streamName -AccessToken $accessToken -Body $payload
            $totalSent += $batch.Count
            $batch.Clear()
            $batchBytes = 0
        }
    }
}

if ($batch.Count -gt 0) {
    $payload = $batch | ConvertTo-Json -Depth 100
    Invoke-LogsIngestionPost -DceEndpoint $DceEndpoint -DcrImmutableId $DcrImmutableId -StreamName $streamName -AccessToken $accessToken -Body $payload
    $totalSent += $batch.Count
}

if ($totalSkipped -gt 0) {
    Write-Host "Completed with skipped records. " -ForegroundColor Yellow -NoNewline
} else {
    Write-Host "Completed. " -ForegroundColor Green -NoNewline
}
Write-Host "Parsed=" -ForegroundColor Cyan -NoNewline
Write-Host $totalParsed -ForegroundColor White -NoNewline
Write-Host " Sent=" -ForegroundColor Cyan -NoNewline
Write-Host $totalSent -ForegroundColor White -NoNewline
Write-Host " Skipped=" -ForegroundColor Cyan -NoNewline
Write-Host $totalSkipped -ForegroundColor White -NoNewline
Write-Host " LogType=" -ForegroundColor Cyan -NoNewline
Write-Host $LogType -ForegroundColor White -NoNewline
Write-Host " Stream=" -ForegroundColor Cyan -NoNewline
Write-Host $streamName -ForegroundColor White

if ($PromptOnSkip -and $totalSkipped -gt 0 -and -not $SkippedOutputPath) {
    $saveChoice = Read-Host "Skipped logs detected. Save to file? (Y/N)"
    if ($saveChoice -match '^[Yy]') {
        $defaultOut = Join-Path (Get-Location) ("skipped_{0}.log" -f $LogType)
        $outPath = Read-Host "Output path (Enter for $defaultOut)"
        if (-not $outPath) {
            $outPath = $defaultOut
        }
        $outDir = Split-Path -Parent $outPath
        if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
            New-Item -ItemType Directory -Path $outDir | Out-Null
        }
        Move-Item -LiteralPath $skippedTempPath -Destination $outPath -Force
    } else {
        if ($skippedTempPath -and (Test-Path -LiteralPath $skippedTempPath)) {
            Remove-Item -LiteralPath $skippedTempPath -Force
        }
    }
} elseif ($skippedTempPath -and (Test-Path -LiteralPath $skippedTempPath)) {
    Remove-Item -LiteralPath $skippedTempPath -Force
}

