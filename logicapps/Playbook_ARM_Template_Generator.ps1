<#       
  	THE SCRIPT IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SCRIPT OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.

    .SYNOPSIS
        This PowerShell script generates ARM Template for Azure LogicApp with all the connections

    .DESCRIPTION
        Generates ARM Template for Azure LogicApp with all the connections
    
    .PARAMETER TenantID
        Enter the TenantID (required)
    
    .PARAMETER GenerateForGallery
        Enter the boolean - True or False

    .NOTES
        AUTHOR: Sreedhar Ande, Itai Yankelevsky
        LASTEDIT: 4-15-2022

    .EXAMPLE
        .\GenerateARMTemplate_V2 -TenantID xxxx -GenerateForGallery true 
#>

param(    
    [parameter(Mandatory = $true, HelpMessage = "Enter the Tenant Id")]    
    [string]$TenantID  
)

#region HelperFunctions
Function Write-Log {
    <#
    .DESCRIPTION 
    Write-Log is used to write information to a log file and to the console.
    
    .PARAMETER Severity
    parameter specifies the severity of the log message. Values can be: Information, Warning, or Error. 
    #>

    [CmdletBinding()]
    param(
        [parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message,
        [string]$LogFileName,
 
        [parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$Severity = 'Information'
    )

    $messageToWrite = if ([string]::IsNullOrWhiteSpace($Message)) { "<empty message>" } else { $Message }

    # Write the message out to the correct channel											  
    switch ($Severity) {
        "Information" { Write-Host $messageToWrite -ForegroundColor Green }
        "Warning" { Write-Host $messageToWrite -ForegroundColor Yellow }
        "Error" { Write-Host $messageToWrite -ForegroundColor Red }
    } 											  
    try {
        [PSCustomObject] [ordered] @{
            Time     = (Get-Date -f g)
            Message  = $messageToWrite
            Severity = $Severity
        } | Export-Csv -Path "$PSScriptRoot\$LogFileName" -Append -NoTypeInformation -Force
    }
    catch {
        Write-Error "An error occurred in Write-Log() method" -ErrorAction SilentlyContinue		
    }    
}

Function Get-RequiredModules {
    <#
    .DESCRIPTION 
    Get-Required is used to install and then import a specified PowerShell module.
    
    .PARAMETER Module
    parameter specifices the PowerShell module to install. 
    #>

    [CmdletBinding()]
    param (        
        [parameter(Mandatory = $true)] $Module        
    )
    
    try {
        $installedModule = Get-InstalledModule -Name $Module -ErrorAction SilentlyContinue       

        if ($null -eq $installedModule) {
            Write-Log -Message "The $Module PowerShell module was not found" -LogFileName $LogFileName -Severity Warning
            #check for Admin Privleges
            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

            if (-not ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
                #Not an Admin, install to current user            
                Write-Log -Message "Can not install the $Module module. You are not running as Administrator" -LogFileName $LogFileName -Severity Warning
                Write-Log -Message "Installing $Module module to current user Scope" -LogFileName $LogFileName -Severity Warning
                
                Install-Module -Name $Module -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
                Import-Module -Name $Module -Force
            }
            else {
                #Admin, install to all users																		   
                Write-Log -Message "Installing the $Module module to all users" -LogFileName $LogFileName -Severity Warning
                Install-Module -Name $Module -Repository PSGallery -Force -AllowClobber
                Import-Module -Name $Module -Force
            }
        }
        else {
            if ($UpdateAzModules) {
                Write-Log -Message "Checking updates for module $Module" -LogFileName $LogFileName -Severity Information
                $currentVersion = [Version](Get-InstalledModule | Where-Object {$_.Name -eq $Module}).Version
                # Get latest version from gallery
                $latestVersion = [Version](Find-Module -Name $Module).Version
                if ($currentVersion -ne $latestVersion) {
                    #check for Admin Privleges
                    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

                    if (-not ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
                        #install to current user            
                        Write-Log -Message "Can not update the $Module module. You are not running as Administrator" -LogFileName $LogFileName -Severity Warning
                        Write-Log -Message "Updating $Module from [$currentVersion] to [$latestVersion] to current user Scope" -LogFileName $LogFileName -Severity Warning
                        Update-Module -Name $Module -RequiredVersion $latestVersion -Force
                    }
                    else {
                        #Admin - Install to all users																		   
                        Write-Log -Message "Updating $Module from [$currentVersion] to [$latestVersion] to all users" -LogFileName $LogFileName -Severity Warning
                        Update-Module -Name $Module -RequiredVersion $latestVersion -Force
                    }
                }
                else {
                    $latestVersion = [Version](Get-Module -Name $Module).Version               
                    Write-Log -Message "Importing module $Module with version $latestVersion" -LogFileName $LogFileName -Severity Information
                    Import-Module -Name $Module -RequiredVersion $latestVersion -Force
                }
            }
            else {                
                # Get latest version
                $latestVersion = [Version](Get-Module -Name $Module).Version               
                Write-Log -Message "Importing module $Module with version $latestVersion" -LogFileName $LogFileName -Severity Information
                Import-Module -Name $Module -RequiredVersion $latestVersion -Force
                
            }
        }
        # Install-Module will obtain the module from the gallery and install it on your local machine, making it available for use.
        # Import-Module will bring the module and its functions into your current powershell session, if the module is installed.  
    }
    catch {
        Write-Log -Message "An error occurred in Get-RequiredModules() method - $($_)" -LogFileName $LogFileName -Severity Error        
    }
}

Function Get-FolderName {
    Add-Type -AssemblyName System.Windows.Forms
    $FolderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $FolderBrowser.Description = 'Select the folder containing the data'
    Try {
        $result = $FolderBrowser.ShowDialog((New-Object System.Windows.Forms.Form -Property @{TopMost = $true; TopLevel = $true }))
        if ($result -eq [Windows.Forms.DialogResult]::OK){
            return $FolderBrowser.SelectedPath
        } 
    }
    catch {
        Write-Log -Message "Error occured in Get-FolderName :$($_)" -LogFileName $LogFileName -Severity Error
        exit
    }
} #end function Get-FolderName

function Confirmation-Dlg {
    [CmdletBinding()]
    param (        
        [parameter(Mandatory = $true)] $DlgMessage        
    )
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $logselectform = New-Object System.Windows.Forms.Form
    $logselectform.Text = 'Confirmation'
    $logselectform.AutoSize = $false
    $logselectform.Size = New-Object System.Drawing.Size(450,360)
    $logselectform.StartPosition = 'CenterScreen'

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(10,20)
    $label.Size = New-Object System.Drawing.Size(350,120)
    $label.AutoSize = $false
    $label.Text = $DlgMessage
    $logselectform.Controls.Add($label)

    $okb = New-Object System.Windows.Forms.Button
    $okb.Location = New-Object System.Drawing.Point(165,225)
    $okb.Size = New-Object System.Drawing.Size(75,25)
    $okb.Text = 'Ok'
    $okb.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $logselectform.AcceptButton = $okb
    $logselectform.Controls.Add($okb)

    $logselectform.ShowDialog((New-Object System.Windows.Forms.Form -Property @{TopMost = $true; TopLevel = $true }))
    
}
#endregion


#region MainFunctions
# Taken from https://stackoverflow.com/questions/56322993/proper-formating-of-json-using-powershell/56324939
Function FixJsonIndentation ($jsonOutput) {
    Try {
        $currentIndent = 0
        $tabSize = 4
        $lines = $jsonOutput.Split([Environment]::NewLine)
        $newString = ""
        foreach ($line in $lines)
        {
            # skip empty line
            if ($line.Trim() -eq "") {
                continue
            }

            # if the line with ], or }, reduce indent
            if ($line -match "[\]\}]+\,?\s*$") {
                $currentIndent -= 1
            }

            # add the line with the right indent
            if ($newString -eq "") {
                $newString = $line
            } else {
                $spaces = ""
                $matchFirstChar = [regex]::Match($line, '[^\s]+')
                
                $totalSpaces = $currentIndent * $tabSize
                if ($totalSpaces -gt 0) {
                    $spaces = " " * $totalSpaces
                }
                
                $newString += [Environment]::NewLine + $spaces + $line.Substring($matchFirstChar.Index)
            }

            # if the line with { or [ increase indent
            if ($line -match "[\[\{]+\s*$") {
                $currentIndent += 1
            }
        }
        return $newString
    }
    catch {
        Write-Log -Message "Error occured in FixJsonIndentation :$($_)" -LogFileName $LogFileName -Severity Error
    }
}

Function BuildPlaybookArmId() {
    Try {
        if ($PlaybookSubscriptionId -and $PlaybookResourceGroupName -and $PlaybookResourceName) {
            return "/subscriptions/$PlaybookSubscriptionId/resourceGroups/$PlaybookResourceGroupName/providers/Microsoft.Logic/workflows/$PlaybookResourceName"
        }
    }
    catch {
        Write-Log -Message "Playbook full ARM id, or subscription, resource group and resource name are required: $($_)" -LogFileName $LogFileName -Severity Error
    }
}

Function ConvertFrom-Base64Url([string]$base64Url) {
    if ([string]::IsNullOrWhiteSpace($base64Url)) {
        return $null
    }
    $s = $base64Url.Replace('-', '+').Replace('_', '/')
    switch ($s.Length % 4) {
        2 { $s += '==' }
        3 { $s += '=' }
        0 { }
        default { }
    }
    try {
        $bytes = [Convert]::FromBase64String($s)
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    catch {
        return $null
    }
}

Function Get-JwtPayload([string]$jwt) {
    if ([string]::IsNullOrWhiteSpace($jwt)) {
        return $null
    }
    $parts = $jwt.Split('.')
    if ($parts.Count -lt 2) {
        return $null
    }
    $payloadJson = ConvertFrom-Base64Url -base64Url $parts[1]
    if ([string]::IsNullOrWhiteSpace($payloadJson)) {
        return $null
    }
    try {
        return $payloadJson | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

Function ConvertTo-PlainTextToken($token) {
    if ($null -eq $token) {
        return $null
    }
    if ($token -is [System.Security.SecureString]) {
        try {
            return (New-Object System.Net.NetworkCredential('', $token)).Password
        }
        catch {
            return $null
        }
    }
    return [string]$token
}

Function Get-ArmAccessToken([string]$armResourceUrl, [string]$tenantId) {
    # Prefer a token explicitly scoped for ARM.
    try {
        $t = (Get-AzAccessToken -ResourceTypeName Arm -TenantId $tenantId).Token
        return ConvertTo-PlainTextToken -token $t
    }
    catch {
        # Older Az.Accounts may not support ResourceTypeName
    }

    try {
        $t = (Get-AzAccessToken -ResourceUrl $armResourceUrl -TenantId $tenantId).Token
        return ConvertTo-PlainTextToken -token $t
    }
    catch {
        # Older Az.Accounts may not support TenantId/ResourceUrl
    }

    $t = (Get-AzAccessToken).Token
    return ConvertTo-PlainTextToken -token $t
}

Function SendArmGetCall($relativeUrl, [switch]$ThrowOnError) {
    $authHeader = @{
        'Authorization'='Bearer ' + $tokenToUse
    }

    $absoluteUrl = $armHostUrl+$relativeUrl
    Try {
        $result = Invoke-RestMethod -Uri $absoluteUrl -Method Get -Headers $authHeader -ErrorAction Stop
        Write-Log -Message "ARM GET succeeded: $absoluteUrl" -LogFileName $LogFileName -Severity Information
        return $result
    }
    catch {                    
        $statusCode = $null
        $statusDescription = $null
        $responseBody = $null

        # Often contains JSON error payload for Invoke-RestMethod failures
        try {
            if ($_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace($_.ErrorDetails.Message)) {
                $responseBody = $_.ErrorDetails.Message
            }
        } catch { }

        # Windows PowerShell: System.Net.WebException w/ HttpWebResponse
        # PowerShell 7+: HttpResponseException w/ HttpResponseMessage
        $resp = $null
        try { $resp = $_.Exception.Response } catch { $resp = $null }

        if ($resp -and [string]::IsNullOrWhiteSpace($responseBody)) {
            try {
                if ($resp.PSObject.Properties.Name -contains 'StatusCode') {
                    $statusCode = $resp.StatusCode
                }
                elseif ($resp.PSObject.Properties.Name -contains 'Status') {
                    $statusCode = $resp.Status
                }
            } catch { }

            try {
                if ($resp.PSObject.Properties.Name -contains 'StatusDescription') {
                    $statusDescription = $resp.StatusDescription
                }
                elseif ($resp.PSObject.Properties.Name -contains 'ReasonPhrase') {
                    $statusDescription = $resp.ReasonPhrase
                }
            } catch { }

            try {
                if ($resp.PSObject.Properties.Name -contains 'GetResponseStream') {
                    $stream = $resp.GetResponseStream()
                    if ($stream) {
                        $reader = New-Object System.IO.StreamReader($stream)
                        $responseBody = $reader.ReadToEnd()
                    }
                }
                elseif ($resp.Content) {
                    # PS7 HttpResponseMessage.Content is HttpContent; call method directly.
                    try {
                        $responseBody = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    } catch {
                        $responseBody = [string]$resp.Content
                    }
                }
            } catch { }
        }

        $sc = if ($null -ne $statusCode -and -not [string]::IsNullOrWhiteSpace([string]$statusCode)) { [string]$statusCode } else { '<unknown>' }
        $sd = if ($null -ne $statusDescription -and -not [string]::IsNullOrWhiteSpace([string]$statusDescription)) { [string]$statusDescription } else { '<no description>' }
        $statusLine = ("{0} {1}" -f $sc, $sd).Trim()
        Write-Log -Message "ARM GET failed: $absoluteUrl" -LogFileName $LogFileName -Severity Error
        Write-Log -Message "Status: $statusLine" -LogFileName $LogFileName -Severity Error
        if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
            Write-Log -Message ("Response body: {0}" -f $responseBody) -LogFileName $LogFileName -Severity Error
        }

        if ($ThrowOnError) {
            throw
        }
        return $null
    } 
}

Function GetPlaybookResource() {
    Try {    
        $playbookArmIdToUse = BuildPlaybookArmId
        $playbookResource = SendArmGetCall -relativeUrl "$($playbookArmIdToUse)?api-version=2017-07-01" -ThrowOnError

        if ($null -eq $playbookResource) {
            throw "Failed to read playbook resource via ARM. Check RBAC (Microsoft.Logic/workflows/read) and authentication."
        }
        
        $PlaybookARMParameters.Add("PlaybookName", [ordered] @{
            "defaultValue"= $playbookResource.Name
            "type"= "string"
        })

        # Update properties to fit ARM template structure
        if ($GenerateForGallery) {
            if (!("tags" -in $playbookResource.PSobject.Properties.Name)) {
                Add-Member -InputObject $playbookResource -Name "tags" -Value @() -MemberType NoteProperty -Force
            }

            if (!$playbookResource.tags) {
                $playbookResource.tags = [ordered] @{
                    "hidden-SentinelTemplateName"= $playbookResource.name
                    "hidden-SentinelTemplateVersion"= "1.0"
                }
            }
            else {
                if (!$playbookResource.tags["hidden-SentinelTemplateName"]) {
                    Add-Member -InputObject $playbookResource.tags -Name "hidden-SentinelTemplateName" -Value $playbookResource.name -MemberType NoteProperty -Force
                }

                if (!$playbookResource.tags["hidden-SentinelTemplateVersion"]) {
                    Add-Member -InputObject $playbookResource.tags -Name "hidden-SentinelTemplateVersion" -Value "1.0" -MemberType NoteProperty -Force
                }
            }

            # The azuresentinel connection will use MSI when exported for the gallery, so the playbook must support it too
            if ($playbookResource.identity.type -ne "SystemAssigned") {
                if (!$playbookResource.identity) {
                    Add-Member -InputObject $playbookResource -Name "identity" -Value @{
                        "type"= "SystemAssigned"
                    } -MemberType NoteProperty -Force
                }
                else {
                    $playbookResource.identity = @{
                        "type"= "SystemAssigned"
                    }
                }
            }
        }

        $playbookResource.PSObject.Properties.remove("id")
        $playbookResource.location = "[resourceGroup().location]"
        $playbookResource.name = "[parameters('PlaybookName')]"
        Add-Member -InputObject $playbookResource -Name "apiVersion" -Value "2017-07-01" -MemberType NoteProperty
        Add-Member -InputObject $playbookResource -Name "dependsOn" -Value @() -MemberType NoteProperty

        # Remove properties specific to an instance of a deployed playbook
        $playbookResource.properties.PSObject.Properties.remove("createdTime")
        $playbookResource.properties.PSObject.Properties.remove("changedTime")
        $playbookResource.properties.PSObject.Properties.remove("version")
        $playbookResource.properties.PSObject.Properties.remove("accessEndpoint")
        $playbookResource.properties.PSObject.Properties.remove("endpointsConfiguration")

        if ($playbookResource.identity) {
            $playbookResource.identity.PSObject.Properties.remove("principalId")
            $playbookResource.identity.PSObject.Properties.remove("tenantId")
        }

        return $playbookResource
    }
    Catch {
        Write-Log -Message "Error occured in GetPlaybookResource :$($_)" -LogFileName $LogFileName -Severity Error
    }
}

Function HandlePlaybookApiConnectionReference($apiConnectionReference, $playbookResource) {
    Try {
        # $apiConnectionReference.Name is the *reference key* in $connections (e.g. teams, teams-2, teams-3)
        # $apiConnectionReference.Value.id points to the *connector* (e.g. .../managedApis/teams)
        $referenceKey = $apiConnectionReference.Name
        $referenceKey = $referenceKey.Split('_')[0].ToString().Trim()

        # Prefer connector API name from the exported reference (managedApis/<name>), not from the reference key.
        $connectorApiName = $null
        $connectorTypeFromId = $null
        try {
            if ($apiConnectionReference.Value -and $apiConnectionReference.Value.id) {
                $idString = [string]$apiConnectionReference.Value.id
                if ($idString -match '/(managedApis|customApis)/([A-Za-z0-9-]+)') {
                    $connectorTypeFromId = $Matches[1]
                    $connectorApiName = $Matches[2]
                }
            }
        } catch { }

        if ([string]::IsNullOrWhiteSpace($connectorApiName)) {
            # Fallback to previous behavior
            $connectorApiName = $referenceKey
        }
        $connectorApiName = $connectorApiName.ToLowerInvariant()

        $connectionName = (Get-Culture).TextInfo.ToTitleCase($connectorApiName)

        if ($connectionName -ieq "azuresentinel") {
            $connectionVariableName = "MicrosoftSentinelConnectionName" 
        } else {
            $connectionVariableName = "$($connectionName)ConnectionName"
        }
        $connectorType = if ($connectorTypeFromId) {
            $connectorTypeFromId
        } else {
            if ($apiConnectionReference.Value.id -and ([string]$apiConnectionReference.Value.id).ToLowerInvariant().Contains("/managedapis/")) { "managedApis" } else { "customApis" }
        }
        $connectionAuthenticationType = if ($apiConnectionReference.Value.connectionProperties.authentication.type -eq "ManagedServiceIdentity") { "Alternative" } else  { $null }
        
        # We always convert azuresentinel connections to MSI during export
        if ($GenerateForGallery -and $connectionName -eq "azuresentinel" -and !$connectionAuthenticationType) {
            $connectionAuthenticationType = "Alternative"

            if (!$apiConnectionReference.Value.ConnectionProperties) {
                Add-Member -InputObject $apiConnectionReference.Value -Name "ConnectionProperties" -Value @{} -MemberType NoteProperty
            }
            $apiConnectionReference.Value.connectionProperties = @{
                "authentication"= @{
                    "type"= "ManagedServiceIdentity"
                }
            }
        }

        # Deduplicate: if multiple $connections keys reference the same underlying connectionId,
        # generate only one Microsoft.Web/connections resource and point all references to it.
        $sourceConnectionId = $null
        try { $sourceConnectionId = [string]$apiConnectionReference.Value.connectionId } catch { $sourceConnectionId = $null }
        if ([string]::IsNullOrWhiteSpace($sourceConnectionId)) {
            $sourceConnectionId = "$connectorType/$connectorApiName"
        }
        $authKey = if ($connectionAuthenticationType) { [string]$connectionAuthenticationType } else { "" }
        $dedupKey = ("{0}|{1}" -f $sourceConnectionId.ToLowerInvariant(), $authKey.ToLowerInvariant())

        if ($null -ne $script:ConnectionExportCache -and $script:ConnectionExportCache.ContainsKey($dedupKey)) {
            $cached = $script:ConnectionExportCache[$dedupKey]
            $connectionVariableName = $cached.connectionVariableName
            $connectorType = $cached.connectorType
            $connectorApiName = $cached.connectorApiName

            $apiConnectionReference.Value = [ordered] @{
                "connectionId"= "[resourceId('Microsoft.Web/connections', variables('$connectionVariableName'))]"
                "connectionName" = "[variables('$connectionVariableName')]"
                "id" = "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/$connectorType/$connectorApiName')]"
                "connectionProperties" = $apiConnectionReference.Value.connectionProperties
            }
            if (!$apiConnectionReference.Value.connectionProperties) {
                $apiConnectionReference.Value.Remove("connectionProperties")
            }

            # Ensure dependsOn includes the shared connection (only once)
            $dependsExpr = "[resourceId('Microsoft.Web/connections', variables('$connectionVariableName'))]"
            if (-not ($playbookResource.dependsOn -contains $dependsExpr)) {
                $playbookResource.dependsOn += $dependsExpr
            }
            return
        }

        $existingConnectionProperties = $null
        try {
            $existingConnectionProperties = SendArmGetCall -relativeUrl "$($apiConnectionReference.Value.connectionId)?api-version=2016-06-01"
        } catch {
            $existingConnectionProperties = $null
        }

        $existingConnectorProperties = $null
        try {
            $existingConnectorProperties = SendArmGetCall -relativeUrl "$($apiConnectionReference.Value.id)?api-version=2016-06-01"
        } catch {
            $existingConnectorProperties = $null
        }

        $canExportConnectorParameters = $true
        if ($null -eq $existingConnectorProperties -or $null -eq $existingConnectionProperties) {
            $canExportConnectorParameters = $false
            Write-Log -Message "Skipping connector parameter export for $connectionName (insufficient access or connector metadata unavailable)." -LogFileName $LogFileName -Severity Warning
        }

        # Ensure variable key exists only once
        if (-not $templateVariables.Contains($connectionVariableName)) {
            if ($connectionName -ieq "azuresentinel") {
                $templateVariables.Add($connectionVariableName, "[concat('MicrosoftSentinel-', parameters('PlaybookName'))]")
            } else {
                $templateVariables.Add($connectionVariableName, "[concat('$connectionName-', parameters('PlaybookName'))]")
            }
        }

        # Create API connection resource
        $apiConnectionResource = [ordered] @{
            "type"= "Microsoft.Web/connections"
            "apiVersion"= "2016-06-01"
            "name"= "[variables('$connectionVariableName')]"
            "location"= "[resourceGroup().location]"
            "kind"= "V1"
            "properties"= [ordered] @{
                "displayName"= "[variables('$connectionVariableName')]"
                "customParameterValues"= [ordered] @{}
                "parameterValueType"= $connectionAuthenticationType
                "api"= [ordered] @{
                    "id"= "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/$connectorType/$connectorApiName')]"
                }
            }
        }
        if (!$apiConnectionResource.properties.parameterValueType) {
            $apiConnectionResource.properties.Remove("parameterValueType")
        }
            
        $apiConnectionResources.Add($apiConnectionResource) | Out-Null

        if ($null -ne $script:ConnectionExportCache) {
            $script:ConnectionExportCache[$dedupKey] = [ordered]@{
                connectionVariableName = $connectionVariableName
                connectorType = $connectorType
                connectorApiName = $connectorApiName
            }
        }

        # Update API connection reference in the playbook resource
        $apiConnectionReference.Value = [ordered] @{
            "connectionId"= "[resourceId('Microsoft.Web/connections', variables('$connectionVariableName'))]"
            "connectionName" = "[variables('$connectionVariableName')]"
            "id" = "[concat('/subscriptions/', subscription().subscriptionId, '/providers/Microsoft.Web/locations/', resourceGroup().location, '/$connectorType/$connectorApiName')]"
            "connectionProperties" = $apiConnectionReference.Value.connectionProperties
        }
        if (!$apiConnectionReference.Value.connectionProperties) {
            $apiConnectionReference.Value.Remove("connectionProperties")
        }
        $dependsExpr = "[resourceId('Microsoft.Web/connections', variables('$connectionVariableName'))]"
        if (-not ($playbookResource.dependsOn -contains $dependsExpr)) {
            $playbookResource.dependsOn += $dependsExpr
        }
        
        if ($canExportConnectorParameters -and $existingConnectorProperties.properties -and $existingConnectorProperties.properties.connectionAlternativeParameters) {
            # Evaluate and add connection-specific parameters
            Foreach ($connectorParameter in $existingConnectorProperties.properties.connectionAlternativeParameters.PSObject.Properties) {
                if ($connectorParameter.Name -eq "authentication" -or $connectorParameter -match "token:") {
                    continue
                }

                $matchingConnectionValue = $null
                try {
                    $matchingConnectionValue = $existingConnectionProperties.properties.alternativeParameterValues.$($connectorParameter.Name)
                } catch {
                    $matchingConnectionValue = $null
                }

                $templateParameters.Add($connectorParameter.Name, [ordered] @{
                    "defaultValue"= $matchingConnectionValue
                    "type"= $connectorParameter.Value.type
                })
            }
        }
    }
    Catch {
        Write-Log -Message "Error occured in HandlePlaybookApiConnectionReference :$($_)" -LogFileName $LogFileName -Severity Error
    }
}

Function BuildArmTemplate($playbookResource) {
    Try {
        $armTemplate = [ordered] @{
            '$schema'= "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
            "contentVersion"= "1.0.0.0"
            "parameters"= $PlaybookARMParameters
            "variables"= $templateVariables
            "resources"= @($playbookResource)+$apiConnectionResources
        }

        if ($GenerateForGallery) {
            $armTemplate.Insert(2, "metadata", [ordered] @{
                "title"= ""
                "description"= ""
                "prerequisites"= ""
                "postDeployment" = @()
                "prerequisitesDeployTemplateFile"= ""
                "lastUpdateTime"= ""
                "entities"= @()
                "tags"= @()
                "support"= [ordered] @{
                    "tier"= "community"
                    "armtemplate" = "Generated from https://github.com/Azure/Azure-Sentinel/tree/master/Tools/Playbook-ARM-Template-Generator"
                }
                "author"= @{
                    "name"= ""
                }
            })
        }

        return $armTemplate
    }
    Catch {
        Write-Log -Message "Error occured in BuildArmTemplate :$($_)" -LogFileName $LogFileName -Severity Error
    }
}

#endregion

#region DriverProgram

$TemplateGalleryQuestion = "Generate ARM Template for Gallery?"
$TemplateGalleryQuestionChoices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
$TemplateGalleryQuestionChoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
$TemplateGalleryQuestionChoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

$TemplateGalleryQuestionDecision = $Host.UI.PromptForChoice($title, $TemplateGalleryQuestion, $TemplateGalleryQuestionChoices, 0)

if ($TemplateGalleryQuestionDecision -eq 0) {
    $GenerateForGallery = $true
}
else {
    $GenerateForGallery = $false
}

$AzModulesQuestion = "Do you want to update required Az Modules to latest version?"
$AzModulesQuestionChoices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
$AzModulesQuestionChoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
$AzModulesQuestionChoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

$AzModulesQuestionDecision = $Host.UI.PromptForChoice($title, $AzModulesQuestion, $AzModulesQuestionChoices, 1)

if ($AzModulesQuestionDecision -eq 0) {
    $UpdateAzModules = $true
}
else {
    $UpdateAzModules = $false
}

Get-RequiredModules("Az.Accounts")
Get-RequiredModules("Az.Resources")
Get-RequiredModules("Az.OperationalInsights")

# Check Powershell version, needs to be 5 or higher
if ($host.Version.Major -lt 5) {
    Write-Log -Message "Supported PowerShell version for this script is 5 or above" -LogFileName $LogFileName -Severity Error    
    exit
}

$TimeStamp = Get-Date -Format yyyyMMdd_HHmmss 
$LogFileName = '{0}_{1}.csv' -f "ARMTemplateGenerator", $TimeStamp

# Load Assembly
Add-Type -AssemblyName System.Windows.Forms

#disconnect exiting connections and clearing contexts.
Write-Log -Message "Clearing existing Azure connection" -LogFileName $LogFileName -Severity Information
    
$null = Disconnect-AzAccount -ContextName 'MyAzContext' -ErrorAction SilentlyContinue
    
Write-Log -Message "Clearing existing Azure context `n" -LogFileName $LogFileName -Severity Information
    
get-azcontext -ListAvailable | ForEach-Object{$_ | remove-azcontext -Force -Verbose | Out-Null} #remove all connected content
    
Write-Log -Message "Clearing of existing connection and context completed." -LogFileName $LogFileName -Severity Information
Try {
    #Connect to tenant with context name and save it to variable
    Connect-AzAccount -Tenant $TenantID -ContextName 'MyAzContext' -Force -ErrorAction Stop
        
    #Select subscription to build
    $GetSubscriptions = Get-AzSubscription -TenantId $TenantID | Where-Object {($_.state -eq 'enabled') } | Out-GridView -Title "Select Subscription to Use" -PassThru       
}
catch {    
    Write-Log -Message "Error When trying to connect to tenant : $($_)" -LogFileName $LogFileName -Severity Error
    exit    
}

foreach($GetSubscription in $GetSubscriptions) {
    Try {
        #Set context for subscription being built
        $azContext = Set-AzContext -Subscription $GetSubscription.id
        Write-Log -Message "`nWorking in Subscription: $($GetSubscription.Name)" -LogFileName $LogFileName -Severity Information        
        Write-Log -Message "Listing Azure Logic Apps workspace from $($GetSubscription.Name)" -LogFileName $LogFileName -Severity Information
        $AzureLogicApps = Get-AzResource -ResourceType "Microsoft.Logic/workflows" | Out-GridView -Title "Select Playbook to generate ARM Template" -PassThru 
        if($null -eq $AzureLogicApps){
            Write-Log -Message "No Azure Logic Apps workspace found in $($GetSubscription.Name)" -LogFileName $LogFileName -Severity Error 
        }
        else {               
            Write-Log -Message "Creating ARM Template" -LogFileName $LogFileName -Severity Information
            
            $FolderName = Get-FolderName -initialDirectory $PSScriptRoot
            
            foreach($LogicApp in $AzureLogicApps){                               
                $armHostUrl = $azContext.Environment.ResourceManagerUrl
                # Ensure token audience matches the ARM endpoint for the selected cloud (AzureCloud/AzureUSGovernment/etc.)
                $tenantIdToUse = $null
                try { $tenantIdToUse = $azContext.Tenant.Id } catch { $tenantIdToUse = $TenantID }
                $tokenToUse = Get-ArmAccessToken -armResourceUrl $armHostUrl -tenantId $tenantIdToUse

                $jwtPayload = Get-JwtPayload -jwt $tokenToUse
                if ($jwtPayload) {
                    $aud = $jwtPayload.aud
                    $tid = $jwtPayload.tid
                    $exp = $null
                    try {
                        if ($jwtPayload.exp) {
                            $exp = [DateTimeOffset]::FromUnixTimeSeconds([int64]$jwtPayload.exp).ToString('u')
                        }
                    } catch { }
                    Write-Log -Message "ARM token details: aud=$aud tid=$tid exp=$exp" -LogFileName $LogFileName -Severity Information
                }
                else {
                    $len = 0
                    try { $len = $tokenToUse.Length } catch { $len = 0 }
                    $looksJwt = $false
                    try { $looksJwt = ($tokenToUse -match '^[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+$') } catch { $looksJwt = $false }
                    Write-Log -Message "ARM token format: type=$($tokenToUse.GetType().FullName) len=$len jwt=$looksJwt" -LogFileName $LogFileName -Severity Warning
                }

                $apiConnectionResources = [System.Collections.ArrayList]@()
                $templateParameters = [ordered] @{}
                $PlaybookARMParameters = [ordered] @{}
                $templateVariables = [ordered] @{}
                $script:ConnectionExportCache = @{}

                $PlaybookSubscriptionId = $GetSubscription.id
                $PlaybookResourceName = $LogicApp.Name
                $PlaybookResourceGroupName = $LogicApp.ResourceGroupName

                $playbookResource = GetPlaybookResource
                
                $null = MkDir "$($FolderName)\$($PlaybookResourceName)" -Force
                
                # Remove Parameter default values                
                foreach($PlaybookParameter in $playbookResource.properties.definition.parameters.PSObject.Properties) {
                    
                   if ($PlaybookParameter.Name -ne '$connections') {                        
                        $playbookResource.properties.definition.parameters.PSObject.Properties.Remove($PlaybookParameter.Name)                        
                        $playbookResource.properties.definition.parameters | Add-Member -MemberType NoteProperty -Name $($PlaybookParameter.Name) -Value @{"defaultValue"="[parameters('$($PlaybookParameter.Name)')]" 
                        "type"= "$($PlaybookParameter.Value.type)" }     
                        
                        $PlaybookARMParameters.Add($($PlaybookParameter.Name), [ordered] @{                            
                            "type"= "$($PlaybookParameter.Value.type)"
                            "metadata"= @{
                                "description"="Enter value for $($PlaybookParameter.Name)"
                            }
                        })
                    }
                }
                               
                # Add changes for API connection resources
                # Keep only connection references that are actually used in the workflow definition
                $usedConnectionKeys = $null
                try {
                    $usedConnectionKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                    $defJson = $playbookResource.properties.definition | ConvertTo-Json -Depth 100
                    $pattern = '@parameters\(''\$connections''\)\[''([^'']+)''\]'
                    $matches = [regex]::Matches($defJson, $pattern)
                    foreach ($m in $matches) {
                        $null = $usedConnectionKeys.Add($m.Groups[1].Value)
                    }
                } catch {
                    $usedConnectionKeys = $null
                }

                if ($usedConnectionKeys -and $usedConnectionKeys.Count -gt 0) {
                    foreach ($p in @($playbookResource.properties.parameters.'$connections'.value.PSObject.Properties)) {
                        if (-not $usedConnectionKeys.Contains($p.Name)) {
                            $playbookResource.properties.parameters.'$connections'.value.PSObject.Properties.Remove($p.Name)
                        }
                    }
                }

                Foreach ($apiConnectionReference in @($playbookResource.properties.parameters.'$connections'.value.PsObject.Properties)) {
                    HandlePlaybookApiConnectionReference -apiConnectionReference $apiConnectionReference -playbookResource $playbookResource
                }
                
                # Create and export the ARM template
                $armTemplateOutput = BuildArmTemplate -playbookResource $playbookResource | ConvertTo-Json -Depth 100
                $armTemplateOutput = $armTemplateOutput -replace "\\u0027", "'" # ConvertTo-Json escapes quotes, which we don't want
                FixJsonIndentation -jsonOutput $armTemplateOutput | Set-Content "$($FolderName)\$($PlaybookResourceName)\azuredeploy.json"
                Write-Log -Message "ARM Template created successfully at $($FolderName)\$($PlaybookResourceName)\azuredeploy.json" -LogFileName $LogFileName -Severity Information                
            }
            Confirmation-Dlg -DlgMessage "ARM Template created successfully at $($FolderName)"
        }
    }
    catch {    
        Write-Log -Message "Error When trying to connect to Subscription : $($_)" -LogFileName $LogFileName -Severity Error
        exit    
    }
}

#endregion