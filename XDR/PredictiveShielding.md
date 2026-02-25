# 予測シールド（Predictive Shielding）- プレビュー

> [!NOTE]
> この機能はプレビュー段階であり、商用リリース前に大幅に変更される可能性があります。

## 概要

予測シールドは、Microsoft Defender XDR の **Automatic Attack Disruption（自動攻撃キャンセル）** を拡張した **プロアクティブな防御機能** です。侵害された資産を封じ込めるだけでなく、**攻撃の進行を予測し、まだ侵害されていない資産を事前に強化** します。

## 動作の仕組み

予測シールドは以下の 2 つの柱で構成されます。

1. **Prediction（予測）**: 脅威インテリジェンス、攻撃者の行動パターン、過去のインシデント、組織の露出データを分析し、攻撃者の次の標的や攻撃経路を推測
2. **Enforcement（適用）**: 特定された攻撃経路に対してリアルタイムで予防的な保護を適用

グラフベースのロジックにより、組織の資産・接続・脆弱性を統合的にマッピングし、攻撃者が到達する前に重要資産を保護します。

### グラフベースの予測ロジック（3 段階）

1. ポストブリーチのアクティビティを組織の露出グラフに重ね合わせ、潜在的な攻撃経路の包括的なビューを作成
2. 影響範囲（blast radius）— 特定されたアクティビティが影響を及ぼす可能性のある関連資産を特定
3. 推論モデルが過去の挙動、資産の特性、環境の脆弱性を考慮し、攻撃者が最も使用する可能性の高い経路を予測

## 予測シールドで実行される修復アクション

すべて **Defender for Endpoint** ベースのアクションです。

| アクション | 説明 |
|---|---|
| **SafeBoot Hardening（セーフブート強化）** | デバイスがセーフモードで起動することを防止。攻撃者がセキュリティ制御を回避し、永続性を維持するためにセーフモードを悪用する手法への対策 |
| **GPO Hardening（GPO 強化）** | グループポリシーオブジェクト（GPO）を強化し、攻撃者が GPO の設定ミスや脆弱性を悪用して特権昇格やラテラルムーブメントを行うことを防止 |
| **Proactive User Containment（プロアクティブなユーザー封じ込め）** | 露出データとアクティビティデータを組み合わせ、侵害・再利用されるリスクが高い資格情報を特定し、関連ユーザーのアクティビティを予防的に制限。既存セッションの終了ではなく、**新規セッションの作成を防止** する |

## GPO Hardening（GPO 強化）の詳細

### GPO が攻撃に悪用されるシナリオ

攻撃者が GPO を標的にする主な理由と手法：

| 攻撃手法 | 説明 |
|---|---|
| **GPO の設定ミスの悪用** | 過度に緩い権限が設定された GPO を改ざんし、悪意のあるスクリプトやソフトウェアをドメイン全体に配布 |
| **GPO を使ったラテラルムーブメント** | GPO にリンクされた OU 内のすべてのデバイスに対してリモート実行スクリプトやスケジュールタスクを展開 |
| **特権昇格** | GPO を変更してローカル管理者グループにアカウントを追加、またはセキュリティポリシーを弱体化 |
| **セキュリティ制御の無効化** | GPO 経由で Windows Defender やファイアウォールルール、監査ポリシーを無効化 |
| **ランサムウェアの横展開** | GPO のログオンスクリプトやソフトウェアインストール機能を使って、ランサムウェアをドメイン内の複数デバイスに一斉配布 |

### GPO Hardening が行うこと

予測シールドのグラフベース推論モデルが攻撃経路上にある GPO を特定した場合、以下の強化が**予防的に**適用されます。

1. **GPO 権限のロックダウン** — 攻撃者が GPO の編集権限を悪用できないよう、GPO オブジェクトへの書き込みアクセスを制限
2. **GPO リンクの保護** — 重要な OU へのリンク変更・追加を防止し、悪意のあるポリシーの適用範囲を限定
3. **GPO 経由のスクリプト実行の制限** — GPO を通じたスタートアップ/ログオンスクリプトの改ざん・追加を防止
4. **セキュリティポリシーの改ざん防止** — 監査ポリシー、パスワードポリシー、ファイアウォールルールなどのセキュリティ関連 GPO 設定の変更をブロック

### GPO Hardening の動作フロー

```
侵害検知 → 露出グラフ分析 → 攻撃経路上の GPO を特定 → GPO 強化ポリシーを対象デバイスに適用
```

1. **Prediction フェーズ**: 侵害されたアカウントや資産から、攻撃者が GPO を悪用して到達しうる資産をグラフベースで推論
2. **Enforcement フェーズ**: まだ侵害されていないデバイスに対して、Defender for Endpoint 経由で GPO 強化ポリシーをリアルタイムで適用
3. 攻撃者が当該 GPO を改ざんしようとしても、強化によりブロックされる

### Attack Disruption との違い（GPO 観点）

通常の Attack Disruption では**既に侵害されたデバイスを封じ込め（Contain Device）**ますが、Predictive Shielding の GPO Hardening は**まだ侵害されていないデバイスの GPO 設定を事前に強化**するプロアクティブなアクションです。既存の業務への影響を最小限に抑えつつ、攻撃経路を予防的に遮断します。

### GPO Hardening の確認方法

- **インシデントページ**: 「予測シールド」タグでフィルターし、[アクティビティ] > [応答] カテゴリで GPO Hardening アクションを確認
- **Advanced Hunting**: `DisruptionAndResponseEvents` テーブルで追跡
- **アクションセンター**: 適用された GPO 強化アクションの確認と、必要に応じた元に戻す操作

#### GPO Hardening ポリシーの追跡クエリ

```kusto
let hardeningPolicyType = "GPOHardening";
let lookBackTime = ago(7d);
DisruptionAndResponseEvents
| where Timestamp > lookBackTime
| where PolicyName == hardeningPolicyType
| summarize arg_max(Timestamp, IsPolicyOn) by DeviceId, DomainName
| where IsPolicyOn
```

> [!NOTE]
> Predictive Shielding はプレビュー段階の機能であり、GPO Hardening の具体的な実装詳細は GA（一般提供）時に変更される可能性があります。

## Attack Disruption との違い

| 項目 | Attack Disruption | 予測シールド |
|---|---|---|
| **対象** | 既に侵害された資産 | まだ侵害されていないがリスクがある資産 |
| **タイミング** | 攻撃検知後に反応的に封じ込め | 攻撃進行を予測し事前に保護 |
| **Contain User の動作** | 既存セッションも含め制限 | 新規セッションのみ制限（よりセレクティブ） |

## 確認・管理方法

- インシデントキューで **「予測シールド」タグ** でフィルター
- インシデントの **[アクティビティ]** タブ → **[応答]** カテゴリでフィルターして適用されたアクションを確認
- **Advanced Hunting** で `DisruptionAndResponseEvents` テーブルを使用し、ポリシーの変更やブロックされたイベントを追跡
- アクション センターまたはアクティビティタブから **アクションを元に戻す** ことも可能

### Advanced Hunting クエリ例

#### 有効な強化ポリシーの追跡

```kusto
let hardeningPolicyType = "";
let lookBackTime = datetime("");
DisruptionAndResponseEvents
| where Timestamp > lookBackTime
| where PolicyName == hardeningPolicyType
| where DomainName == domainName
| summarize arg_max(Timestamp, IsPolicyOn) by DeviceId
| where IsPolicyOn
```
