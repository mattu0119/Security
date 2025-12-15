# Notify-Teams-Chat（Logic Apps / Playbook）ARM テンプレート展開手順

## 1. このファイルについて（概要）
このフォルダーにある ARM テンプレート `Notify-Teams-Chat.json` から、Microsoft Sentinel のインシデント作成をトリガーにして、Microsoft Teams のグループチャットを作成し、メッセージ投稿・インシデントタグ付けを行う Logic Apps（Playbook）をデプロイします。

テンプレートは以下の 3 リソースを作成します。

- `Microsoft.Logic/workflows`（Logic Apps: ワークフロー本体）
- `Microsoft.Web/connections`（azuresentinel コネクタ接続）
- `Microsoft.Web/connections`（teams コネクタ接続）

> 注意
> - Teams コネクタはデプロイ後に「接続の認証（サインイン/承認）」が必要です。ARM だけで完全自動化できないケースが多いため、後述の「展開後の作業」を必ず実施してください。
> - ワークフロー内で Microsoft Graph を呼び出す HTTP アクションを **システム割り当てマネージド ID** で実行します。Graph 側の権限付与が必要になる場合があります（後述）。

## 2. 対象ファイル
- `Notify-Teams-Chat.json`
  - デプロイ対象の ARM テンプレートです。
  - 主なパラメーター:
    - `PlaybookName`（既定: `Notify-Teams-chat`）
    - `ChatMembers`（必須）

## 3. 前提条件
- Azure サブスクリプションに対するリソース作成権限（少なくとも対象 RG への Contributor 相当）
- Microsoft Sentinel が有効化された Log Analytics ワークスペースが存在すること
- デプロイ先リージョンで、以下の Managed Connector（managedApis）が利用できること
  - `azuresentinel`
  - `teams`
- Teams 側でチャット作成・メッセージ投稿が許可されるアカウント（コネクタ認証に使用）

## 4. パラメーター
### 4.1 PlaybookName
- Logic App（ワークフロー）名として使用します。
- 既定値: `Notify-Teams-chat`

### 4.2 ChatMembers（必須）
- 追加でチャットに参加させたいメンバー（UPN など）を指定します。
- ワークフロー側では、インシデントに紐づくユーザー UPN と `ChatMembers` を `;`（セミコロン）で連結して Teams のチャットメンバーとして渡します。

推奨入力例（環境に合わせて調整）:

- 1 名: `secops1@contoso.com`
- 複数名: `secops1@contoso.com; secops2@contoso.com`

> 補足
> - 文字列の整形ルールは Teams コネクタ側の仕様に依存します。デプロイ後に実行して、メンバー解決に失敗する場合は区切り文字や空白（スペース）の有無を調整してください。

## 5. 展開方法（Azure Portal）
1. Azure Portal にサインインします
2. **カスタム テンプレートのデプロイ**（「テンプレートをエディターで作成」または「テンプレートの編集」）を開きます
3. `Notify-Teams-Chat.json` の内容を貼り付け、保存します
4. デプロイ先の以下を選択します
   - サブスクリプション
   - リソース グループ（新規作成でも可）
   - リージョン
5. パラメーターを入力します
   - `PlaybookName`（必要に応じて変更）
   - `ChatMembers`（必須）
6. 「確認と作成」→「作成」でデプロイします

## 6. 展開方法（Azure CLI）
### 6.1 事前準備
- Azure CLI が利用できる環境で実行します。

### 6.2 コマンド例
```powershell
# サインイン
az login

# （必要に応じて）サブスクリプション選択
az account set --subscription <SUBSCRIPTION_ID>

# リソース グループ作成（既存なら不要）
az group create -n <RG_NAME> -l <LOCATION>

# テンプレート デプロイ
az deployment group create \
  -g <RG_NAME> \
  --template-file .\Notify-Teams-Chat.json \
  --parameters PlaybookName="Notify-Teams-chat" ChatMembers="secops1@contoso.com; secops2@contoso.com"
```

> 注意
> - `--template-file` のパスは、`Notify-Teams-Chat.json` のあるフォルダーで実行する前提です。

## 7. 展開後の作業（重要）
### 7.1 Teams コネクタ接続の認証（必須）
ARM テンプレートは `Microsoft.Web/connections` を作成しますが、Teams 側の OAuth 認証は通常デプロイ後に実施が必要です。

1. Azure Portal でデプロイしたリソース グループを開きます
2. `Teams-<PlaybookName>`（例: `Teams-Notify-Teams-chat`）の **API 接続** を開きます
3. 「承認」/「編集 API 接続」などから、Teams にサインインして接続を確立します

### 7.2 Sentinel コネクタ / 実行権限（確認）
- テンプレートは `azuresentinel` 接続を **Managed Identity** で利用する構成です。
- Logic App のシステム割り当てマネージド ID に対し、対象の Microsoft Sentinel（ワークスペース）で Playbook 実行に必要な RBAC が付与されていることを確認してください。

> 具体的なロール名は運用（インシデント更新、エンティティ参照、タグ付け等）と組織ポリシーにより異なります。最小権限になるよう、Playbook が必要とする操作に合わせて付与してください。

### 7.3 Microsoft Graph 呼び出し（Managed Identity）の権限（必要に応じて）
ワークフロー内の HTTP アクションが `https://graph.microsoft.com/v1.0/users(...)` を `ManagedServiceIdentity` で呼び出します。

- 実行時に Graph の 401/403 が発生する場合は、Logic App のシステム割り当てマネージド ID（サービス プリンシパル）に対して、Graph のアプリ権限（例: ユーザー情報参照に相当する権限）を付与し、管理者同意が必要になることがあります。

## 8. 動作確認（簡易）
1. Microsoft Sentinel でテスト用インシデントを作成します
2. Logic App の実行履歴でトリガーが起動していることを確認します
3. Teams 側でチャット作成とメッセージ投稿が行われることを確認します
4. インシデントにタグ（例: 「ユーザー確認中」）が追加されることを確認します

## 9. よくある問題
- **Teams 接続が未認証で失敗する**
  - 「展開後の作業 7.1」を実施してください。
- **Graph 呼び出しが 403**
  - 「展開後の作業 7.3」を確認し、マネージド ID への権限付与を検討してください。
- **コネクタがリージョン未対応で失敗**
  - リソース グループのリージョンを変更するか、対象リージョンで `azuresentinel` / `teams` の Managed API が利用可能か確認してください。
