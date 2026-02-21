# 説明: ZIA Web Log CSV を CommonSecurityLog 形式へ変換し、Logs Ingestion API へ送信する統合スクリプト
# 日付: 2025-11-20
# バージョン: 1.0.0
#
# このスクリプトは以下の手順で動作します:
#   1. CSV を読み込み、Event Time を UTC/ISO 8601 に正規化した上で CommonSecurityLog 互換の JSON を生成します。
#   2. 変換結果をファイル出力し、行数サマリを表示します。
#   3. ユーザーが Y を選択した場合のみ Logs Ingestion API へデータを送信します (N または ConvertOnly 指定時は送信しません)。

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TenantId = '<テナントID を指定してください>',

    [Parameter()]
    [string]$ClientId = '<アプリケーションID を指定してください>',

    [Parameter()]
    [string]$ClientSecret = '<クライアントシークレットを指定してください>',

    [Parameter()]
    [string]$LogsIngestionEndpoint = '<Logs Ingestion API エンドポイントを指定してください>',

    [Parameter()]
    [string]$DcrImmutableId = '<DCRの不変IDを指定してください>',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InputCsvPath,

    [Parameter()]
    [string]$OutputJsonPath = '',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [char]$Delimiter = ',',

    [Parameter()]
    [double]$ChunkSizeMB = 0.9,

    [Parameter()]
    [string]$StreamName = 'Custom-CommonSecurityLog',

    [Parameter()]
    [string]$TargetTable = 'CommonSecurityLog',

    [switch]$ConvertOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$timeZoneOverrides = @{ 'JST' = '+09:00' }
$nullMarkers = @('None', 'N/A')

function ConvertTo-DoubleOrNull {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    $text = $Value.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $style = [System.Globalization.NumberStyles]::Float -bor [System.Globalization.NumberStyles]::AllowThousands
    $parsed = 0.0
    if ([double]::TryParse($text, $style, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function ConvertTo-LongOrNull {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    $text = $Value.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $style = [System.Globalization.NumberStyles]::Integer
    $parsed = 0
    if ([long]::TryParse($text, $style, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
        return $parsed
    }

    $doubleValue = ConvertTo-DoubleOrNull -Value $text
    if ($null -ne $doubleValue) {
        return [long][math]::Round($doubleValue)
    }

    return $null
}

function Get-DomainFromUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    $candidate = $Url.Trim()
    $uri = $null
    $normalized = $candidate
    if ($normalized -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $normalized = "https://$normalized"
    }

    if ([System.Uri]::TryCreate($normalized, [System.UriKind]::Absolute, [ref]$uri)) {
        return $uri.DnsSafeHost
    }

    $noQuery = $candidate.Split('?', 2)[0]
    $hostPart = $noQuery.Trim('/').Split('/')[0]
    if ($hostPart.Contains(':')) {
        return $hostPart.Split(':')[0]
    }
    return $hostPart
}

# CSV -> CommonSecurityLog 変換のメイン関数
function Convert-ZIAWebCsv {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [char]$Delimiter,
        [hashtable]$TimeZoneMap,
        [string[]]$NullKeywords
    )

    if (-not (Test-Path -Path $InputPath -PathType Leaf)) {
        throw "Input file '$InputPath' not found."
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $directory = [System.IO.Path]::GetDirectoryName($InputPath)
        $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
        $OutputPath = Join-Path $directory "$baseName.json"
    }

    $rawLines = Get-Content -Path $InputPath -ErrorAction Stop
    $csvLineCount = $rawLines.Count
    if ($csvLineCount -lt 3) {
        throw 'CSV must contain at least three lines (two header lines plus data).'
    }

    $csvPayload = ($rawLines[2..($rawLines.Count - 1)]) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($csvPayload)) {
        throw 'No data rows found after the header (line 3).'
    }

    $rows = ConvertFrom-Csv -InputObject $csvPayload -Delimiter $Delimiter
    $rowsArray = @($rows)
    $totalRows = ($rowsArray | Measure-Object).Count
    $convertedRows = @()

    foreach ($row in $rowsArray) {
        # 1 行ごとに Event Time を解析し、UTC に正規化
        $timeGenerated = $null

        if ($row.PSObject.Properties.Name -contains 'Event Time') {
            $eventTimeValue = $row.'Event Time'
            $eventTimeTrimmed = if ($eventTimeValue -is [string]) { $eventTimeValue.Trim() } else { $null }

            if ($eventTimeTrimmed -and ($NullKeywords -contains $eventTimeTrimmed)) {
                $row.'Event Time' = $null
            }
            elseif ([string]::IsNullOrWhiteSpace($eventTimeTrimmed)) {
                Write-Warning 'Event Time が空のため、変換せずそのまま出力します。'
            }
            else {
                $eventTimeNormalized = $eventTimeTrimmed
                foreach ($tz in $TimeZoneMap.Keys) {
                    if ($eventTimeNormalized -match "\s$tz$") {
                        $replacement = $TimeZoneMap[$tz]
                        $eventTimeNormalized = $eventTimeNormalized -replace "\s$tz$", " $replacement"
                    }
                }

                $parsedOffset = [datetimeoffset]::MinValue
                if ([datetimeoffset]::TryParse($eventTimeNormalized, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsedOffset)) {
                    $utcInstant = $parsedOffset.ToUniversalTime()
                    $row.'Event Time' = $utcInstant.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
                    $timeGenerated = $utcInstant.UtcDateTime
                }
                elseif ([datetime]::TryParse($eventTimeNormalized, $null, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]([datetime]$parsed = [datetime]::MinValue))) {
                    if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified) {
                        $parsed = [datetime]::SpecifyKind($parsed, [System.DateTimeKind]::Local)
                    }
                    $utcInstant = $parsed.ToUniversalTime()
                    $row.'Event Time' = $utcInstant.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
                    $timeGenerated = $utcInstant.UtcDateTime
                }
                else {
                    Write-Warning "Event Time '$eventTimeValue' を解析できません。元の値を保持します。"
                }
            }
        }

        foreach ($property in $row.PSObject.Properties) {
            # None/N/A などの文字列は null へ統一
            if ($property.Value -is [string]) {
                $trimmed = $property.Value.Trim()
                if ($NullKeywords -contains $trimmed) {
                    $property.Value = $null
                }
                else {
                    $property.Value = $trimmed
                }
            }
        }

        if (-not $timeGenerated -and $row.'Event Time') {
            $fallbackOffset = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse($row.'Event Time', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$fallbackOffset)) {
                $timeGenerated = $fallbackOffset.ToUniversalTime().UtcDateTime
            }
        }

        $domain = Get-DomainFromUrl -Url $row.URL

        # Proxy Latency から簡易的な Severity を推定
        $severityValue = ConvertTo-DoubleOrNull -Value $row.'Proxy Latency (ms)'
        $severityText = switch ($severityValue) {
            { $_ -eq $null } { 'Informational'; break }
            { $_ -lt 100 } { 'Informational'; break }
            { $_ -lt 500 } { 'Low'; break }
            { $_ -lt 1000 } { 'Medium'; break }
            default { 'High' }
        }

        # ReceiptTime は JST 表記、TimeGenerated_CF は UTC ISO 8601 で付与
        $receiptTime = if ($timeGenerated) {
            $timeGenerated.AddHours(9).ToString('yyyy/MM/dd HH:mm:ss.fff', [System.Globalization.CultureInfo]::InvariantCulture) + ' JST'
        }
        elseif ($row.'Event Time') {
            $row.'Event Time'
        }
        else {
            $null
        }

        $timeGeneratedCfValue = if ($timeGenerated) {
            $timeGenerated.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        else {
            $null
        }

        $convertedRows += [pscustomobject][ordered]@{
            DeviceVendor             = 'Zscaler'
            DeviceProduct            = 'NSSWeblog'
            DeviceVersion            = '5.7'
            DeviceEventClassID       = $row.'Policy Action'
            Activity                 = $row.'Policy Action'
            LogSeverity              = $severityText
            DeviceAction             = $row.'Policy Action'
            ApplicationProtocol      = $row.Protocol
            DestinationServiceName   = $row.'Cloud Application Class'
            DestinationHostName      = $domain
            DestinationIP            = $row.'Server IP'
            FileType                 = $row.'Download File Type'
            ReceivedBytes            = ConvertTo-LongOrNull -Value $row.'Received Bytes'
            SentBytes                = ConvertTo-LongOrNull -Value $row.'Sent Bytes'
            EventOutcome             = $row.'Response Code'
            Reason                   = $row.'Policy Action'
            ReceiptTime              = $receiptTime
            TimeGenerated_CF         = $timeGeneratedCfValue
            RequestURL               = $row.URL
            RequestClientApplication = $row.'URL Categorization Method'
            RequestContext           = $row.'Referrer URL'
            RequestMethod            = $row.'Request Method'
            SourceTranslatedAddress  = $row.'Client External IP'
            SourceUserPrivileges     = $row.Location
            SourceIP                 = $row.'Client IP'
            SourceUserName           = $row.User
            DeviceEventCategory      = $row.'URL Category'
            DeviceCustomNumber1      = ConvertTo-LongOrNull -Value $row.'Suspicious Content'
            DeviceCustomNumber1Label = 'riskscore'
            DeviceCustomString1      = $row.Department
            DeviceCustomString2      = $row.'URL Super Category'
            DeviceCustomString3      = $row.'Cloud Application Class'
            DeviceCustomString4      = $row.'Cloud Application'
            DeviceCustomString5      = $row.'Cloud Application'
            DeviceCustomString6      = $row.'Cloud Application'
        }
    }

    $convertedCount = ($convertedRows | Measure-Object).Count
    $json = $convertedRows | ConvertTo-Json -Depth 10
    $json | Set-Content -Path $OutputPath -Encoding UTF8

    Write-Host "`n=== 変換サマリ ===" -ForegroundColor Cyan
    Write-Host ("CSV 行数 (ヘッダー含む): {0}" -f $csvLineCount) -ForegroundColor Yellow
    Write-Host ("データ行数 (ヘッダー除く): {0}" -f $totalRows) -ForegroundColor Yellow
    Write-Host ("処理済み行数: {0}" -f $convertedCount) -ForegroundColor Green
    Write-Host ("出力ファイル: {0}" -f $OutputPath) -ForegroundColor Magenta

    return [pscustomobject]@{
        Data           = $convertedRows
        OutputPath     = $OutputPath
        CsvLineCount   = $csvLineCount
        DataRowCount   = $totalRows
        ConvertedCount = $convertedCount
    }
}

# Logs Ingestion API への送信処理
function Invoke-ZIAWebLogIngestion {
    param(
        [object[]]$Items,
        [double]$ChunkSizeMB,
        [string]$LogsIngestionEndpoint,
        [string]$DcrImmutableId,
        [string]$StreamName,
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$TargetTable
    )

    Write-Host '認証中...' -ForegroundColor Yellow
    $body = @{
        client_id     = $ClientId
        scope         = 'https://monitor.azure.com/.default'
        client_secret = $ClientSecret
        grant_type    = 'client_credentials'
    }

    try {
        $tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Body $body -ContentType 'application/x-www-form-urlencoded'
        $accessToken = $tokenResponse.access_token
        Write-Host '認証成功' -ForegroundColor Green
    }
    catch {
        Write-Host "認証失敗: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }

    $chunkBytes = [math]::Round($ChunkSizeMB * 1MB)
    if ($chunkBytes -le 0) {
        $chunkBytes = 900000
    }

    $current  = New-Object System.Collections.ArrayList
    $currentSize = 0
    $totalSent = 0

    function Send-Chunk {
        param(
            [System.Collections.ArrayList]$ItemsToSend,
            [string]$Endpoint,
            [string]$RuleId,
            [string]$Stream,
            [string]$Token
        )
        if ($ItemsToSend.Count -eq 0) { return }
        $payload = ($ItemsToSend | ConvertTo-Json -Depth 100)
        $uri = "$Endpoint/dataCollectionRules/$RuleId/streams/${Stream}?api-version=2023-01-01"
        $headers = @{
            Authorization = "Bearer $Token"
            'Content-Type' = 'application/json'
        }

        Write-Host "データ送信中... ($($ItemsToSend.Count) 件)" -ForegroundColor Yellow
        try {
            Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $payload | Out-Null
            Write-Host '送信成功' -ForegroundColor Green
        }
        catch {
            Write-Host "送信失敗: $($_.Exception.Message)" -ForegroundColor Red

            if ($_.Exception -is [Microsoft.PowerShell.Commands.HttpResponseException]) {
                Write-Host "HTTP Status Code: $($_.Exception.Response.StatusCode)" -ForegroundColor Red
                Write-Host 'Response Headers:' -ForegroundColor Yellow
                $_.Exception.Response.Headers | ForEach-Object { Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray }
            }

            if ($_.ErrorDetails) {
                Write-Host "Error Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
            }

            if ($_.Exception.Response -and $_.Exception.Response.Content) {
                try {
                    $errorContent = $_.Exception.Response.Content.ReadAsStringAsync().Result
                    Write-Host "Response Content: $errorContent" -ForegroundColor Red
                }
                catch {
                    Write-Host 'レスポンス内容の読み取りに失敗' -ForegroundColor Yellow
                }
            }
            throw
        }
    }

    foreach ($item in $Items) {
        $serialized = ($item | ConvertTo-Json -Depth 100)
        $bytes = [System.Text.Encoding]::UTF8.GetByteCount($serialized)

        if (($currentSize + $bytes) -gt $chunkBytes -and $current.Count -gt 0) {
            Send-Chunk -ItemsToSend $current -Endpoint $LogsIngestionEndpoint -RuleId $DcrImmutableId -Stream $StreamName -Token $accessToken
            $totalSent += $current.Count
            $current.Clear() | Out-Null
            $currentSize = 0
        }

        $null = $current.Add($item)
        $currentSize += $bytes
    }

    if ($current.Count -gt 0) {
        Send-Chunk -ItemsToSend $current -Endpoint $LogsIngestionEndpoint -RuleId $DcrImmutableId -Stream $StreamName -Token $accessToken
        $totalSent += $current.Count
    }

    Write-Host "Logs Ingestion API で $totalSent 件を $TargetTable に送信しました。" -ForegroundColor Cyan
}

$conversionResult = Convert-ZIAWebCsv -InputPath $InputCsvPath -OutputPath $OutputJsonPath -Delimiter $Delimiter -TimeZoneMap $timeZoneOverrides -NullKeywords $nullMarkers

if ($ConvertOnly) {
    Write-Host 'ConvertOnly 指定のため、取り込み処理はスキップしました。' -ForegroundColor Yellow
    return
}

if (-not $conversionResult.Data -or $conversionResult.ConvertedCount -eq 0) {
    Write-Warning '送信対象データが存在しないため取り込みを中止しました。'
    return
}

$ingestDecision = $null
if (-not $ConvertOnly) {
    do {
        # ユーザーに送信可否を確認し、Y/N で分岐
        $response = Read-Host 'Logs Ingestion API にログを送信しますか? (Y/N)'
        if ([string]::IsNullOrWhiteSpace($response)) { continue }
        switch ($response.Trim().ToUpperInvariant()) {
            'Y' { $ingestDecision = $true }
            'N' { $ingestDecision = $false }
            default { Write-Host 'Y か N を入力してください。' -ForegroundColor Yellow }
        }
    } while ($null -eq $ingestDecision)
}

if (-not $ingestDecision) {
    Write-Host 'ユーザー入力により Logs Ingestion API への送信をスキップしました。' -ForegroundColor Yellow
    return
}

Invoke-ZIAWebLogIngestion -Items $conversionResult.Data -ChunkSizeMB $ChunkSizeMB -LogsIngestionEndpoint $LogsIngestionEndpoint -DcrImmutableId $DcrImmutableId -StreamName $StreamName -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -TargetTable $TargetTable
