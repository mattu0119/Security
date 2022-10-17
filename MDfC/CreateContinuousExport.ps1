$subID = "YOUR-SUBSCRIPTION-ID"
$rgName = "YOUR-RESOURCEGROUP-NAME"
$automationName = "YOUR-AUTOMATION-NAME"
$laId = "YOUR-LOGANALYTICS-ID"
$guid = "195a64a1-5869-4b41-96ba-4b45d62914b3"

$body = @{
    location   = "japaneast"
    etag = $guid
    tags = @{}
    properties = @{
        description = "1014test01"
        isEnabled   = $true
        scopes      = @(
            @{
                scopePath = "/subscriptions/$subID"
                description = "scope for /subscriptions/$subID"
            }
        )
        sources     = @(
            @{
                EventSource = "Assessments"
                RuleSets    = @(
                    @{
                        Rules = @(
                            @{
                                PropertyJPath    = "type"
                                PropertyType     = "String"
                                ExpectedValue    = "Microsoft.Security/assessments"
                                operator = "Contains"        
                            }
                        )
                    }
                )

            }
            @{
                EventSource = "AssessmentsSnapshot"
                RuleSets    = @(
                    @{
                        Rules = @(
                            @{
                                PropertyJPath    = "type"
                                PropertyType     = "String"
                                ExpectedValue    = "Microsoft.Security/assessments"
                                operator = "Contains"        
                            }
                        )
                    }
                )
            }
            @{
                EventSource = "SubAssessments"
                RuleSets    = $null
            }
            @{
                EventSource = "SubAssessmentsSnapshot"
                RuleSets    = $null

            }
            @{
                EventSource = "Alerts"
                RuleSets    = @(
                    @{
                        Rules = @(
                            @{
                                PropertyJPath    = "Severity"
                                PropertyType     = "String"
                                ExpectedValue    = "low"
                                operator = "Equals"        
                            }
                            @{
                                PropertyJPath    = "Severity"
                                PropertyType     = "String"
                                ExpectedValue    = "medium"
                                operator = "Equals"        
                            }
                            @{
                                PropertyJPath    = "Severity"
                                PropertyType     = "String"
                                ExpectedValue    = "informational"
                                operator = "Equals"        
                            }
                            @{
                                PropertyJPath    = "Severity"
                                PropertyType     = "String"
                                ExpectedValue    = "high"
                                operator = "Equals"        
                            }
                        )
                    }
                )
            }
            @{
                EventSource = "SecureScores"
                RuleSets    = $null

            }
            @{
                EventSource = "SecureScoresSnapshot"
                RuleSets    = $null

            }
            @{
                EventSource = "SecureScoreControls"
                RuleSets    = $null

            }
            @{
                EventSource = "SecureScoreControlsSnapshot"
                RuleSets    = $null

            }
            @{
                EventSource = "RegulatoryComplianceAssessment"
                RuleSets    = $null

            }
            @{
                EventSource = "RegulatoryComplianceAssessmentSnapshot"
                RuleSets    = $null

            }
            
        )
        actions     = @(
            @{
                workspaceResourceId = $laId
                actionType = "Workspace"
            }
        )
    }
} | ConvertTo-Json -Depth 100

Invoke-azrest -Path "/subscriptions/$subID/resourceGroups/$rgName/providers/Microsoft.Security/automations/$automationName`?api-version=2019-01-01-preview" -Method PUT -Payload $body