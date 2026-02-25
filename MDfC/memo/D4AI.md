# Defender for AI アラートと Azure AI Content Safety / Microsoft Purview の依存関係

## 1. Azure AI Content Safety に依存するアラート

アラート ID に `ContentFiltering` を含むのは以下の **2 件のみ**。

| アラート ID | 概要 |
|---|---|
| `AI.Azure_Jailbreak.ContentFiltering.BlockedAttempt` | Prompt Shields によりジェイルブレイクが**ブロック**された |
| `AI.Azure_Jailbreak.ContentFiltering.DetectedAttempt` | Prompt Shields によりジェイルブレイクが**検出**された |

> [!NOTE]
> Azure AI Content Safety の Prompt Shields 機能自体はジェイルブレイク・間接プロンプトインジェクションの両方を検出するが、Defender for AI のアラートとして `ContentFiltering` を ID に持つのはジェイルブレイク関連の 2 件のみ。
> 「間接プロンプトインジェクション」に対応する `ContentFiltering` 付きアラートは、現在のドキュメントには記載されていない。

> [!NOTE]
> **Foundry Agent Service 向け補足：** エージェント向けには `AI.Azure_Agentic_Jailbreak` / `Azure_Agentic_BlockedJailbreak`（いずれも Preview）が存在し、説明文に「Prompt Shields」と記載されているが、ID に `ContentFiltering` は含まれない。エージェントサービスでは Prompt Shields が統合的に動作する設計と考えられる。

---

## 2. 応答（レスポンス）関連アラートの Content Safety 依存性

**応答（レスポンス）に関するアラートは Azure AI Content Safety の設定に依存しない。**

以下のような応答側のアラートは、Defender for AI 自身の脅威インテリジェンスおよび行動分析によって生成される。

| アラート ID | 概要 |
|---|---|
| `AI.Azure_MaliciousUrl.ModelResponse` | モデル応答にフィッシング URL を検出 |
| `AI.Azure_SensitiveDataAnomaly`（Preview） | 応答に機密データの異常な出力を検出 |
| `AI.Azure_Agentic_MaliciousUrl.ModelResponse`（Preview） | エージェント応答に悪意ある URL |
| `AI.Azure_Agentic_InstructionLeakage`（Preview） | エージェントのシステムプロンプト漏洩 |

これらは Content Safety（コンテンツフィルタリング）の構成有無に関わらず、Defender for AI のサブスクリプションが有効であれば検知される。

---

## 3. Microsoft Purview に起因する Defender for AI アラート

**Microsoft Purview の設定に依存して発報される Defender for AI アラートは、現時点のドキュメントには存在しない。**

Purview は主に **DSPM for AI（Data Security Posture Management for AI）** の文脈で AI ワークロードと連携するが、これはポスチャ管理機能であり、Defender for AI のセキュリティアラート発報とは独立している。

- AI ワークロードで処理される機密データの可視化・分類
- データガバナンスポリシーの適用
- コンプライアンス要件への対応

**データ保護＝Purview、脅威検出（アラート）＝Defender for AI** という役割分担であり、Purview 設定の変更が Defender for AI のアラート有無に影響することはない。

---

## 4. 全体整理

| レイヤー | 担当 | Defender for AI アラートへの影響 |
|---|---|---|
| プロンプト保護（入力側） | Azure AI Content Safety（Prompt Shields） | `ContentFiltering` 付きジェイルブレイクアラート 2 件のみ依存 |
| 脅威検出（入出力の行動分析） | Defender for AI（Defender for Cloud） | **独自分析**。Content Safety / Purview に依存しない（27 件） |
| データ保護・ガバナンス | Microsoft Purview | アラート発報には関与しない |

### まとめ

- **Content Safety 依存はジェイルブレイクの 2 件のみ**（間接プロンプトインジェクション専用の ContentFiltering アラートは現状ドキュメントに未記載）
- **応答関連アラートは Content Safety 設定に依存しない**
- **Purview はアラート発報に関与しない**

---

## 5. Defender for AI アラート一覧

### AI アプリケーション向けアラート（17 件）

| # | アラート ID | アラート名 | Content Safety 依存 |
|---|---|---|---|
| 1 | `AI.Azure_CredentialTheftAttempt` | Azure AI モデルデプロイメントに対する資格情報窃取の試み | No |
| 2 | `AI.Azure_Jailbreak.ContentFiltering.BlockedAttempt` | Prompt Shields によりジェイルブレイクがブロックされた | **Yes** |
| 3 | `AI.Azure_Jailbreak.ContentFiltering.DetectedAttempt` | Prompt Shields によりジェイルブレイクが検出された | **Yes** |
| 4 | `AI.Azure_MaliciousUrl.ModelResponse` | モデル応答にフィッシング URL を検出 | No |
| 5 | `AI.Azure_MaliciousUrl.UnknownSource` | AI アプリケーションでフィッシング URL を共有 | No |
| 6 | `AI.Azure_MaliciousUrl.UserPrompt` | AI アプリケーションでフィッシングの試みを検出 | No |
| 7 | `AI.Azure_AccessFromSuspiciousUserAgent` | 疑わしいユーザーエージェントを検出 | No |
| 8 | `AI.Azure_ASCIISmuggling` | ASCII スマグリングプロンプトインジェクションを検出 | No |
| 9 | `AI.Azure_AccessFromAnonymizedIP` | Tor IP からのアクセス | No |
| 10 | `AI.Azure_AccessFromSuspiciousIP` | 疑わしい IP からのアクセス | No |
| 11 | `AI.Azure_DOWDuplicateRequests` | ウォレット攻撃の疑い - 反復リクエスト | No |
| 12 | `AI.Azure_DOWVolumeAnomaly` | ウォレット攻撃の疑い - ボリューム異常 | No |
| 13 | `AI.Azure_AccessAnomaly` | AI リソースへのアクセス異常 | No |
| 14 | `AI.Azure_AnomalousOperation.InitialAccess` | サービスプリンシパルによる高リスク初期アクセス操作 | No |
| 15 | `AI.Azure_AnomalousToolInvocation` | 異常なツール呼び出し | No |
| 16 | `AI.Azure_SensitiveDataAnomaly`（Preview） | Azure AI リソースで機密データの異常な出力 | No |
| 17 | `AI.Azure_LLMReconnaissance`（Preview） | LLM 偵察の試みを検出 | No |

### Foundry Agent Service 向けアラート（12 件）

| # | アラート ID | アラート名 | Content Safety 依存 |
|---|---|---|---|
| 18 | `AI.Azure_Agentic_Jailbreak`（Preview） | エージェントに対するジェイルブレイクの試みを検出 | No* |
| 19 | `Azure_Agentic_BlockedJailbreak`（Preview） | エージェントに対するジェイルブレイクの試みをブロック | No* |
| 20 | `AI.Azure_Agentic_ASCIISmuggling`（Preview） | エージェントに対する ASCII スマグリングの試み | No |
| 21 | `AI.Azure_Agentic_MaliciousUrl.UserPrompt`（Preview） | エージェントでユーザーフィッシングの試みを検出 | No |
| 22 | `AI.Azure_Agentic_AccessFromSuspiciousIP`（Preview） | エージェントへの疑わしい IP アクセス | No |
| 23 | `AI.Azure_Agentic_AccessFromAnonymizedIP`（Preview） | エージェントへの匿名化 IP アクセス | No |
| 24 | `AI.Azure_Agentic_AccessFromSuspiciousUserAgent`（Preview） | エージェントへの疑わしいユーザーエージェントアクセス | No |
| 25 | `AI.Azure_Agentic_MaliciousUrl.ModelResponse`（Preview） | エージェント応答に悪意ある URL | No |
| 26 | `AI.Azure_Agentic_MaliciousUrl.ToolOutput`（Preview） | エージェントのツール応答に悪意ある URL | No |
| 27 | `AI.Azure_Agentic_DOWVolumeAnomaly`（Preview） | ウォレット攻撃の疑い - ボリューム異常 | No |
| 28 | `AI.Azure_Agentic_InstructionLeakage`（Preview） | エージェントのシステムプロンプト漏洩 | No |
| 29 | `AI.Azure_Agentic_LLMReconaissance`（Preview） | エージェント偵察の試みを検出 | No |

> \* #18, #19 は説明文に「Prompt Shields」と記載されているが、ID に `ContentFiltering` を含まない。エージェントサービスでは Prompt Shields が統合的に機能する設計と考えられる。

---

## 参考ドキュメント

- [Alerts for AI workloads](https://learn.microsoft.com/en-us/azure/defender-for-cloud/alerts-ai-workloads)
- [AI threat protection overview](https://learn.microsoft.com/en-us/azure/defender-for-cloud/ai-threat-protection)