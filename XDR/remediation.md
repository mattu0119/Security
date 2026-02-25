# Microsoft Defender XDR の修復アクション（Remediation Actions）

Defender XDR の修復アクションは、自動調査やセキュリティチームの手動操作によって脅威を修復するためのアクションです。

## 修復アクションの種類

### デバイス（エンドポイント）

- 調査パッケージの収集
- デバイスの分離（元に戻すことが可能）
- マシンのオフボード
- コード実行の解放
- 検疫からの解放
- サンプルの要求
- コード実行の制限（元に戻すことが可能）
- ウイルス対策スキャンの実行
- 停止と検疫
- ネットワークからのデバイスの封じ込め

### メール

- URL のブロック（クリック時）
- メールメッセージまたはクラスターの論理削除
- メールの検疫
- メール添付ファイルの検疫
- 外部メール転送の無効化

### ユーザー（アカウント）

- ユーザーの無効化
- ユーザーパスワードのリセット
- ユーザーを侵害済みとして確認

---

## 自動実行 vs 承認待ち vs 手動実行

### 自動実行

- デバイスグループの自動化レベルが「**Full - remediate threats automatically**」に設定されている場合、悪意のある（Malicious）判定が出ると修復アクションが自動で実行される
- 侵害された（Compromised）ユーザーに対するアクションも自動で実行される

### 承認待ち

- メールコンテンツ（URL・添付ファイル）が悪意あり（Malicious）と判定された場合
- デバイスまたはメールコンテンツが疑わしい（Suspicious）と判定された場合

### 手動実行

- デバイスの分離やファイルの検疫
- メールの論理削除
- ユーザーの無効化やパスワードリセット
- Advanced Hunting からのアクション
- Explorer によるメール操作（迷惑メールへの移動、論理削除、物理削除）
- Live Response によるアクション（ファイル削除、プロセス停止、スケジュールタスクの削除）
- Defender for Endpoint API によるアクション

---

## 判定（Verdict）と結果

| 判定 | 対象エンティティ | 結果 |
|---|---|---|
| Malicious（悪意あり） | デバイス | 自動で修復（自動化レベルによる） |
| Compromised（侵害済み） | ユーザー | 自動で修復 |
| Malicious（悪意あり） | メールコンテンツ（URL/添付ファイル） | 承認待ち |
| Suspicious（疑わしい） | デバイス/メール | 承認待ち |
| No threats found（脅威なし） | デバイス/メール | アクション不要 |

---

## アクション センター（Action Center）

すべての修復アクション（承認待ち・完了済み）は **Action Center** で確認・管理できます。

- **URL**: <https://security.microsoft.com/action-center>

### Pending（承認待ち）タブ

1. Microsoft Defender ポータル（<https://security.microsoft.com>）にサインイン
2. ナビゲーションの **Actions and submissions** > **Action center** を選択
3. **Pending** タブで項目を選択
4. **Approve**（承認）または **Reject**（拒否）を選択

### History（履歴）タブ

完了済みのアクションを確認できます。以下のアクションは **元に戻す（Undo）** ことが可能です：

| 元に戻せるアクション |
|---|
| デバイスの分離 |
| デバイスの封じ込め |
| ユーザーの封じ込め |
| コード実行の制限 |
| ファイルの検疫 |
| レジストリキーの削除 |
| サービスの停止 |
| ドライバーの無効化 |
| スケジュールタスクの削除 |

---

## 必要な権限

- 修復アクションの承認/拒否には **セキュリティ管理者** または **グローバル管理者** の権限が必要
- 元に戻す（Undo）操作も同様に管理者権限が必要

---

## 参考リンク

- [Remediation actions in Microsoft Defender XDR](https://learn.microsoft.com/en-us/defender-xdr/m365d-remediation-actions)
- [View and manage actions in the Action center](https://learn.microsoft.com/en-us/defender-xdr/m365d-autoir-actions)
- [Configure automated investigation and response](https://learn.microsoft.com/en-us/defender-xdr/m365d-configure-auto-investigation-response)