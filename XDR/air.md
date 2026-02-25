# Automated Investigation and Response（AIR）— Microsoft Defender XDR

## 概要

Automated Investigation and Response（AIR）は、Microsoft Defender XDR に組み込まれた **自動調査・対応機能** です。セキュリティアラートが発生した際に、アナリストが行う調査・修復のステップを自動的に実行し、SOC チームの負担を大幅に軽減します。AIR は「仮想アナリスト」として 24 時間 365 日稼働し、脅威の調査とインシデント対応を迅速かつスケーラブルに処理します。

## 動作の仕組み — セルフヒーリング

AIR のセルフヒーリング（自己修復）は以下のステップで動作します。

1. **アラートの発生** — 悪意のあるアクティビティやアーティファクトが検出されるとアラートが生成され、インシデントが作成される
2. **自動調査の開始** — インシデントに紐づく自動調査が開始される
3. **証拠の評価** — 各証拠（エビデンス）に対して判定（Verdict）が下される
4. **修復アクションの実行** — 判定結果に基づき、修復アクションが自動または承認待ちで実行される
5. **スコープの拡大** — 調査中に関連するアラートが発生した場合、調査範囲が自動的に拡大される

### 判定（Verdict）の種類

| 判定 | 説明 | 結果 |
|---|---|---|
| **Malicious（悪意あり）** | 脅威が確認された | デバイス：自動修復（自動化レベルが Full の場合）<br>メール：承認待ち |
| **Compromised（侵害済み）** | ユーザーが侵害された | 自動修復 |
| **Suspicious（疑わしい）** | 完全には確定していないが疑わしい | 承認待ち |
| **No threats found（脅威なし）** | 脅威が検出されなかった | アクション不要 |

## 対象となる脅威保護サービス

AIR は以下の Microsoft Defender サービスからのシグナルを統合的に相関分析します。

| エンティティ | 脅威保護サービス |
|---|---|
| **デバイス（エンドポイント）** | Microsoft Defender for Endpoint |
| **オンプレミス AD ユーザー、エンティティの行動・活動** | Microsoft Defender for Identity |
| **メールコンテンツ（メッセージ、ファイル、URL）** | Microsoft Defender for Office 365 |

## 修復アクション一覧

### デバイス（エンドポイント）

| アクション | 説明 |
|---|---|
| デバイスの分離（Isolate device） | デバイスをネットワークから隔離（元に戻すことが可能） |
| ファイルの検疫（Quarantine a file） | 悪意のあるファイルを検疫に送信 |
| コード実行の制限（Restrict code execution） | 信頼されていないプロセスの実行を制限（元に戻すことが可能） |
| ウイルス対策スキャンの実行（Run antivirus scan） | デバイス上でウイルススキャンを実行 |
| プロセスの停止と検疫（Stop and quarantine） | 悪意のあるプロセスを停止しファイルを検疫 |
| 調査パッケージの収集（Collect investigation package） | フォレンジック用の調査パッケージを収集 |
| デバイスのオフボード（Offboard machine） | デバイスを Defender for Endpoint から切り離す |
| ネットワーク封じ込め（Contain devices from the network） | ネットワークから封じ込める |

### メール

| アクション | 説明 |
|---|---|
| メールの論理削除（Soft delete email messages or clusters） | メッセージまたはクラスターを論理削除 |
| メールの検疫（Quarantine email） | メールを検疫に移動 |
| 添付ファイルの検疫（Quarantine an email attachment） | 悪意のある添付ファイルを検疫 |
| URL のブロック（Block URL） | クリック時に悪意のある URL をブロック |
| 外部メール転送の無効化（Turn off external mail forwarding） | 外部への自動転送を停止 |

### ユーザー（アカウント）

| アクション | 説明 |
|---|---|
| ユーザーの無効化（Disable user） | ユーザーアカウントを無効にする |
| パスワードのリセット（Reset user password） | 侵害された可能性のあるパスワードをリセット |
| ユーザーの侵害確認（Confirm user as compromised） | ユーザーを侵害済みとしてマーク |

## 自動化レベル

デバイスグループごとに自動化レベルを設定でき、修復アクションの実行方式を制御します。

| 自動化レベル | 動作 |
|---|---|
| **Full — remediate threats automatically（推奨）** | 修復アクションを自動的に実行 |
| **Semi — require approval for any remediation** | すべての修復に承認が必要 |
| **Semi — require approval for core folders remediation** | コアフォルダーの修復にのみ承認が必要 |
| **Semi — require approval for non-temp folders remediation** | 一時フォルダー以外の修復に承認が必要 |
| **No automated response** | 自動応答なし |

> [!NOTE]
> メールコンテンツに関する修復アクションは、自動化レベルに関わらず **常に承認が必要** です。

## 前提条件

| 要件 | 詳細 |
|---|---|
| **ライセンス** | Microsoft 365 E5 / A5、または Microsoft 365 E3 + Microsoft Defender Suite アドオン 等 |
| **デバイス要件** | Windows 10 v1709 以降 / Windows 11、Defender for Endpoint が構成済み |
| **ネットワーク要件** | Defender for Identity の有効化、Defender for Cloud Apps の構成 |
| **メール保護** | Defender for Office 365 が構成済み |
| **権限** | グローバル管理者 または セキュリティ管理者ロール |

## アクション センターでの管理

すべての修復アクション（保留中・完了済み）は **アクション センター** で一元管理されます。

- **保留中（Pending）タブ** — 承認待ちのアクションを確認・承認・拒否
- **履歴（History）タブ** — 完了したアクションの確認、必要に応じて **元に戻す（Undo）** 操作が可能

### 元に戻せるアクション

以下のアクションはアクション センターの「履歴」タブから取り消し可能です。

- デバイスの分離（Isolate device）
- デバイスの封じ込め（Contain device）
- ユーザーの封じ込め（Contain user）
- コード実行の制限（Restrict code execution）
- ファイルの検疫（Quarantine a file）
- レジストリキーの削除（Remove a registry key）
- サービスの停止（Stop a service）
- ドライバーの無効化（Disable a driver）
- スケジュールタスクの削除（Remove a scheduled task）

## 調査結果の確認方法

1. **Microsoft Defender ポータル** (https://security.microsoft.com) にサインイン
2. **インシデント** ページでインシデントを選択
3. **[調査]（Investigations）** タブで自動調査の詳細と結果を確認
4. 各証拠の判定、影響を受けたエンティティ、修復アクション、調査ログを確認

## 手動修復アクション

AIR の自動調査に加え、SOC チームは以下の手動アクションも実行可能です。

- **Advanced Hunting** によるデバイス・ユーザー・メールへのアクション
- **Explorer** によるメールのジャンク移動・論理削除・物理削除
- **Live Response** によるファイル削除・プロセス停止・スケジュールタスクの削除
- **Defender for Endpoint API** を使ったデバイスの分離やスキャン実行

## 参考リンク

- [Automated investigation and response in Microsoft Defender XDR](https://learn.microsoft.com/en-us/defender-xdr/m365d-autoir)
- [Configure AIR capabilities](https://learn.microsoft.com/en-us/defender-xdr/m365d-configure-auto-investigation-response)
- [View and manage actions in the Action center](https://learn.microsoft.com/en-us/defender-xdr/m365d-autoir-actions)
- [Details and results of an automated investigation](https://learn.microsoft.com/en-us/defender-xdr/m365d-autoir-results)
- [Remediation actions in Microsoft Defender XDR](https://learn.microsoft.com/en-us/defender-xdr/m365d-remediation-actions)