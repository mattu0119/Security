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
| `Force` | - | `False` | 確認プロンプトをスキップして実行 |

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
| `Force` | - | `False` | 確認プロンプトをスキップして実行 |

### Invoke-WorkspaceReplicationFailback.ps1

| パラメーター | 必須 | 既定値 | 説明 |
|---|---|---|---|
| `SubscriptionId` | ✅ | - | 対象サブスクリプション ID |
| `ResourceGroupName` | ✅ | - | リソースグループ名 |
| `WorkspaceName` | ✅ | - | ワークスペース名 |
| `PollingIntervalSeconds` | - | `30` | 状態確認ポーリング間隔（秒） |
| `TimeoutMinutes` | - | `60` | タイムアウト（分） |
| `Force` | - | `False` | 確認プロンプトをスキップして実行 |

---

## パラメーターに指定できるリージョン一覧（Workspace Replication）

> 以下は Azure Monitor Log Analytics Workspace Replication の対応リージョンです（`location code` で指定）。  
> `PrimaryRegion` と `SecondaryRegion` は **同一リージョングループ内**で選択してください。

| リージョングループ | PrimaryRegion に指定可能（表示名 / code） | SecondaryRegion に指定可能（表示名 / code） |
|---|---|---|
| North America | Canada Central (`canadacentral`), Canada East (`canadaeast`), Central US (`centralus`), East US (`eastus`)\*, East US 2 (`eastus2`)\*, North Central US (`northcentralus`), South Central US (`southcentralus`)\*, West Central US (`westcentralus`), West US (`westus`), West US 2 (`westus2`), West US 3 (`westus3`) | Canada Central (`canadacentral`), Central US (`centralus`), East US (`eastus`)\*, East US 2 (`eastus2`)\*, West US (`westus`), West US 2 (`westus2`), West US 3 (`westus3`) |
| South America | Brazil South (`brazilsouth`), Brazil Southeast (`brazilsoutheast`) | Brazil South (`brazilsouth`), Brazil Southeast (`brazilsoutheast`) |
| Europe | France Central (`francecentral`), France South (`francesouth`), Germany North (`germanynorth`), Germany West Central (`germanywestcentral`), Italy North (`italynorth`), North Europe (`northeurope`), Norway East (`norwayeast`), Norway West (`norwaywest`), Poland Central (`polandcentral`), UK South (`uksouth`), Spain Central (`spaincentral`), Sweden Central (`swedencentral`), Sweden South (`swedensouth`), Switzerland North (`switzerlandnorth`), Switzerland West (`switzerlandwest`), West Europe (`westeurope`), UK West (`ukwest`) | France Central (`francecentral`), Germany West Central (`germanywestcentral`), North Europe (`northeurope`), UK South (`uksouth`), West Europe (`westeurope`), UK West (`ukwest`) |
| Middle East | Qatar Central (`qatarcentral`), UAE Central (`uaecentral`), UAE North (`uaenorth`) | Qatar Central (`qatarcentral`), UAE Central (`uaecentral`), UAE North (`uaenorth`) |
| India | Central India (`centralindia`), Jio India Central (`jioindiacentral`), Jio India West (`jioindiawest`), South India (`southindia`) | Central India (`centralindia`), Jio India Central (`jioindiacentral`), Jio India West (`jioindiawest`), South India (`southindia`) |
| Asia Pacific | East Asia (`eastasia`), Japan East (`japaneast`), Japan West (`japanwest`), Korea Central (`koreacentral`), Korea South (`koreasouth`), Southeast Asia (`southeastasia`) | East Asia (`eastasia`), Japan East (`japaneast`), Japan West (`japanwest`), Korea Central (`koreacentral`), Southeast Asia (`southeastasia`) |
| Oceania | Australia Central (`australiacentral`), Australia Central 2 (`australiacentral2`), Australia East (`australiaeast`), Australia Southeast (`australiasoutheast`) | Australia Central (`australiacentral`), Australia East (`australiaeast`), Australia Southeast (`australiasoutheast`) |
| Africa | South Africa North (`southafricanorth`), South Africa West (`southafricawest`) | South Africa North (`southafricanorth`), South Africa West (`southafricawest`) |

\* 注意: **East US / East US 2 / South Central US は相互にレプリケーションできません。**

### 参考
- https://learn.microsoft.com/azure/azure-monitor/logs/workspace-replication#deployment-considerations


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
