# 説明: ZIA Firewall Log CSV を CommonSecurityLog 形式へ変換し、Logs Ingestion API へ送信する統合スクリプト
# 日付: 2025-12-11
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
$nullMarkers = @('None', 'N/A', 'NA', 'null', 'NULL', '(null)')

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

function Normalize-ZIATimestamp {
    param(
        [Parameter(Mandatory = $true)][psobject]$Row,
        [Parameter(Mandatory = $true)][string]$ColumnName,
        [hashtable]$TimeZoneMap,
        [string[]]$NullKeywords
    )

    if (-not ($Row.PSObject.Properties.Name -contains $ColumnName)) {
        return $null
    }

    $rawValue = $Row.$ColumnName
    if ($rawValue -is [string]) {
        $rawValue = $rawValue.Trim()
    }

    if ($rawValue -is [string]) {
        if ($NullKeywords -contains $rawValue) {
            $Row.$ColumnName = $null
            return $null
        }

        if ([string]::IsNullOrWhiteSpace($rawValue)) {
            return $null
        }
    }
    elseif ($null -eq $rawValue) {
        return $null
    }

    $normalized = if ($rawValue -is [string]) { $rawValue } else { $rawValue.ToString() }
    foreach ($tz in $TimeZoneMap.Keys) {
        if ($normalized -match "\s$tz$") {
            $normalized = $normalized -replace "\s$tz$", " $($TimeZoneMap[$tz])"
        }
    }

    $parsedOffset = [datetimeoffset]::MinValue
    if ([datetimeoffset]::TryParse($normalized, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsedOffset)) {
        $utcInstant = $parsedOffset.ToUniversalTime()
        $Row.$ColumnName = $utcInstant.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        return $utcInstant.UtcDateTime
    }

    $parsedDate = [datetime]::MinValue
    if ([datetime]::TryParse($normalized, $null, [System.Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsedDate)) {
        if ($parsedDate.Kind -eq [System.DateTimeKind]::Unspecified) {
            $parsedDate = [datetime]::SpecifyKind($parsedDate, [System.DateTimeKind]::Local)
        }
        $utcInstant = $parsedDate.ToUniversalTime()
        $Row.$ColumnName = $utcInstant.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        return $utcInstant
    }

    Write-Warning "[$ColumnName] '$rawValue' を解析できません。元の値を保持します。"
    return $null
}

function Convert-ZIAFirewallCsv {
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
        $eventTimeUtc = Normalize-ZIATimestamp -Row $row -ColumnName 'Event Time' -TimeZoneMap $TimeZoneMap -NullKeywords $NullKeywords
        $loggedTimeUtc = Normalize-ZIATimestamp -Row $row -ColumnName 'Logged Time' -TimeZoneMap $TimeZoneMap -NullKeywords $NullKeywords

        foreach ($property in $row.PSObject.Properties) {
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

        $timeGenerated = $eventTimeUtc
        if (-not $timeGenerated -and $row.'Event Time') {
            $fallbackOffset = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse($row.'Event Time', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$fallbackOffset)) {
                $timeGenerated = $fallbackOffset.ToUniversalTime().UtcDateTime
            }
        }

        $receiptTime = if ($timeGenerated) {
            $timeGenerated.AddHours(9).ToString('yyyy/MM/dd HH:mm:ss.fff', [System.Globalization.CultureInfo]::InvariantCulture) + ' JST'
        }
        elseif ($loggedTimeUtc) {
            $loggedTimeUtc.AddHours(9).ToString('yyyy/MM/dd HH:mm:ss.fff', [System.Globalization.CultureInfo]::InvariantCulture) + ' JST'
        }
        elseif ($row.'Event Time') {
            $row.'Event Time'
        }
        elseif ($row.'Logged Time') {
            $row.'Logged Time'
        }
        else {
            $null
        }

        $timeGeneratedCfValue = if ($timeGenerated) {
            $timeGenerated.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        elseif ($loggedTimeUtc) {
            $loggedTimeUtc.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        else {
            $null
        }

        $sessionDurationRaw = ConvertTo-LongOrNull -Value $row.'Session Duration'
        $sessionDuration = if ($sessionDurationRaw -ne $null) { [long]($sessionDurationRaw * 1000) } else { $null }
        $sourcePort = ConvertTo-LongOrNull -Value $row.'Client Source Port'
        $destinationPort = ConvertTo-LongOrNull -Value $row.'Client Destination Port'
        $serverDestinationPort = ConvertTo-LongOrNull -Value $row.'Server Destination Port'
        $sourceTranslatedPort = ConvertTo-LongOrNull -Value $row.'ZIA Source Port'
        $serverSourcePort = ConvertTo-LongOrNull -Value $row.'Server Source Port'
        $inboundBytes = ConvertTo-LongOrNull -Value $row.'Inbound Bytes'
        $outboundBytes = ConvertTo-LongOrNull -Value $row.'Outbound Bytes'
        $ipsCustomSignature = ConvertTo-LongOrNull -Value $row.'IPS Custom Signature'
        $bypassedSession = ConvertTo-LongOrNull -Value $row.'Bypassed Session'
        $recordId = ConvertTo-LongOrNull -Value $row.'External Device ID'

        $extensions = [ordered]@{}
        if (-not [string]::IsNullOrWhiteSpace($row.'NAT Action')) { $extensions['NATAction'] = $row.'NAT Action' }
        if (-not [string]::IsNullOrWhiteSpace($row.'DNAT Rule Name')) { $extensions['DNATRuleName'] = $row.'DNAT Rule Name' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Traffic Forwarding')) { $extensions['TrafficForwarding'] = $row.'Traffic Forwarding' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Aggregated Session')) { $extensions['AggregatedSession'] = $row.'Aggregated Session' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Gateway Name')) { $extensions['GatewayName'] = $row.'Gateway Name' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Flow Type')) { $extensions['FlowType'] = $row.'Flow Type' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Bypassed Session')) { $extensions['BypassedSession'] = $row.'Bypassed Session' }
        if (-not [string]::IsNullOrWhiteSpace($row.Capture)) { $extensions['CaptureId'] = $row.Capture }
        if (-not [string]::IsNullOrWhiteSpace($row.'Extranet Resource')) { $extensions['ExtranetResource'] = $row.'Extranet Resource' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Application Segment')) { $extensions['ApplicationSegment'] = $row.'Application Segment' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Forwarding Rule')) { $extensions['ForwardingRule'] = $row.'Forwarding Rule' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Forwarding Method')) { $extensions['ForwardingMethod'] = $row.'Forwarding Method' }
        if (-not [string]::IsNullOrWhiteSpace($row.'ZIA Source IP')) { $extensions['ZIASourceIP'] = $row.'ZIA Source IP' }
        if (-not [string]::IsNullOrWhiteSpace($row.'ZIA Source Port')) { $extensions['ZIASourcePort'] = $row.'ZIA Source Port' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Gateway Destination IP')) { $extensions['GatewayDestinationIP'] = $row.'Gateway Destination IP' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Gateway Destination Port')) { $extensions['GatewayDestinationPort'] = $row.'Gateway Destination Port' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Server Source IP')) { $extensions['ServerSourceIP'] = $row.'Server Source IP' }
        if ($serverSourcePort -ne $null) { $extensions['ServerSourcePort'] = $serverSourcePort }
        if (-not [string]::IsNullOrWhiteSpace($row.'Server IP Category')) { $extensions['ServerIPCategory'] = $row.'Server IP Category' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Dest Country')) { $extensions['DestCountry'] = $row.'Dest Country' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Source Country')) { $extensions['SourceCountry'] = $row.'Source Country' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Network Application Category')) { $extensions['NetworkApplicationCategory'] = $row.'Network Application Category' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Zscaler Client Connector Tunnel Version')) { $extensions['ZCCTunnelVersion'] = $row.'Zscaler Client Connector Tunnel Version' }
        if (-not [string]::IsNullOrWhiteSpace($row.'ZIA Gateway Protocol')) { $extensions['ZIAGatewayProtocol'] = $row.'ZIA Gateway Protocol' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Data Center')) { $extensions['DataCenter'] = $row.'Data Center' }
        if (-not [string]::IsNullOrWhiteSpace($row.'MT GRE IP')) { $extensions['MTGREIP'] = $row.'MT GRE IP' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Bypassed Session Event Time')) { $extensions['BypassedSessionEventTime'] = $row.'Bypassed Session Event Time' }
        if (-not [string]::IsNullOrWhiteSpace($row.'IPS Rule Name')) { $extensions['IPSRuleName'] = $row.'IPS Rule Name' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Application Service')) { $extensions['ApplicationService'] = $row.'Application Service' }
        if ($ipsCustomSignature -ne $null) { $extensions['IPSCustomSignature'] = $ipsCustomSignature }
        if (-not [string]::IsNullOrWhiteSpace($row.'ZIA Gateway Protocol')) { $extensions['ZIAGatewayProtocol'] = $row.'ZIA Gateway Protocol' }
        if ($bypassedSession -ne $null) { $extensions['BypassedSession'] = $bypassedSession }
        if (-not [string]::IsNullOrWhiteSpace($row.'Bypassed Session Event Time')) { $extensions['BypassedSessionEventTime'] = $row.'Bypassed Session Event Time' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Flow Type')) { $extensions['FlowType'] = $row.'Flow Type' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Forwarding Rule')) { $extensions['ForwardingRule'] = $row.'Forwarding Rule' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Forwarding Method')) { $extensions['ForwardingMethod'] = $row.'Forwarding Method' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Data Center')) { $extensions['DataCenter'] = $row.'Data Center' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Gateway Destination IP')) { $extensions['GatewayDestinationIP'] = $row.'Gateway Destination IP' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Gateway Destination Port')) { $extensions['GatewayDestinationPort'] = $row.'Gateway Destination Port' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Gateway Name')) { $extensions['GatewayName'] = $row.'Gateway Name' }
        if (-not [string]::IsNullOrWhiteSpace($row.'ZIA Source IP')) { $extensions['ZIASourceIP'] = $row.'ZIA Source IP' }
        if ($sourceTranslatedPort -ne $null) { $extensions['ZIASourcePort'] = $sourceTranslatedPort }
        if (-not [string]::IsNullOrWhiteSpace($row.'Zscaler Client Connector Tunnel Version')) { $extensions['ZCCTunnelVersion'] = $row.'Zscaler Client Connector Tunnel Version' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Server IP Category')) { $extensions['ServerIPCategory'] = $row.'Server IP Category' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Dest Country')) { $extensions['DestCountry'] = $row.'Dest Country' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Source Country')) { $extensions['SourceCountry'] = $row.'Source Country' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Data Center')) { $extensions['DataCenter'] = $row.'Data Center' }
        if (-not [string]::IsNullOrWhiteSpace($row.'MT GRE IP')) { $extensions['MTGREIP'] = $row.'MT GRE IP' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Capture')) { $extensions['CaptureId'] = $row.'Capture' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Application Segment')) { $extensions['ApplicationSegment'] = $row.'Application Segment' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Extranet Resource')) { $extensions['ExtranetResource'] = $row.'Extranet Resource' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Traffic Forwarding')) { $extensions['TrafficForwarding'] = $row.'Traffic Forwarding' }
        if (-not [string]::IsNullOrWhiteSpace($row.'Aggregated Session')) { $extensions['AggregatedSession'] = $row.'Aggregated Session' }
        if ($recordId -ne $null) { $extensions['RecordId'] = $recordId }

        $additionalExtensions = if ($extensions.Count -gt 0) {
            ($extensions.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ';'
        } else {
            $null
        }

        $messageParts = @(@($row.Action, $row.'Network Application', $row.'Rule Name') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $message = if ($messageParts.Count -gt 0) { [string]::Join(' | ', $messageParts) } else { $null }

        $convertedRows += [pscustomobject][ordered]@{
            DeviceVendor              = 'Zscaler'
            DeviceProduct             = 'NSSFWlog'
            DeviceVersion             = '5.7'
            DeviceEventClassID        = $row.Action
            Activity                  = $row.'Rule Name'
            DeviceAction              = $row.Action
            DestinationTranslatedAddress = $row.'Server Destination IP'
            DestinationTranslatedPort = $serverDestinationPort
            DestinationPort           = $destinationPort
            DestinationIP             = $row.'Client Destination IP'
            SentBytes                 = $outboundBytes
            Protocol                  = $row.'Network Application'
            Reason                    = $row.'Rule Name'
            SourceTranslatedAddress   = $row.'Client Tunnel IP'
            SourceUserPrivileges      = $row.Location
            SourcePort                = $sourcePort
            SourceIP                  = $row.'Client Source IP'
            SourceUserName            = $row.User
            DeviceCustomString1       = $row.Department
            DeviceCustomString2       = $row.'Network Service'
            DeviceCustomString3       = $row.'Network Protocol'
            FlexString1               = $row.'Server IP Category'
            ReceiptTime               = $receiptTime
            TimeGenerated_CF          = $timeGeneratedCfValue
            # ApplicationProtocol       = $row.'Network Service'
            # SourceTranslatedPort      = $sourceTranslatedPort
            # DestinationHostName       = $row.'Client Destination Name'
            # DestinationServiceName    = $row.'Network Application'
            # DeviceTranslatedAddress   = $row.'Server Source IP'        
            # DeviceAddress             = $row.'ZIA Source IP'
            # DeviceName                = $row.'Device Hostname'
            # ReceivedBytes             = $inboundBytes
            # EventOutcome              = $row.Action
            # DeviceEventCategory       = $row.'Network Application Category'
            # DeviceExternalId          = $row.'External Device ID'
            # DeviceCustomString1Label  = 'dept'
            # DeviceCustomString2Label  = 'nwService'
            # DeviceCustomString3Label  = 'nwApp'
            # DeviceCustomString4       = $row.'Aggregated Session'
            # DeviceCustomString4Label  = 'aggregated'
            # DeviceCustomString5       = $row.'Advanced Threat Category'
            # DeviceCustomString5Label  = 'threatcat'
            # DeviceCustomString6       = $row.'Threat Name'
            # DeviceCustomString6Label  = 'threatname'
            # DeviceCustomNumber1       = $sessionDuration
            # DeviceCustomNumber1Label  = 'durationms'
            # DestinationUserName       = $row.'DNAT Destination Name'
            # AdditionalExtensions      = $additionalExtensions
            # Message                   = $message
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

function Invoke-ZIAFirewallLogIngestion {
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

$conversionResult = Convert-ZIAFirewallCsv -InputPath $InputCsvPath -OutputPath $OutputJsonPath -Delimiter $Delimiter -TimeZoneMap $timeZoneOverrides -NullKeywords $nullMarkers

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

Invoke-ZIAFirewallLogIngestion -Items $conversionResult.Data -ChunkSizeMB $ChunkSizeMB -LogsIngestionEndpoint $LogsIngestionEndpoint -DcrImmutableId $DcrImmutableId -StreamName $StreamName -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -TargetTable $TargetTable
