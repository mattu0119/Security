## 各テーブルの EPS 算出クエリ
* [EPS calculation and log size](https://techcommunity.microsoft.com/t5/microsoft-sentinel/eps-calculation-and-log-size/m-p/2007929)
* [Log Analytics table reference](https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/tables-category?WT.mc_id=facebook&fbclid=IwAR26Pudzbd9p6Ow02A7cfmYzor5EFZg_Zn6TLz0eIN4CG_HVKJogn_muI7w)

```kql
union withsource=_TableName1 *
| where _TimeReceived  > ago(1d)
| summarize count() , Size = sum(_BilledSize) by bin(_TimeReceived, 1m), Type, _IsBillable, _BilledSize
| extend counttemp =count_ / 60
| summarize 
           ['Average Events per Second (eps)'] = avg(counttemp),
           ['Average Bytes']=avg(_BilledSize),
           //['Bytes']=avg(counttemp) * avg(_BilledSize),
           ['Minimum eps']=min (counttemp),
           ['Maximum eps']=max(counttemp)
  by ['Table Name']=Type
| order  by ['Average Events per Second (eps)'] desc
===