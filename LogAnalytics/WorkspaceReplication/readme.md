# Log Analytics ワークスペースレプリケーション

Log Analytics ワークスペースのレプリケーションを有効化する PowerShell スクリプトです。  
Azure Monitor REST API (`api-version: 2025-02-01`) を `Invoke-AzRestMethod` で呼び出し、セカンダリリージョンへのレプリケーションを構成します。

## 前提条件

- **Az PowerShell モジュール** がインストール済みであること（`Az.Accounts` が必要）
- 以下の権限を持つ Azure アカウントでログインしていること
  - `Microsoft.OperationalInsights/workspaces/write`
  - `Microsoft.Insights/dataCollectionEndpoints/write`
  - 例: **Monitoring Contributor** ロール
- プライマリリージョンとセカンダリリージョンが **同一リージョングループ** 内であること

## 使用方法

### パラメーター

| パラメーター | 必須 | 既定値 | 説明 |
|-------------|------|--------|------|
| `SubscriptionId` | ○ | - | 対象の Azure サブスクリプション ID |
| `ResourceGroupName` | ○ | - | ワークスペースが属するリソースグループ名 |
| `WorkspaceName` | ○ | - | Log Analytics ワークスペース名 |
| `PrimaryRegion` | ○ | - | ワークスペースのプライマリリージョン（例: `japaneast`） |
| `SecondaryRegion` | ○ | - | レプリケーション先のセカンダリリージョン（例: `japanwest`） |
| `PollingIntervalSeconds` | × | `30` | プロビジョニング状態のポーリング間隔（秒） |
| `TimeoutMinutes` | × | `60` | プロビジョニング完了待機のタイムアウト（分） |

### 基本的な実行

```powershell
.\Enable-WorkspaceReplication.ps1 `
    -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -ResourceGroupName "my-resource-group" `
    -WorkspaceName "my-log-analytics-workspace" `
    -PrimaryRegion "japaneast" `
    -SecondaryRegion "japanwest"

## 注意事項

| 項目 | 内容 |
|---|---|
| レプリケーション開始 | 有効化後、全テーブルのレプリケーション開始まで **最大1時間** かかる場合があります |
| 既存ログ | 有効化前に取り込まれたログはセカンダリに **コピーされません** |
| スイッチオーバー | 有効化後 **少なくとも7日** 待ってからスイッチオーバーを実行することが推奨されます |
| Sentinel データ | Watchlist / Threat Intelligence テーブルの完全レプリケーションに **最大12日** かかります |
| 非対応機能 | Auxiliary テーブル、Application Insights、VM Insights、Container Insights は非対応です |
| リージョン制約 | プライマリとセカンダリは同一リージョングループ内である必要があります。East US / East US 2 / South Central US は互いにレプリケーション **不可** です |
| 専用クラスター | 専用クラスターにリンクされたワークスペースの場合、**先にクラスター側でレプリケーションを有効化** してください。クラスターのプロビジョニングには 1〜2 時間かかります |
| DCR の関連付け | AMA / Logs Ingestion API 経由のデータ収集ルール (DCR) は、ワークスペースの **システムデータ収集エンドポイント** に関連付ける必要があります |
| Private Link | スイッチオーバー中は Private Link は **サポートされません** |
| スイッチオーバー権限 | スイッチオーバーの実行にはワークスペースではなく **リソースグループに対する Log Analytics Contributor** 権限が必要です |


@@
 ```powershell
 .\Enable-WorkspaceReplication.ps1 `
     -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
     -ResourceGroupName "my-resource-group" `
     -WorkspaceName "my-log-analytics-workspace" `
     -PrimaryRegion "japaneast" `
     -SecondaryRegion "japanwest"
+```
+
+## 実行例
+
+### 東日本 → 西日本
+
+```powershell
+.\Enable-WorkspaceReplication.ps1 `
+    -SubscriptionId "12345678-abcd-efgh-ijkl-123456789012" `
+    -ResourceGroupName "rg-sentinel-prod" `
+    -WorkspaceName "law-sentinel-prod" `
+    -PrimaryRegion "japaneast" `
+    -SecondaryRegion "japanwest"
+```
+
+### 西ヨーロッパ → 北ヨーロッパ（ポーリング間隔・タイムアウトを変更）
+
+```powershell
+.\Enable-WorkspaceReplication.ps1 `
+    -SubscriptionId "12345678-abcd-efgh-ijkl-123456789012" `
+    -ResourceGroupName "rg-sentinel-eu" `
+    -WorkspaceName "law-sentinel-eu" `
+    -PrimaryRegion "westeurope" `
+    -SecondaryRegion "northeurope" `
+    -PollingIntervalSeconds 60 `
+    -TimeoutMinutes 90
+```
+
+## スクリプトの動作
+
+1. **Azure 接続確認**  
+   `Get-AzContext` でログイン状態を確認し、未ログインの場合は `Connect-AzAccount` を実行します。  
+   `Set-AzContext` で対象サブスクリプションを設定します。
+
+2. **ワークスペース状態確認**  
+   REST API (GET) で現在のワークスペース情報を取得し、`replication` の有無と `provisioningState` を表示します。
+
+3. **レプリケーション有効化**  
+   REST API (PUT) でレプリケーションを有効化します。
+
+4. **プロビジョニング完了待機**  
+   `provisioningState` が `Succeeded` になるまでポーリングし、完了時に最終状態を表示します。
 
@@
-## 参考ドキュメント
-Log Analytics workspace replication - Azure Monitor | Microsoft Learn
-Workspaces - Create Or Update - REST API | Microsoft Learn
-Invoke-AzRestMethod - Az.Accounts | Microsoft Learn
+## 参考ドキュメント
+- [Log Analytics workspace replication - Azure Monitor | Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/workspace-replication)
+- [Workspaces - Create Or Update - REST API | Microsoft Learn](https://learn.microsoft.com/en-us/rest/api/loganalytics/workspaces/create-or-update)
+- [Invoke-AzRestMethod - Az.Accounts | Microsoft Learn](https://learn.microsoft.com/en-us/powershell/module/az.accounts/invoke-azrestmethod)