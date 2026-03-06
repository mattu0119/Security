# Playbook ARM Template Generator

Azure Logic Apps (Playbook) の定義と関連する API コネクションを ARM テンプレートとしてエクスポートする PowerShell スクリプトです。  
Azure Sentinel ギャラリー形式での出力にも対応しています。

## 前提条件

- **PowerShell** 5.0 以上
- **Azure PowerShell モジュール**
  - `Az.Accounts`
  - `Az.Resources`
  - `Az.OperationalInsights`
- **権限**: Logic App リソース (`Microsoft.Logic/workflows/read`) および API コネクション / コネクタへの読み取りアクセス
- **OS**: Windows（フォルダ選択ダイアログに Windows Forms を使用）

## パラメーター

| パラメーター | 型 | 必須 | 説明 |
|---|---|---|---|
| `TenantID` | string | ○ | Logic Apps がデプロイされている Azure テナント ID |

## 使い方

```powershell
.\Playbook_ARM_Template_Generator.ps1 -TenantID "<テナントID>"