param(
    [string]$Repo
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI 'gh' is not installed. Install it first: https://cli.github.com/"
}

if (-not $Repo) {
    $Repo = gh repo view --json nameWithOwner --jq ".nameWithOwner"
}

if (-not $Repo) {
    throw "Cannot detect repository. Run this inside the git repo or pass -Repo OWNER/REPO."
}

function Read-SecretValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [switch]$PlainText
    )

    if ($PlainText) {
        return Read-Host "Enter $Name"
    }

    $secure = Read-Host "Enter $Name" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)

    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Set-RepoSecret {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name cannot be empty."
    }

    gh secret set $Name --repo $Repo --body $Value
}

Write-Host "Setting GitHub Actions secrets for $Repo"

Set-RepoSecret "SONAR_TOKEN" (Read-SecretValue "SONAR_TOKEN")
Set-RepoSecret "SONAR_ORG" (Read-SecretValue "SONAR_ORG" -PlainText)
Set-RepoSecret "OPENAI_API_KEY" (Read-SecretValue "OPENAI_API_KEY")
Set-RepoSecret "AZURE_CLIENT_ID" (Read-SecretValue "AZURE_CLIENT_ID" -PlainText)
Set-RepoSecret "AZURE_TENANT_ID" (Read-SecretValue "AZURE_TENANT_ID" -PlainText)
Set-RepoSecret "AZURE_SUBSCRIPTION_ID" (Read-SecretValue "AZURE_SUBSCRIPTION_ID" -PlainText)

Write-Host "Done."
