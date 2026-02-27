# Log Analytics Workspace Replication Scripts

Log Analytics ワークスペース レプリケーションを運用するための PowerShell スクリプト集です。  
以下の操作をカバーします。

- レプリケーション有効化
- 設定状態確認
- フェールオーバー
- フェールバック

---

## 含まれるスクリプト

| スクリプト | 目的 |
|---|---|
| `Enable-WorkspaceReplication.ps1` | ワークスペース レプリケーションを有効化 |
| `Check-WorkspaceReplication.ps1` | レプリケーション設定状態を確認 |
| `Invoke-WorkspaceReplicationFailover.ps1` | セカンダリリージョンへフェールオーバー |
| `Invoke-WorkspaceReplicationFailback.ps1` | フェールバック（元の構成へ戻す） |

---

## クイックスタート

### 1) レプリケーション有効化

```powershell
.\Enable-WorkspaceReplication.ps1 `
  -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
  -ResourceGroupName "rg-sentinel" `
  -WorkspaceName "sentinel-jpe" `
  -PrimaryRegion "japaneast" `
  -SecondaryRegion "japanwest"
```

### 2) 状態確認

```powershell
.\Check-WorkspaceReplication.ps1 `
  -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
  -ResourceGroupName "rg-sentinel" `
  -WorkspaceName "sentinel-jpe"
```

### 3) フェールオーバー

```powershell
.\Invoke-WorkspaceReplicationFailover.ps1 `
  -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
  -ResourceGroupName "rg-sentinel" `
  -WorkspaceName "sentinel-jpe" `
  -SecondaryRegion "japanwest"
```

### 4) フェールバック

```powershell
.\Invoke-WorkspaceReplicationFailback.ps1 `
  -SubscriptionId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
  -ResourceGroupName "rg-sentinel" `
  -WorkspaceName "sentinel-jpe"
```

---

## 各スクリプトのパラメーター

### Enable-WorkspaceReplication.ps1

| パラメーター | 必須 | 既定値 | 説明 |
|---|---|---|---|
| `SubscriptionId` | ✅ | - | 対象サブスクリプション ID |
| `ResourceGroupName` | ✅ | - | リソースグループ名 |
| `WorkspaceName` | ✅ | - | ワークスペース名 |
| `PrimaryRegion` | ✅ | - | プライマリリージョン |
| `SecondaryRegion` | ✅ | - | セカンダリリージョン |
| `PollingIntervalSeconds` | - | `30` | 状態確認ポーリング間隔（秒） |
| `TimeoutMinutes` | - | `60` | タイムアウト（分） |

### Check-WorkspaceReplication.ps1

| パラメーター | 必須 | 既定値 | 説明 |
|---|---|---|---|
| `SubscriptionId` | ✅ | - | 対象サブスクリプション ID |
| `ResourceGroupName` | ✅ | - | リソースグループ名 |
| `WorkspaceName` | ✅ | - | ワークスペース名 |

### Invoke-WorkspaceReplicationFailover.ps1

| パラメーター | 必須 | 既定値 | 説明 |
|---|---|---|---|
| `SubscriptionId` | ✅ | - | 対象サブスクリプション ID |
| `ResourceGroupName` | ✅ | - | リソースグループ名 |
| `WorkspaceName` | ✅ | - | ワークスペース名 |
| `SecondaryRegion` | ✅ | - | フェールオーバー先リージョン |
| `PollingIntervalSeconds` | - | `30` | 状態確認ポーリング間隔（秒） |
| `TimeoutMinutes` | - | `60` | タイムアウト（分） |

### Invoke-WorkspaceReplicationFailback.ps1

| パラメーター | 必須 | 既定値 | 説明 |
|---|---|---|---|
| `SubscriptionId` | ✅ | - | 対象サブスクリプション ID |
| `ResourceGroupName` | ✅ | - | リソースグループ名 |
| `WorkspaceName` | ✅ | - | ワークスペース名 |
| `PollingIntervalSeconds` | - | `30` | 状態確認ポーリング間隔（秒） |
| `TimeoutMinutes` | - | `60` | タイムアウト（分） |

---

## 注意事項

| 項目 | 内容 |
|---|---|
| レプリケーション開始 | 有効化後、全テーブルのレプリケーション開始まで **最大1時間** かかる場合があります |
| 既存ログ | 有効化前に取り込まれたログはセカンダリに **コピーされません** |
| スイッチオーバー推奨 | 有効化後 **少なくとも7日** 待ってから実施推奨 |
| Sentinel データ | Watchlist / Threat Intelligence テーブルの完全レプリケーションに **最大12日** かかる場合があります |

---

## 参考ドキュメント

- [Log Analytics workspace replication - Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/workspace-replication)
- [Workspaces - Create Or Update (REST API)](https://learn.microsoft.com/en-us/rest/api/loganalytics/workspaces/create-or-update)
- [Invoke-AzRestMethod (Az.Accounts)](https://learn.microsoft.com/en-us/powershell/module/az.accounts/invoke-azrestmethod)
