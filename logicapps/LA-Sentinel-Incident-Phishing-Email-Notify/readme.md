# LA-Sentinel-Incident-Phishing-Email-Notify 展開手順

## 1. 概要
このフォルダーにある ARM テンプレート `LA-Sentinel-Incident-Phishing-Email-Notify.json` から、Microsoft Sentinel インシデント作成時にメール通知を送信する Logic Apps（Playbook）を展開します。

この Playbook は、主に以下を実行します。

- Microsoft Sentinel のインシデント作成をトリガーに起動
- インシデントの `relatedEntities` から `MailMessage` エンティティを抽出
- 重要度、タイトル、Defender XDR / Sentinel へのリンク、関連メール情報を HTML メールで通知
- インシデント コメント先頭の内容を Security Copilot の分析レポートとしてメール本文に埋め込み

テンプレートは以下の 3 リソースを作成します。

- `Microsoft.Logic/workflows`（Logic App 本体）
- `Microsoft.Web/connections`（Microsoft Sentinel コネクタ接続）
- `Microsoft.Web/connections`（Office 365 Outlook コネクタ接続）

> 注意
> - 通知先メールアドレスは ARM テンプレートのパラメーター `通知メールアドレス` で指定する構成です。
> - `MailMessage` エンティティを含まないインシデントでは、メール件名・送信元・送信元 IP・受信者などの項目が空になる場合があります。
> - Office 365 Outlook コネクタはデプロイ後にサインインと接続認証が必要です。

## 2. 対象ファイル
- `LA-Sentinel-Incident-Phishing-Email-Notify.json`
  - デプロイ対象の ARM テンプレートです。
  - 主なパラメーター:
		- `PlaybookName`（既定: `LA-Sentinel-Incident-Phishing-Email-Notify`）
		- `通知メールアドレス`（必須）

## 3. 前提条件
- Azure サブスクリプションに対して、対象リソース グループへリソースを作成できる権限があること
- Microsoft Sentinel が有効化された Log Analytics ワークスペースが存在すること
- デプロイ先リージョンで以下の Managed API が利用可能であること
  - `azuresentinel`
  - `office365`
- Office 365 Outlook コネクタの認証に使用するアカウントが、メール送信可能であること
- Logic App のマネージド ID に、Microsoft Sentinel ワークスペースに対する適切なロールを付与できること

## 4. パラメーター
### 4.1 PlaybookName
- Logic App 名、および API 接続名のサフィックスとして使用します。
- 既定値: `LA-Sentinel-Incident-Phishing-Email-Notify`

### 4.2 通知メールアドレス
- 送信先メールアドレスです。
- Logic App の `メールの送信_(V2)` アクションの `To` にそのまま渡されます。
- 必須パラメーターです。

入力例:

- 1 件: `soc@contoso.com`
- 複数件を運用したい場合: まずは単一アドレスでの利用を推奨

> 補足
> - テンプレート上は単一文字列パラメーターです。複数宛先を利用する場合は、Office 365 Outlook コネクタ側で受け付ける形式に合わせて値を調整してください。

作成される接続名の例:

- `MicrosoftSentinel-LA-Sentinel-Incident-Phishing-Email-Notify`
- `Office365-LA-Sentinel-Incident-Phishing-Email-Notify`

## 5. 事前に確認・変更したい項目
テンプレートの現状では、メール送信アクション `メールの送信_(V2)` に以下の構成が含まれています。

- 宛先 (`To`): パラメーター `通知メールアドレス`
- 重要度 (`Importance`): `Normal`

利用環境に合わせて、必要に応じて以下を確認または変更してください。

- `通知メールアドレス` に指定する送信先
- 件名フォーマット
- 本文の日本語表現
- メール重要度

## 6. 展開方法
### 6.1 Deploy to Azure ボタン
以下のボタンから Azure Portal のカスタムデプロイ画面を開けます。

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fmattu0119%2FSecurity%2Frefs%2Fheads%2Fmain%2Flogicapps%2FLA-Sentinel-Incident-Phishing-Email-Notify%2FLA-Sentinel-Incident-Phishing-Email-Notify.json)

手順:

1. ボタンをクリックします。
2. デプロイ先の以下を選択します。
	- サブスクリプション
	- リソース グループ
	- リージョン
3. `PlaybookName` を必要に応じて変更します。
4. `通知メールアドレス` を入力します。
5. 「確認と作成」→「作成」を実行します。

### 6.2 Azure Portal で手動展開
1. Azure Portal にサインインします。
2. **カスタム テンプレートのデプロイ** を開きます。
3. **テンプレートの編集** を選択します。
4. `LA-Sentinel-Incident-Phishing-Email-Notify.json` の内容を貼り付けて保存します。
5. サブスクリプション、リソース グループ、リージョンを選択します。
6. `PlaybookName` を指定します。
7. `通知メールアドレス` を指定します。
8. 「確認と作成」→「作成」でデプロイします。

### 6.3 Azure CLI で展開
ローカルから展開する場合の例です。

```bash
az deployment group create \
  --resource-group <ResourceGroupName> \
  --template-file .\logicapps\LA-Sentinel-Incident-Phishing-Email-Notify\LA-Sentinel-Incident-Phishing-Email-Notify.json \
	--parameters PlaybookName=LA-Sentinel-Incident-Phishing-Email-Notify 通知メールアドレス=soc@contoso.com
```

## 7. 展開後の作業
### 7.1 Office 365 Outlook 接続の認証
ARM テンプレートは API 接続リソースを作成しますが、Office 365 Outlook 側の OAuth 認証は通常デプロイ後に実施が必要です。

1. Azure Portal でデプロイ先リソース グループを開きます。
2. `Office365-<PlaybookName>` の API 接続を開きます。
3. 「承認」または「編集 API 接続」を選択します。
4. 実際にメール送信に利用するアカウントでサインインします。

> 補足
> - 送信元は、この接続を認証したアカウントに依存します。
> - 共有メールボックス運用を行う場合は、接続アカウントと送信権限を事前に確認してください。

### 7.2 Microsoft Sentinel 接続とロール割り当て
このテンプレートでは、`azuresentinel` コネクタを Logic App のシステム割り当てマネージド ID で利用する構成です。

この Playbook はインシデントを受信する用途が中心のため、通常は `Microsoft Sentinel Reader` ロールで十分です。将来的にインシデント更新やコメント追加などの書き込みアクションを追加する場合は、`Microsoft Sentinel Responder` 以上を検討してください。

手順:

1. Logic App を開き、**ID** からシステム割り当てマネージド ID を有効化済みであることを確認します。
2. Microsoft Sentinel ワークスペース、または対象リソース グループの **アクセス制御 (IAM)** を開きます。
3. **ロールの割り当ての追加** を選択します。
4. 以下のいずれかのロールを付与します。
	- `Microsoft Sentinel Reader`（受信・参照のみ）
	- `Microsoft Sentinel Responder`（更新操作を追加する場合）
5. 割り当て先として Logic App を選択し、対象 Playbook を指定して保存します。

### 7.3 Microsoft Sentinel の自動化ルール関連付け
Playbook を自動実行するには、Microsoft Sentinel 側で自動化ルールに関連付けます。

1. Microsoft Sentinel ワークスペースを開きます。
2. **Automation** を開きます。
3. **Create** → **Automation rule** を選択します。
4. トリガーに **When incident is created** を選択します。
5. 必要に応じて条件を設定します。
	- タイトルに `phish` を含むインシデントのみ
	- 重要度が `High` 以上
	- Provider が `Microsoft 365 Defender`
6. アクションで本 Playbook を選択します。
7. 保存します。

## 8. 動作確認
1. Microsoft Sentinel でテスト用インシデントを作成、または既存のフィッシング系インシデント発生を待ちます。
2. 自動化ルールにより Playbook が起動することを確認します。
3. Logic App の **実行履歴** で成功していることを確認します。
4. 指定したメールアドレスに通知メールが届くことを確認します。
5. メール本文に以下が含まれることを確認します。
	- Defender XDR / Sentinel へのリンク
	- インシデント番号、タイトル、重要度
	- 関連メールの件名、送信元、送信元 IP、受信者
	- Security Copilot コメント内容

## 9. よくある問題
### 9.1 Office 365 接続が `Unauthorized` / `Not authenticated`
- API 接続 `Office365-<PlaybookName>` の認証が未完了です。
- 「7.1 Office 365 Outlook 接続の認証」を実施してください。

### 9.2 Microsoft Sentinel トリガーが動作しない
- Logic App のマネージド ID に Sentinel ワークスペースへのロールが付与されているか確認してください。
- 自動化ルールで正しい Playbook が選択されているか確認してください。
- 自動化ルールの条件が厳しすぎないか確認してください。

### 9.3 メール本文の関連メール情報が空になる
- インシデントに `MailMessage` エンティティが含まれていない可能性があります。
- `relatedEntities` にメール情報が付与される分析ルール・統合元であるか確認してください。

### 9.4 AI 分析リスク評価やコメントが空になる
- インシデントの先頭コメントに Security Copilot 分析結果が存在しない場合があります。
- この場合でも Playbook 自体は動作しますが、一部表示が `レポート本文を参照` または `コメントなし` になることがあります。

## 10. 補足
このテンプレートでは通知先メールアドレスがすでにパラメーター化されています。さらに再利用性を高める場合は、以下の項目も追加でパラメーター化すると運用しやすくなります。

- 件名プレフィックス
- 重要度
- 条件分岐時のメッセージ文言
