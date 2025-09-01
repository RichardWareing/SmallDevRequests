# PowerShell Script to Set Up Azure DevOps Project for SDR Management System
# This script creates and configures:
# - DevOps Organization and Project
# - Custom Work Item Types
# - Process Template
# - Teams and Security Groups

param(
    [Parameter(Mandatory=$true)]
    [string]$OrganizationName,

    [Parameter(Mandatory=$true)]
    [string]$ProjectName,

    [Parameter(Mandatory=$false)]
    [string]$Description = "Software Development Request Management System",

    [Parameter(Mandatory=$false)]
    [ValidateSet("Basic", "Agile", "Scrum", "CMMI")]
    [string]$ProcessTemplate = "Agile",

    [Parameter(Mandatory=$false)]
    [switch]$CreateWorkItemTypes,

    [Parameter(Mandatory=$false)]
    [switch]$ConfigureTeams,

    [Parameter(Mandatory=$false)]
    [string]$PersonalAccessToken
)

# Configuration
$OrganizationUrl = "https://dev.azure.com/$OrganizationName"
$ApiVersion = "7.0-preview.3"

# Authentication headers
$Base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken"))
$Headers = @{
    Authorization=("Basic {0}" -f $Base64AuthInfo)
    "Content-Type" = "application/json"
}

function Write-Log {
    param($Message, $Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$Timestamp] [$Level] $Message"
}

function Invoke-RestApi {
    param(
        $Uri,
        $Method = "GET",
        $Body = $null,
        $ContentType = "application/json"
    )

    try {
        $params = @{
            Uri = $Uri
            Method = $Method
            Headers = $Headers
        }

        if ($Body) {
            if ($ContentType -eq "application/json-patch+json") {
                $params.Body = $Body
            } else {
                $params.Body = (ConvertTo-Json -InputObject $Body -Depth 10)
            }
        }

        $response = Invoke-RestMethod @params
        return $response
    }
    catch {
        Write-Log "API call failed: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Create-DevOpsProject {
    Write-Log "Creating Azure DevOps Project: $ProjectName"

    # Check if project already exists
    try {
        $existingProject = Invoke-RestApi -Uri "$OrganizationUrl/_apis/projects/$ProjectName&api-version=$ApiVersion"
        if ($existingProject) {
            Write-Log "Project '$ProjectName' already exists. Skipping creation." "WARNING"
            return $existingProject
        }
    }
    catch {
        Write-Log "Project doesn't exist, proceeding with creation..."
    }

    # Create new project
    $projectBody = @{
        name = $ProjectName
        description = $Description
        visibility = "private"
        capabilities = @{
            versioncontrol = @{
                sourceControlType = "Git"
            }
            processTemplate = @{
                templateTypeId = switch ($ProcessTemplate) {
                    "Agile" { "27450541-8e31-4150-9947-dc59f998fc01" }
                    "Scrum" { "6b724908-ef14-45cf-84f8-768b5384da45" }
                    "CMMI" { "c78aea03-6c4a-4c54-ba61-3c587d518c80" }
                    "Basic" { "b8a3a935-7e91-48b8-a94c-606d37c3e9f2" }
                }
            }
        }
    }

    $response = Invoke-RestApi -Uri "$OrganizationUrl/_apis/projects?api-version=$ApiVersion" -Method POST -Body $projectBody
    Write-Log "Project created successfully. Project ID: $($response.id)"

    # Wait for project creation to complete
    do {
        Start-Sleep -Seconds 5
        try {
            $status = Invoke-RestApi -Uri "$OrganizationUrl/_apis/operations/$($response.id)?api-version=$ApiVersion"
            Write-Log "Project creation status: $($status.status)"
        } catch {
            Write-Log "Error checking project status: $($_.Exception.Message)" "WARNING"
            break
        }
    } while ($status.status -eq "inProgress" -or $status.status -eq "queued")

    return $response
}

function Create-CustomWorkItemTypes {
    Write-Log "Creating custom work item types for SDR"

    # Get process template
    $processes = Invoke-RestApi -Uri "$OrganizationUrl/_apis/process/processes?api-version=$ApiVersion"
    $agileProcess = $processes | Where-Object { $_.name -eq "Agile" }

    # Create custom work item type "SDR Request"
    $sdrWorkItemDefinition = @{
        name = "SDR Request"
        description = "Custom work item type for Software Development Requests"
        color = "007acc"
        icon = "book"
        isDisabled = $false
        states = @(
            @{
                name = "New"
                category = "Proposed"
                color = "ff0000"
                order = 1
            },
            @{
                name = "Active"
                category = "InProgress"
                color = "ffff00"
                order = 2
            },
            @{
                name = "Resolved"
                category = "Resolved"
                color = "008000"
                order = 3
            },
            @{
                name = "Closed"
                category = "Completed"
                color = "000000"
                order = 4
            }
        )
        fields = @(
            @{
                referenceName = "System.Title"
                name = "Title"
                type = "String"
                required = $true
                order = 1
            },
            @{
                referenceName = "System.Description"
                name = "Description"
                type = "Html"
                required = $true
                order = 2
            },
            @{
                referenceName = "Custom.SubmitterId"
                name = "Submitter ID"
                type = "String"
                required = $true
                order = 3
            },
            @{
                referenceName = "Custom.CustomerType"
                name = "Customer Type"
                type = "String"
                allowedValues = @("Internal", "External")
                required = $true
                order = 4
            },
            @{
                referenceName = "Custom.Priority"
                name = "Priority"
                type = "String"
                allowedValues = @("Low", "Medium", "High", "Critical")
                defaultValue = "Medium"
                required = $true
                order = 5
            },
            @{
                referenceName = "Custom.RequiredByDate"
                name = "Required By Date"
                type = "DateTime"
                required = $false
                order = 6
            },
            @{
                referenceName = "Custom.EstimatedHours"
                name = "Estimated Hours"
                type = "Double"
                required = $false
                order = 7
            },
            @{
                referenceName = "Custom.SourceType"
                name = "Source Type"
                type = "String"
                allowedValues = @("Manual", "Email", "File", "Teams")
                defaultValue = "Manual"
                required = $true
                order = 8
            },
            @{
                referenceName = "Custom.ApprovalStatus"
                name = "Approval Status"
                type = "String"
                allowedValues = @("Not Required", "Pending", "Approved", "Rejected")
                defaultValue = "Not Required"
                required = $true
                order = 9
            },
            @{
                referenceName = "Custom.TechnicalComplexity"
                name = "Technical Complexity"
                type = "String"
                allowedValues = @("Low", "Medium", "High")
                defaultValue = "Medium"
                required = $true
                order = 10
            },
            @{
                referenceName = "Custom.RiskLevel"
                name = "Risk Level"
                type = "String"
                allowedValues = @("Low", "Medium", "High")
                defaultValue = "Medium"
                required = $true
                order = 11
            },
            @{
                referenceName = "Custom.TestingRequired"
                name = "Testing Required"
                type = "Boolean"
                defaultValue = $true
                required = $true
                order = 12
            },
            @{
                referenceName = "Custom.DocumentationRequired"
                name = "Documentation Required"
                type = "Boolean"
                defaultValue = $true
                required = $true
                order = 13
            }
        )
    }

    try {
        $response = Invoke-RestApi -Uri "$OrganizationUrl/_apis/work/processes/$($agileProcess.typeId)/workitemtypes?api-version=$ApiVersion" -Method POST -Body $sdrWorkItemDefinition
        Write-Log "Custom work item type 'SDR Request' created successfully."
    } catch {
        Write-Log "Failed to create custom work item type: $($_.Exception.Message)" "ERROR"
    }
}

function Create-ProjectTeams {
    Write-Log "Creating project teams and security groups"

    # Team definitions
    $teams = @(
        @{
            name = "SDR-Developers"
            description = "Development team responsible for implementing SDR requests"
        },
        @{
            name = "SDR-Approvers"
            description = "Business approvers for SDR requests"
        },
        @{
            name = "SDR-Admins"
            description = "System administrators for SDR management"
        }
    )

    foreach ($team in $teams) {
        try {
            $teamBody = @{
                name = $team.name
                description = $team.description
                projectId = $project.id
                projectName = $ProjectName
            }

            Invoke-RestApi -Uri "$OrganizationUrl/$ProjectName/_apis/teams?api-version=$ApiVersion" -Method POST -Body $teamBody
            Write-Log "Team '$($team.name)' created successfully."
        } catch {
            Write-Log "Failed to create team '$($team.name)': $($_.Exception.Message)" "ERROR"
        }
    }
}

function Create-SecurityGroups {
    Write-Log "Creating Azure DevOps security groups"

    $groups = @(
        "SDR Contributors",
        "SDR Readers",
        "SDR Approvers"
    )

    foreach ($group in $groups) {
        try {
            # Security groups are managed at organization level
            Write-Log "Security group creation requires manual setup in Azure DevOps portal"
        } catch {
            Write-Log "Note: Security groups should be created manually in Azure DevOps" "INFO"
        }
    }
}

function Create-DefaultQueries {
    Write-Log "Creating default work item queries"

    $queries = @(
        @{
            name = "Active SDRs by Priority"
            wiql = "SELECT [System.Id], [System.Title], [System.State], [Custom.Priority], [Custom.CustomerType] FROM workitems WHERE [System.WorkItemType] = 'SDR Request' AND [System.State] IN ('New', 'Active') ORDER BY [Custom.Priority] DESC"
        },
        @{
            name = "Pending Approvals"
            wiql = "SELECT [System.Id], [System.Title], [Custom.SubmitterId], [Custom.CustomerType] FROM workitems WHERE [System.WorkItemType] = 'SDR Request' AND [Custom.ApprovalStatus] = 'Pending' ORDER BY [System.CreatedDate] DESC"
        },
        @{
            name = "Overdue SDRs"
            wiql = "SELECT [System.Id], [System.Title], [Custom.RequiredByDate] FROM workitems WHERE [System.WorkItemType] = 'SDR Request' AND [Custom.RequiredByDate] < @today AND [System.State] <> 'Closed' ORDER BY [Custom.RequiredByDate] ASC"
        },
        @{
            name = "High Priority SDRs"
            wiql = "SELECT [System.Id], [System.Title], [System.AssignedTo], [Custom.RequiredByDate] FROM workitems WHERE [System.WorkItemType] = 'SDR Request' AND [Custom.Priority] IN ('High', 'Critical') AND [System.State] <> 'Closed' ORDER BY [Custom.RequiredByDate] ASC"
        }
    )

    foreach ($query in $queries) {
        try {
            $queryBody = @{
                name = $query.name
                wiql = $query.wiql
                isPublic = $true
            }

            Invoke-RestApi -Uri "$OrganizationUrl/$ProjectName/_apis/wit/queries/Shared%20Queries?api-version=$ApiVersion" -Method POST -Body $queryBody
            Write-Log "Query '$($query.name)' created successfully."
        } catch {
            Write-Log "Failed to create query '$($query.name)': $($_.Exception.Message)" "ERROR"
        }
    }
}

# Main execution
try {
    Write-Log "Starting Azure DevOps Project Setup Script"
    Write-Log "Organization: $OrganizationName"
    Write-Log "Project: $ProjectName"

    # Validate prerequisites
    if (!$PersonalAccessToken) {
        throw "Personal Access Token is required for authentication"
    }

    # Step 1: Create DevOps Project
    $global:project = Create-DevOpsProject

    # Step 2: Create Custom Work Item Types (if requested)
    if ($CreateWorkItemTypes) {
        Create-CustomWorkItemTypes
    }

    # Step 3: Create Teams (if requested)
    if ($ConfigureTeams) {
        Create-ProjectTeams
    }

    # Step 4: Create Security Groups
    Create-SecurityGroups

    # Step 5: Create Default Queries
    if ($CreateWorkItemTypes) {
        Create-DefaultQueries
    }

    Write-Log "Azure DevOps Project setup completed successfully!" "SUCCESS"

    # Output summary
    Write-Host
    Write-Host "========== SETUP SUMMARY =========="
    Write-Host "Organization: $OrganizationName"
    Write-Host "Project: $ProjectName"
    Write-Host "Project URL: https://dev.azure.com/$OrganizationName/$ProjectName"
    Write-Host "==================================="

} catch {
    Write-Log "Script execution failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}

Write-Log "Script completed"