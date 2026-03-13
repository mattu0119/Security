<#
.SYNOPSIS
Assign Microsoft Graph application permissions (app roles) to an Azure Managed Identity.

.DESCRIPTION
- Resolves the Managed Identity service principal
- Resolves the Microsoft Graph service principal
- Finds the requested Graph app roles
- Assigns app roles to the Managed Identity service principal

.NOTES
- Requires Microsoft Graph PowerShell SDK
- Recommended connection scopes for the operator:
  AppRoleAssignment.ReadWrite.All, Application.Read.All
- Managed identity role changes can take time to become effective because tokens are cached by the platform.

.PARAMETER ManagedIdentityObjectId
Object ID of the managed identity service principal in Microsoft Entra ID.
Use this when you already know the managed identity principal/object ID.

.PARAMETER ManagedIdentityDisplayName
Display name of the managed identity service principal.
Use this when you want to resolve the managed identity by name.

.PARAMETER Permissions
List of Microsoft Graph application permissions (app role values) to assign.
Default: Channel.Create.Group

.EXAMPLE
.\Grant-GraphPermissionsToManagedIdentity.ps1 `
  -ManagedIdentityObjectId "11111111-2222-3333-4444-555555555555"

.EXAMPLE
.\Grant-GraphPermissionsToManagedIdentity.ps1 `
  -ManagedIdentityDisplayName "func-teams-vuln-demo" `
  -Permissions @("Channel.Create.Group")
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityObjectId,

    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityDisplayName,

    [Parameter(Mandatory = $false)]
    [string[]]$Permissions = @("Channel.Create.Group")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-WarnLine {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[ OK ] $Message" -ForegroundColor Green
}

if ([string]::IsNullOrWhiteSpace($ManagedIdentityObjectId) -and [string]::IsNullOrWhiteSpace($ManagedIdentityDisplayName)) {
    throw "Specify either -ManagedIdentityObjectId or -ManagedIdentityDisplayName."
}

# Ensure Microsoft Graph PowerShell SDK is available
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
    Write-Info "Microsoft.Graph.Applications module not found. Installing Microsoft.Graph..."
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

Import-Module Microsoft.Graph.Applications

Write-Info "Connecting to Microsoft Graph..."
Connect-MgGraph -Scopes "AppRoleAssignment.ReadWrite.All","Application.Read.All" | Out-Null

# Resolve the managed identity service principal
$managedIdentitySp = $null

if (-not [string]::IsNullOrWhiteSpace($ManagedIdentityObjectId)) {
    Write-Info "Resolving managed identity by Object ID: $ManagedIdentityObjectId"
    $managedIdentitySp = Get-MgServicePrincipal -ServicePrincipalId $ManagedIdentityObjectId
}
else {
    Write-Info "Resolving managed identity by display name: $ManagedIdentityDisplayName"
    $result = Get-MgServicePrincipal -Filter "displayName eq '$ManagedIdentityDisplayName'"
    if ($null -eq $result) {
        throw "Managed identity service principal not found by display name: $ManagedIdentityDisplayName"
    }

    if ($result -is [System.Array] -or $result.Count -gt 1) {
        if ($result.Count -gt 1) {
            throw "Multiple service principals found for display name '$ManagedIdentityDisplayName'. Please use -ManagedIdentityObjectId instead."
        }
    }

    $managedIdentitySp = @($result)[0]
}

if ($null -eq $managedIdentitySp) {
    throw "Managed identity service principal could not be resolved."
}

Write-Ok "Managed identity resolved: $($managedIdentitySp.DisplayName) / $($managedIdentitySp.Id)"

# Resolve Microsoft Graph service principal
$graphAppId = "00000003-0000-0000-c000-000000000000"
Write-Info "Resolving Microsoft Graph service principal..."
$graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"

if ($null -eq $graphSp) {
    throw "Microsoft Graph service principal could not be resolved."
}

$graphSp = @($graphSp)[0]
Write-Ok "Microsoft Graph SP resolved: $($graphSp.DisplayName) / $($graphSp.Id)"

# Build a lookup of current assignments to avoid duplicates
Write-Info "Reading existing app role assignments..."
$currentAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentitySp.Id

foreach ($permissionName in $Permissions) {
    Write-Info "Processing permission: $permissionName"

    $appRole = $graphSp.AppRoles | Where-Object {
        $_.Value -eq $permissionName -and $_.AllowedMemberTypes -contains "Application"
    }

    if (-not $appRole) {
        Write-WarnLine "Permission '$permissionName' was not found as an APPLICATION permission on Microsoft Graph. Skipping."
        continue
    }

    $alreadyAssigned = $currentAssignments | Where-Object {
        $_.ResourceId -eq $graphSp.Id -and $_.AppRoleId -eq $appRole.Id
    }

    if ($alreadyAssigned) {
        Write-WarnLine "Permission '$permissionName' is already assigned. Skipping."
        continue
    }

    $body = @{
        principalId = $managedIdentitySp.Id
        resourceId  = $graphSp.Id
        appRoleId   = $appRole.Id
    }

    Write-Info "Assigning '$permissionName'..."
    New-MgServicePrincipalAppRoleAssignedTo `
        -ServicePrincipalId $graphSp.Id `
        -BodyParameter $body | Out-Null

    Write-Ok "Assigned '$permissionName'"
}

Write-Host ""
Write-Ok "Completed."
Write-WarnLine "Managed identity tokens are cached by the platform, so role changes can take time to become effective."