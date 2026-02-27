<#
作成日: 2026-02-27
作成者: Hiroshi Matsumoto

.SYNOPSIS
  Log Analytics ワークスペースのレプリケーション設定状態を確認する

.DESCRIPTION
  ワークスペースの replication 設定と provisioningState を取得して表示します。
  REST API (api-version: 2025-02-01) を Invoke-AzRestMethod で呼び出します。

.PARAMETER SubscriptionId
  対象のサブスクリプション ID

.PARAMETER ResourceGroupName
  ワークスペースのリソースグループ名

.PARAMETER WorkspaceName
  ワークスペース名
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$apiVersion = "2025-02-01"
$uri = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/${WorkspaceName}?api-version=$apiVersion"

function Test-HasReplicationProperty {
    param(
        [Parameter(Mandatory = $true)]$WorkspaceInfo
    )
    return ($WorkspaceInfo.properties.PSObject.Properties.Name -contains "replication")
}

# Azure 接続確認
$ctx = Get-AzContext
if (-not $ctx) {
    Write-Host "Azure にログインしていません。Connect-AzAccount を実行します..." -ForegroundColor Yellow
    Connect-AzAccount | Out-Null
}
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null

Write-Host "=== レプリケーション設定の取得 ===" -ForegroundColor Cyan
$response = Invoke-AzRestMethod -Method GET -Path $uri

if ($response.StatusCode -ne 200) {
    Write-Error "取得に失敗しました。StatusCode: $($response.StatusCode)`n$($response.Content)"
    exit 1
}

$ws = $response.Content | ConvertFrom-Json

Write-Host "ワークスペース名        : $($ws.name)"
Write-Host "リージョン              : $($ws.location)"
Write-Host "provisioningState      : $($ws.properties.provisioningState)"

$hasReplication = Test-HasReplicationProperty -WorkspaceInfo $ws

if ($hasReplication) {
    Write-Host "replication.enabled    : $($ws.properties.replication.enabled)"
    Write-Host "replication.location   : $($ws.properties.replication.location)"
} else {
    Write-Host "replication            : (未設定)" -ForegroundColor Yellow
}

# 判定メッセージ
if ($hasReplication -and $ws.properties.replication.enabled -eq $true) {
    Write-Host "`n✅ レプリケーションは有効です。" -ForegroundColor Green
} else {
    Write-Host "`n⚠ レプリケーションは無効、または未設定です。" -ForegroundColor Yellow
}