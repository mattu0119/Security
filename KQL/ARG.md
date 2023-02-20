## ARG クエリ
securityresources
| where type == "microsoft.security/securescores/securescorecontrols"
| extend secureScoreName = (extract("/providers/Microsoft.Security/secureScores/([^/]*)/",1, id))
| where secureScoreName == "ascScore"