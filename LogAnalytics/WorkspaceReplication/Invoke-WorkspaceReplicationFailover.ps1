<#
作成日: 2026-02-27
作成者: Hiroshi Matsumoto

.SYNOPSIS
    Log Analytics ワークスペースレプリケーションを有効化するスクリプト

.DESCRIPTION
    Azure Monitor Log Analytics ワークスペースのレプリケーションを有効化します。
    REST API (api-version: 2025-02-01) を使用し、Invoke-AzRestMethod で呼び出します。

.NOTES
    前提条件:
    - Az PowerShell モジュールがインストール済みであること
    - Microsoft.OperationalInsights/workspaces/write 権限があること
    - Microsoft.Insights/dataCollectionEndpoints/write 権限があること
    - プライマリとセカンダリは同じリージョングループ内であること
    - レプリケーション有効化前に取り込まれたログはセカンダリにコピーされません
    - Auxiliary テーブルを使用しているワークスペースでは使用しないでください

.LINK
    https://learn.microsoft.com/en-us/azure/azure-monitor/logs/workspace-replication
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

    [Parameter(Mandatory = $true)]
    [string]$PrimaryRegion,

    [Parameter(Mandatory = $true)]
    [string]$SecondaryRegion,

    [Parameter()]
    [int]$PollingIntervalSeconds = 30,

    [Parameter()]
    [int]$TimeoutMinutes = 60,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$apiVersion = "2025-02-01"

function Get-WorkspaceInfo {
    param(
        [Parameter(Mandatory = $true)][string]$SubscriptionId,
        [Parameter(Mandatory = $true)][string]$ResourceGroupName,
        [Parameter(Mandatory = $true)][string]$WorkspaceName,
        [Parameter(Mandatory = $true)][string]$ApiVersion
    )

    $uri = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/${WorkspaceName}?api-version=$ApiVersion"
    $response = Invoke-AzRestMethod -Method GET -Path $uri

    if ($response.StatusCode -ne 200) {
        throw "ワークスペースの取得に失敗しました。StatusCode: $($response.StatusCode)`n$($response.Content)"
    }

    return ($response.Content | ConvertFrom-Json)
}

function Test-HasReplicationProperty {
    param(
        [Parameter(Mandatory = $true)]$WorkspaceInfo
    )
    return ($WorkspaceInfo.properties.PSObject.Properties.Name -contains "replication")
}

function Write-WorkspaceStatus {
    param(
        [Parameter(Mandatory = $true)]$WorkspaceInfo
    )

    Write-Host "ワークスペース名        : $($WorkspaceInfo.name)"
    Write-Host "リージョン              : $($WorkspaceInfo.location)"
    Write-Host "provisioningState      : $($WorkspaceInfo.properties.provisioningState)"

    $hasReplication = Test-HasReplicationProperty -WorkspaceInfo $WorkspaceInfo
    if ($hasReplication) {
        Write-Host "replication.enabled    : $($WorkspaceInfo.properties.replication.enabled)"
        Write-Host "replication.location   : $($WorkspaceInfo.properties.replication.location)"
    } else {
        Write-Host "replication            : (未設定)" -ForegroundColor Yellow
    }
}

# -------------------------------------------------------
# 1. Azure への接続確認
# -------------------------------------------------------
Write-Host "=== Azure 接続を確認しています ===" -ForegroundColor Cyan
try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Azure にログインしていません。Connect-AzAccount を実行します..." -ForegroundColor Yellow
        Connect-AzAccount | Out-Null
    }
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    Write-Host "サブスクリプション: $SubscriptionId" -ForegroundColor Green
}
catch {
    Write-Error "Azure への接続に失敗しました: $_"
    exit 1
}

# -------------------------------------------------------
# 2. 現在のワークスペース状態を確認
# -------------------------------------------------------
Write-Host "`n=== ワークスペースの現在の状態を確認しています ===" -ForegroundColor Cyan

try {
    $workspaceInfo = Get-WorkspaceInfo -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -ApiVersion $apiVersion
    Write-WorkspaceStatus -WorkspaceInfo $workspaceInfo

    # 既存のレプリケーション設定を確認（プロパティ存在チェック付き）
    $hasReplication = Test-HasReplicationProperty -WorkspaceInfo $workspaceInfo
    if ($hasReplication -and $workspaceInfo.properties.replication.enabled -eq $true) {
        Write-Host "`nレプリケーション  : 既に有効 (セカンダリ: $($workspaceInfo.properties.replication.location))" -ForegroundColor Yellow
        $continueChoice = Read-Host "レプリケーション設定を更新しますか？ (y/N)"
        if ($continueChoice -ne "y") {
            Write-Host "処理を中止しました。" -ForegroundColor Yellow
            exit 0
        }
    }
    elseif (-not $hasReplication) {
        Write-Host "レプリケーション  : 未設定（これから有効化します）" -ForegroundColor Yellow
    }
}
catch {
    Write-Error "ワークスペースの確認に失敗しました: $_"
    exit 1
}

# -------------------------------------------------------
# 3. レプリケーションを有効化
# -------------------------------------------------------
Write-Host "`n=== レプリケーションを有効化しています ===" -ForegroundColor Cyan
Write-Host "プライマリリージョン  : $PrimaryRegion"
Write-Host "セカンダリリージョン  : $SecondaryRegion"

# 有効化前の最終確認（-Force 指定時はスキップ）
if (-not $Force) {
    Write-Host "`nこれからレプリケーション有効化 API を実行します。" -ForegroundColor Yellow
    Write-Host "  SubscriptionId : $SubscriptionId"
    Write-Host "  ResourceGroup  : $ResourceGroupName"
    Write-Host "  WorkspaceName  : $WorkspaceName"
    Write-Host "  PrimaryRegion  : $PrimaryRegion"
    Write-Host "  SecondaryRegion: $SecondaryRegion"

    $confirm = Read-Host "この内容で実行しますか？ (y/N)"
    if ($confirm -notmatch '^(?i:y|yes)$') {
        Write-Host "処理を中止しました。" -ForegroundColor Yellow
        exit 0
    }
}

$putUri = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/${WorkspaceName}?api-version=$apiVersion"

$body = @{
    location   = $PrimaryRegion
    properties = @{
        replication = @{
            enabled  = $true
            location = $SecondaryRegion
        }
    }
} | ConvertTo-Json -Depth 5

Write-Host "`nリクエストボディ:" -ForegroundColor Gray
Write-Host $body -ForegroundColor Gray

try {
    $putResponse = Invoke-AzRestMethod -Method PUT -Path $putUri -Payload $body
    
    if ($putResponse.StatusCode -notin @(200, 201)) {
        Write-Error "レプリケーションの有効化に失敗しました。StatusCode: $($putResponse.StatusCode)`n$($putResponse.Content)"
        exit 1
    }

    Write-Host "`nAPI 呼び出し成功 (StatusCode: $($putResponse.StatusCode))" -ForegroundColor Green
}
catch {
    Write-Error "レプリケーション有効化の API 呼び出しに失敗しました: $_"
    exit 1
}

# -------------------------------------------------------
# 4. プロビジョニング状態をポーリングして完了を待機
# -------------------------------------------------------
Write-Host "`n=== プロビジョニング完了を待機しています ===" -ForegroundColor Cyan
Write-Host "ポーリング間隔: ${PollingIntervalSeconds}秒 / タイムアウト: ${TimeoutMinutes}分"

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$timeoutMs = $TimeoutMinutes * 60 * 1000

while ($stopwatch.ElapsedMilliseconds -lt $timeoutMs) {
    Start-Sleep -Seconds $PollingIntervalSeconds

    try {
        $pollResult = Get-WorkspaceInfo -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -ApiVersion $apiVersion
        $state = $pollResult.properties.provisioningState
        $elapsed = [math]::Round($stopwatch.Elapsed.TotalMinutes, 1)

        Write-Host "  [$($elapsed)分経過] provisioningState: $state"

        if ($state -eq "Succeeded") {
            Write-Host "`n=== レプリケーションの有効化が完了しました ===" -ForegroundColor Green
            Write-WorkspaceStatus -WorkspaceInfo $pollResult

            $hasReplicationAfter = Test-HasReplicationProperty -WorkspaceInfo $pollResult
            if ($hasReplicationAfter -and $pollResult.properties.replication.enabled -eq $true) {
                Write-Host "`n✅ レプリケーションは有効です。" -ForegroundColor Green
            } else {
                Write-Host "`n⚠ レプリケーションが有効化されていない可能性があります。状態を確認してください。" -ForegroundColor Yellow
            }

            Write-Host "`n注意: すべてのテーブルのレプリケーションが開始されるまで最大1時間かかる場合があります。" -ForegroundColor Yellow
            Write-Host "注意: スイッチオーバーを実行する前に、少なくとも7日間待つことを推奨します。" -ForegroundColor Yellow
            $stopwatch.Stop()
            exit 0
        }
        elseif ($state -eq "Failed" -or $state -eq "Canceled") {
            Write-Error "プロビジョニングが失敗しました。状態: $state"
            $stopwatch.Stop()
            exit 1
        }
    }
    catch {
        Write-Warning "ポーリング中にエラーが発生しました。リトライします... 詳細: $_"
    }
}

$stopwatch.Stop()
Write-Error "タイムアウト (${TimeoutMinutes}分) に達しました。Azure Portal でプロビジョニング状態を確認してください。"
exit 1