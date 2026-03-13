# Teams Vulnerability Notification Function Sample

Azure Functions を使って Microsoft Teams に脆弱性関連の通知を送るサンプルです。  
このサンプルには、Function App を Azure に展開するための ARM テンプレート `azuredeploy.json` と、対応するパラメーター ファイル `azuredeploy.parameters.sample.json` が含まれています。

## このサンプルでできること

- Azure Functions (Flex Consumption) の Function App をデプロイ
- Storage Account / Blob Container をデプロイ
- Log Analytics Workspace をデプロイ
- Application Insights をデプロイ
- Function App の基本設定をデプロイ
- Microsoft Graph を利用するためのアプリ設定を一部投入

## このテンプレートが自動で構成するもの

`azuredeploy.json` は、Function App に必要な以下の Storage 接続設定をテンプレート内で自動生成します。

- `AzureWebJobsStorage`
- `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING`
- `DEPLOYMENT_STORAGE_CONNECTION_STRING`

これらは parameters ファイルで指定する必要はありません。  
修正版テンプレートでは、接続文字列を `variables` ではなく、Function App の `appSettings` 内で `listKeys()` を使って直接組み立てています。

## このテンプレートが自動では構成しないもの

以下は ARM テンプレートだけでは完結しません。必要に応じて別途準備してください。

- Microsoft Graph / Teams 用のアプリ登録
- Graph API 権限の付与と admin consent
- Function コードのデプロイ パッケージ配置
- Function 実装が必要とする追加アプリ設定
- Managed Identity への追加 RBAC 割り当て

## 前提条件

- Azure サブスクリプション
- Azure CLI
- デプロイ先リソース グループ
- ARM テンプレートを実行できる権限
- Function コード / パッケージの配置先 Blob Container へのアクセス権

## Flex Consumption の注意

このテンプレートは Azure Functions の Flex Consumption プラン (`FC1`) を使用します。  
Flex Consumption はリージョンによって利用可否が異なるため、`location` に指定するリージョンは事前に確認してください。

既定値は `japaneast` ですが、利用できない場合は `eastus`、`westeurope`、`uksouth`、`northeurope` などの対応リージョンを利用してください。

## テンプレート構成

主なリソースは次のとおりです。

- `Microsoft.Storage/storageAccounts`
- `Microsoft.Storage/storageAccounts/blobServices/containers`
- `Microsoft.OperationalInsights/workspaces`
- `Microsoft.Insights/components`
- `Microsoft.Web/serverfarms`
- `Microsoft.Web/sites`
- `Microsoft.Web/sites/config`

## パラメーター一覧

`azuredeploy.parameters.sample.json` で指定する主なパラメーターは以下です。

| パラメーター | 型 | 例 / 既定値 | 説明 |
|---|---|---:|---|
| `location` | string | `japaneast` | デプロイ先リージョン |
| `functionPlanName` | string | `func-teams-vuln-plan` | Flex Consumption プラン名 |
| `functionAppName` | string | `func-teams-vuln-demo` | Function App 名。グローバル一意が必要 |
| `storageAccountName` | string | `functeamsvulndemo01` | Storage Account 名。3〜24文字、小文字英数字のみ |
| `deploymentContainerName` | string | `function-releases` | デプロイ用 Blob Container 名 |
| `logAnalyticsName` | string | `func-teams-vuln-law` | Log Analytics Workspace 名 |
| `applicationInsightsName` | string | `func-teams-vuln-ai` | Application Insights 名 |
| `functionAppRuntime` | string | `dotnet-isolated` | Functions ランタイム |
| `functionAppRuntimeVersion` | string | `8.0` | ランタイム バージョン |
| `maximumInstanceCount` | int | `20` | Flex Consumption の最大インスタンス数 |
| `instanceMemoryMB` | int | `2048` | 各インスタンスのメモリ |
| `httpPerInstanceConcurrency` | int | `10` | HTTP トリガーの同時実行数 |
| `teamsGraphBaseUrl` | string | `https://graph.microsoft.com/v1.0` | Microsoft Graph ベース URL |
| `defaultTeamId` | string | `""` | 任意の既定 Team ID |
| `defaultAdminUpns` | string | `secadmin@contoso.com,owner1@contoso.com` | 任意の管理者 UPN 一覧 |
| `enableAppServiceLogs` | bool | `true` | App Service ログ有効化 |

## サンプル parameters ファイル

`azuredeploy.parameters.sample.json` には、`location`、`functionPlanName`、`functionAppName`、`storageAccountName`、`deploymentContainerName`、`logAnalyticsName`、`applicationInsightsName`、`functionAppRuntime`、`functionAppRuntimeVersion`、`maximumInstanceCount`、`instanceMemoryMB`、`httpPerInstanceConcurrency`、`teamsGraphBaseUrl`、`defaultTeamId`、`defaultAdminUpns`、`enableAppServiceLogs` が含まれます。

## デプロイ手順

### 1. リソース グループを作成

Azure CLI を使ってリソース グループを作成します。  
実行コマンド: `az group create --name rg-teams-vuln-demo --location japaneast`

```PowerShell
az group create \
  --name rg-teams-vuln-demo \
  --location japaneast
````

### 2. パラメーター ファイルをコピーして編集

`azuredeploy.parameters.sample.json` を `azuredeploy.parameters.json` にコピーして、必要に応じて値を編集します。

Windows のコマンド プロンプトでは、`copy azuredeploy.parameters.sample.json azuredeploy.parameters.json` を使用できます。  
PowerShell では、`Copy-Item .\azuredeploy.parameters.sample.json .\azuredeploy.parameters.json` を使用できます。

```PowerShell
copy azuredeploy.parameters.sample.json azuredeploy.parameters.json
```
`
必要に応じて以下を変更してください。

- `location`
- `functionAppName`
- `storageAccountName`
- 各種リソース名

### 3. ARM テンプレートをデプロイ

Azure CLI で ARM テンプレートをデプロイします。  
実行コマンド: `az deployment group create --resource-group rg-teams-vuln-demo --template-file azuredeploy.json --parameters @azuredeploy.parameters.json`

```PowerShell
az deployment group create \
  --resource-group rg-teams-vuln-demo \
  --template-file azuredeploy.json \
  --parameters @azuredeploy.parameters.json
````

## デプロイ後の確認

以下を確認してください。

1. Storage Account が作成されている
2. Blob Container (`function-releases`) が作成されている
3. Log Analytics Workspace が作成されている
4. Application Insights が作成されている
5. Function App が作成されている
6. Function App のアプリ設定に以下が入っている
   - `AzureWebJobsStorage`
   - `WEBSITE_CONTENTAZUREFILECONNECTIONSTRING`
   - `DEPLOYMENT_STORAGE_CONNECTION_STRING`
   - `GRAPH_BASE_URL`
   - `DEFAULT_TEAM_ID`
   - `DEFAULT_ADMIN_UPNS`

## Microsoft Graph / Teams 連携の前提

このサンプルで Teams 通知や Graph API 呼び出しを行う場合、別途以下が必要になることがあります。

- Entra ID アプリ登録
- Graph API アクセス許可
- admin consent
- クライアント ID / シークレットまたは Managed Identity ベースの認証構成
- Teams / Channel / Team に対する適切なアクセス権

Function コード側がどの認証方式を使うかに応じて、必要な追加アプリ設定を投入してください。

## よくあるデプロイ失敗ポイント

### `listKeys is not expected at this location`

修正版テンプレートでは解消済みです。  
以前の版では、Storage 接続文字列を `variables` 内で `listKeys()` により生成していたため、テンプレート検証に失敗する場合がありました。

### Flex Consumption がリージョン未対応

`location` を対応リージョンに変更してください。

### Function App 名 / Storage Account 名の重複

どちらも一意制約があります。別名に変更してください。

### Graph 関連の実行時エラー

テンプレートが通っても、Graph 認証や権限が不足していると Function 実行時に 401 / 403 になることがあります。

## 補足

- `WEBSITE_RUN_FROM_PACKAGE` は `0` に設定されています
- デプロイ用ストレージ接続は `DEPLOYMENT_STORAGE_CONNECTION_STRING` に設定されます
- Blob Container URL は `functionPackageContainerUrl` から組み立てられます

## 今後の改善候補

- Key Vault 統合
- Managed Identity ベースの Graph 認証
- RBAC 自動割り当て
- リージョン バリデーションの追加
- Bicep 化