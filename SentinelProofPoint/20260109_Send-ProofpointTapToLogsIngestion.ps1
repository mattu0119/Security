<#
作成日: 2026-01-08
作成者: Hiroshi Matsumoto

説明:
    Proofpoint TAP の JSON データ（messagesDelivered / messagesBlocked / clicksPermitted / clicksBlocked）を、
    Azure Monitor Logs Ingestion API 経由で DCR の各ストリームに送信し、Log Analytics のカスタムテーブルへ取り込みます。

    認証はサービスプリンシパル（TenantId / ClientId / ClientSecret）を使用します。
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $InputJsonPath,

    [Parameter()]
    [string] $DceEndpoint,

    [Parameter()]
    [string] $DcrImmutableId,

    [Parameter()]
    [string] $TenantId,

    [Parameter()]
    [string] $ClientId,

    [Parameter()]
    [SecureString] $ClientSecret,

    [Parameter()]
    [ValidateRange(1, 10000)]
    [int] $BatchSize = 500
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:DefaultDceEndpoint = 'https://<DCE の情報>.eastus2-1.ingest.monitor.azure.com'
$Script:DefaultDcrImmutableId = '<DCR の ImmutableId>'
$Script:DefaultTenantId = '<Entra テナント ID>'
$Script:DefaultClientId = '<さービスプリンシパルのクライアント ID>'
$Script:DefaultClientSecretEncrypted = '<暗号化されたサービスプリンシパルのクライアントシークレット>'

<# Client Secret の Secure String を作成方法
暗号化文字列の作り方（1回だけ実行して貼り付け）
$ss = Read-Host -AsSecureString "Client secret"
$enc = $ss | ConvertFrom-SecureString
出てきた $enc の文字列を $Script:DefaultClientSecretEncrypted に貼り付け
#>

function Get-MonitorAccessToken {
    param(
        [string] $TenantId,
        [string] $ClientId,
        [SecureString] $ClientSecret
    )

    if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
        throw "Provide -TenantId, -ClientId, and -ClientSecret."
    }

    $secretPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
    )

    try {
        $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -ContentType 'application/x-www-form-urlencoded' -Body @{
            client_id     = $ClientId
            scope         = 'https://monitor.azure.com/.default'
            client_secret = $secretPlain
            grant_type    = 'client_credentials'
        }

        if (-not $tokenResponse.access_token) {
            throw "Token response did not include access_token."
        }

        return $tokenResponse.access_token
    }
    finally {
        Remove-Variable -Name secretPlain -ErrorAction SilentlyContinue
    }
}

function Invoke-LogsIngestionPost {
    param(
        [Parameter(Mandatory)]
        [string] $DceEndpoint,

        [Parameter(Mandatory)]
        [string] $DcrImmutableId,

        [Parameter(Mandatory)]
        [string] $StreamName,

        [Parameter(Mandatory)]
        [object[]] $Records,

        [Parameter(Mandatory)]
        [string] $AccessToken
    )

    $endpoint = $DceEndpoint.TrimEnd('/')
    $uri = "$endpoint/dataCollectionRules/$DcrImmutableId/streams/${StreamName}?api-version=2023-01-01"

    $headers = @{ Authorization = "Bearer $AccessToken" }

    $bodyJson = $Records | ConvertTo-Json -Depth 100 -Compress

    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json' -Body $bodyJson | Out-Null
            return
        }
        catch {
            if ($attempt -ge $maxAttempts) { throw }

            $statusCode = $null
            try { $statusCode = $_.Exception.Response.StatusCode.value__ } catch { }

            # Retry on throttling and transient server errors
            if ($statusCode -in 429, 500, 502, 503, 504) {
                Start-Sleep -Seconds ([Math]::Pow(2, $attempt))
                continue
            }

            throw
        }
    }
}

if (-not (Test-Path -Path $InputJsonPath -PathType Leaf)) {
    throw "Input file not found: $InputJsonPath"
}

if (-not $DceEndpoint) {
    $DceEndpoint = $Script:DefaultDceEndpoint
}
if (-not $DcrImmutableId) {
    $DcrImmutableId = $Script:DefaultDcrImmutableId
}

if ($DceEndpoint -match '<your-dce>' -or $DcrImmutableId -match '<your-dcr-immutableId>') {
    throw "Set $Script:DefaultDceEndpoint and $Script:DefaultDcrImmutableId in the script, or pass -DceEndpoint / -DcrImmutableId."
}

if (-not $TenantId) {
    $TenantId = $Script:DefaultTenantId
}
if (-not $ClientId) {
    $ClientId = $Script:DefaultClientId
}
if (-not $ClientSecret) {
    if ($Script:DefaultClientSecretEncrypted -and ($Script:DefaultClientSecretEncrypted -notmatch '<your-client-secret-encrypted>')) {
        $ClientSecret = ConvertTo-SecureString $Script:DefaultClientSecretEncrypted
    }
}

if ($TenantId -match '<your-tenant-id>' -or $ClientId -match '<your-client-id>') {
    throw "Set $Script:DefaultTenantId and $Script:DefaultClientId in the script, or pass -TenantId / -ClientId."
}
if (-not $ClientSecret) {
    throw "Provide -ClientSecret, or set $Script:DefaultClientSecretEncrypted in the script."
}

$raw = Get-Content -Path $InputJsonPath -Raw
$data = $raw | ConvertFrom-Json -Depth 100

$streamMap = [ordered]@{
    messagesDelivered = 'Custom-ProofPointTAPMessagesDeliveredV2_CL'
    messagesBlocked   = 'Custom-ProofPointTAPMessagesBlockedV2_CL'
    clicksPermitted   = 'Custom-ProofPointTAPClicksPermittedV2_CL'
    clicksBlocked     = 'Custom-ProofPointTAPClicksBlockedV2_CL'
}

$token = Get-MonitorAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

foreach ($key in $streamMap.Keys) {
    $stream = $streamMap[$key]
    $records = $data.$key

    if (-not $records) {
        Write-Host "Skip '$key' (no records)."
        continue
    }

    if ($records -isnot [System.Collections.IEnumerable]) {
        throw "Expected '$key' to be an array."
    }

    $recordsArray = @($records)
    Write-Host "Sending $($recordsArray.Count) record(s) for '$key' -> stream '$stream'"

    for ($i = 0; $i -lt $recordsArray.Count; $i += $BatchSize) {
        $end = [Math]::Min($i + $BatchSize - 1, $recordsArray.Count - 1)
        $batch = $recordsArray[$i..$end]

        Invoke-LogsIngestionPost -DceEndpoint $DceEndpoint -DcrImmutableId $DcrImmutableId -StreamName $stream -Records $batch -AccessToken $token
        Write-Host "  Posted records $i..$end"
    }
}

Write-Host 'Done.'
