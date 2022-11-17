## 各テーブルの EPS 算出クエリ


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