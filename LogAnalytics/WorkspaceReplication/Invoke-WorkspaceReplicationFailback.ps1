<#
.SYNOPSIS
    Log Analytics ワークスペース レプリケーションのフェールバックを実行する

.DESCRIPTION
    Azure Monitor Log Analytics ワークスペースに対してフェールバックを実行します。
    REST API (api-version: 2025-02-01) を Invoke-AzRestMethod で呼び出します。

.NOTES
    前提:
    - Az.Accounts モジュール利用可能
    - 適切な権限 (例: リソースグループに対する Log Analytics Contributor)
    - レプリケーションが有効化済み
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName,

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
    $res = Invoke-AzRestMethod -Method GET -Path $uri

    if ($res.StatusCode -ne 200) {
        throw "ワークスペース取得に失敗しました。StatusCode: $($res.StatusCode)`n$($res.Content)"
    }

    return ($res.Content | ConvertFrom-Json)
}

function Has-Property {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return ($Object.PSObject.Properties.Name -contains $Name)
}

Write-Host "=== Azure 接続確認 ===" -ForegroundColor Cyan
$ctx = Get-AzContext
if (-not $ctx) {
    Write-Host "Azure にログインしていないため Connect-AzAccount を実行します..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
}
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
Write-Host "サブスクリプション: $SubscriptionId" -ForegroundColor Green

Write-Host "`n=== フェールバック前チェック ===" -ForegroundColor Cyan
$ws = Get-WorkspaceInfo -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -ApiVersion $apiVersion

Write-Host "ワークスペース名      : $($ws.name)"
Write-Host "現在の location      : $($ws.location)"
Write-Host "provisioningState    : $($ws.properties.provisioningState)"

$hasReplication = Has-Property -Object $ws.properties -Name "replication"
if (-not $hasReplication) {
    throw "replication プロパティが未設定です。先に Enable-WorkspaceReplication.ps1 を実行してください。"
}

$rep = $ws.properties.replication
Write-Host "replication.enabled  : $($rep.enabled)"
Write-Host "replication.location : $($rep.location)"

if ($rep.enabled -ne $true) {
    throw "レプリケーションが有効ではありません。フェールバックを実行できません。"
}

if (-not $Force) {
    $confirm = Read-Host "`nフェールバックを実行します。よろしいですか？ (y/N)"
    if ($confirm -notmatch '^(?i:y|yes)$') {
        Write-Host "処理を中止しました。" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`n=== フェールバック実行 ===" -ForegroundColor Cyan
$failbackUri = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/${WorkspaceName}/failback?api-version=$apiVersion"

$failbackResponse = Invoke-AzRestMethod -Method POST -Path $failbackUri

if ($failbackResponse.StatusCode -notin @(200, 202)) {
    throw "フェールバック API 呼び出しに失敗しました。StatusCode: $($failbackResponse.StatusCode)`n$($failbackResponse.Content)"
}

Write-Host "フェールバック API 呼び出し成功 (StatusCode: $($failbackResponse.StatusCode))" -ForegroundColor Green

Write-Host "`n=== 状態監視 (provisioningState) ===" -ForegroundColor Cyan
Write-Host "ポーリング間隔: ${PollingIntervalSeconds}秒 / タイムアウト: ${TimeoutMinutes}分"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$timeoutMs = $TimeoutMinutes * 60 * 1000

while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
    Start-Sleep -Seconds $PollingIntervalSeconds

    try {
        $current = Get-WorkspaceInfo -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -WorkspaceName $WorkspaceName -ApiVersion $apiVersion
        $state = $current.properties.provisioningState
        $elapsed = [math]::Round($sw.Elapsed.TotalMinutes, 1)

        Write-Host "  [$elapsed 分経過] provisioningState: $state"

        if ($state -eq "Succeeded") {
            Write-Host "`n=== フェールバック処理完了 ===" -ForegroundColor Green
            Write-Host "workspace.location    : $($current.location)"

            $hasReplicationNow = Has-Property -Object $current.properties -Name "replication"
            if ($hasReplicationNow) {
                Write-Host "replication.enabled   : $($current.properties.replication.enabled)"
                Write-Host "replication.location  : $($current.properties.replication.location)"
            }

            $sw.Stop()
            exit 0
        }

        if ($state -in @("Failed", "Canceled")) {
            throw "フェールバック後のプロビジョニングが失敗しました。state: $state"
        }
    }
    catch {
        Write-Warning "状態確認中にエラー: $_"
    }
}

$sw.Stop()
throw "タイムアウト (${TimeoutMinutes}分) に達しました。Azure Portal で状態を確認してください。"