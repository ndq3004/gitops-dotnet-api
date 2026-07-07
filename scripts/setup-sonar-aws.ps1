<#
.SYNOPSIS
Creates an EC2 instance with a public IP and bootstraps SonarQube Server.

.EXAMPLE
.\scripts\setup-sonar-aws.ps1 -Region ap-southeast-1 -KeyName my-ec2-key

.EXAMPLE
.\scripts\setup-sonar-aws.ps1 -Region us-east-1 -InstanceName sonar -AllowedCidr 203.0.113.10/32
#>

param(
    [string]$Region = "ap-southeast-1",
    [string]$InstanceName = "sonarqube-server",
    [string]$InstanceType = "t3.medium",
    [string]$KeyName,
    [string]$VpcId,
    [string]$SubnetId,
    [string]$AllowedCidr,
    [int]$VolumeSizeGb = 30
)

$ErrorActionPreference = "Stop"

function Assert-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "'$Name' is not installed or is not on PATH."
    }
}

function Invoke-Aws {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & aws @Arguments 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI command failed: aws $($Arguments -join ' ')`n$output"
    }

    return $output
}

function Invoke-AwsText {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $result = Invoke-Aws ($Arguments + @("--output", "text"))
    return ($result | Out-String).Trim()
}

function Invoke-AwsJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $result = Invoke-Aws ($Arguments + @("--output", "json"))
    return ($result | Out-String | ConvertFrom-Json)
}

function Get-CallerCidr {
    try {
        $ip = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com" -TimeoutSec 10).Trim()
        return "$ip/32"
    }
    catch {
        throw "Cannot detect your public IP. Re-run with -AllowedCidr, for example -AllowedCidr 203.0.113.10/32."
    }
}

function Get-LatestUbuntuAmiId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AwsRegion
    )

    $parameterName = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"

    return Invoke-AwsText @(
        "ssm", "get-parameter",
        "--region", $AwsRegion,
        "--name", $parameterName,
        "--query", "Parameter.Value"
    )
}

function Get-DefaultVpcId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AwsRegion
    )

    return Invoke-AwsText @(
        "ec2", "describe-vpcs",
        "--region", $AwsRegion,
        "--filters", "Name=isDefault,Values=true",
        "--query", "Vpcs[0].VpcId"
    )
}

function Get-FirstSubnetId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AwsRegion,

        [Parameter(Mandatory = $true)]
        [string]$AwsVpcId
    )

    return Invoke-AwsText @(
        "ec2", "describe-subnets",
        "--region", $AwsRegion,
        "--filters", "Name=vpc-id,Values=$AwsVpcId", "Name=state,Values=available",
        "--query", "Subnets | sort_by(@, &AvailabilityZone)[0].SubnetId"
    )
}

function New-OrGetSecurityGroupId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AwsRegion,

        [Parameter(Mandatory = $true)]
        [string]$AwsVpcId,

        [Parameter(Mandatory = $true)]
        [string]$Cidr
    )

    $groupName = "$InstanceName-sg"
    $existingGroupId = Invoke-AwsText @(
        "ec2", "describe-security-groups",
        "--region", $AwsRegion,
        "--filters", "Name=group-name,Values=$groupName", "Name=vpc-id,Values=$AwsVpcId",
        "--query", "SecurityGroups[0].GroupId"
    )

    if ($existingGroupId -and $existingGroupId -ne "None") {
        Write-Host "Using existing security group: $existingGroupId"
        $securityGroupId = $existingGroupId
    }
    else {
        Write-Host "Creating security group: $groupName"
        $securityGroupId = Invoke-AwsText @(
            "ec2", "create-security-group",
            "--region", $AwsRegion,
            "--group-name", $groupName,
            "--description", "SonarQube server access",
            "--vpc-id", $AwsVpcId,
            "--query", "GroupId"
        )
    }

    $ports = @(22, 9000)

    foreach ($port in $ports) {
        try {
            Invoke-Aws @(
                "ec2", "authorize-security-group-ingress",
                "--region", $AwsRegion,
                "--group-id", $securityGroupId,
                "--protocol", "tcp",
                "--port", "$port",
                "--cidr", $Cidr
            ) | Out-Null
        }
        catch {
            if ($_.Exception.Message -notmatch "InvalidPermission.Duplicate") {
                throw
            }
        }
    }

    return $securityGroupId
}

Assert-Command "aws"

if (-not $AllowedCidr) {
    $AllowedCidr = Get-CallerCidr
}

if (-not $VpcId) {
    $VpcId = Get-DefaultVpcId -AwsRegion $Region
}

if (-not $VpcId -or $VpcId -eq "None") {
    throw "No VPC was provided and no default VPC was found in $Region. Pass -VpcId and -SubnetId."
}

if (-not $SubnetId) {
    $SubnetId = Get-FirstSubnetId -AwsRegion $Region -AwsVpcId $VpcId
}

if (-not $SubnetId -or $SubnetId -eq "None") {
    throw "No subnet was provided and no available subnet was found in VPC $VpcId. Pass -SubnetId."
}

$amiId = Get-LatestUbuntuAmiId -AwsRegion $Region
$securityGroupId = New-OrGetSecurityGroupId -AwsRegion $Region -AwsVpcId $VpcId -Cidr $AllowedCidr

$userData = @'
#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

cat >/etc/sysctl.d/99-sonarqube.conf <<SYSCTL
vm.max_map_count=524288
fs.file-max=131072
SYSCTL
sysctl --system

mkdir -p /opt/sonarqube
cat >/opt/sonarqube/docker-compose.yml <<'COMPOSE'
services:
  sonarqube:
    image: sonarqube:lts-community
    depends_on:
      - db
    ports:
      - "9000:9000"
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://db:5432/sonar
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: sonar
    ulimits:
      nofile:
        soft: 131072
        hard: 131072
      nproc: 8192

      volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_extensions:/opt/sonarqube/extensions
      - sonarqube_logs:/opt/sonarqube/logs
    restart: unless-stopped

  db:
    image: postgres:15
    environment:
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: sonar
      POSTGRES_DB: sonar
    volumes:
      - postgresql:/var/lib/postgresql
      - postgresql_data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  sonarqube_data:
  sonarqube_extensions:
  sonarqube_logs:
  postgresql:
  postgresql_data:
COMPOSE

docker compose -f /opt/sonarqube/docker-compose.yml up -d
'@

$userDataFile = Join-Path ([System.IO.Path]::GetTempPath()) "sonarqube-user-data-$([Guid]::NewGuid()).sh"
Set-Content -Path $userDataFile -Value $userData -NoNewline -Encoding ascii

try {
    $networkInterface = "DeviceIndex=0,SubnetId=$SubnetId,Groups=[$securityGroupId],AssociatePublicIpAddress=true"
    $tagSpec = "ResourceType=instance,Tags=[{Key=Name,Value=$InstanceName},{Key=Application,Value=SonarQube}]"
    $blockDevice = "DeviceName=/dev/sda1,Ebs={VolumeSize=$VolumeSizeGb,VolumeType=gp3,DeleteOnTermination=true}"
    Write-Host "Launching EC2 instance in $Region"
    Write-Host "AMI: $amiId"
    Write-Host "Subnet: $SubnetId"
    Write-Host "Security group: $securityGroupId"
    Write-Host "Allowed CIDR: $AllowedCidr"

    $runInstanceArgs = @(
        "ec2", "run-instances",
        "--region", $Region,
        "--image-id", $amiId,
        "--instance-type", $InstanceType
    )

    if ($KeyName) {
        $runInstanceArgs += @("--key-name", $KeyName)
    }

    $runInstanceArgs += @(
        "--network-interfaces", $networkInterface,
        "--block-device-mappings", $blockDevice,
        "--tag-specifications", $tagSpec,
        "--user-data", "file://$userDataFile",
        "--query", "Instances[0].InstanceId"
    )

    $instanceId = Invoke-AwsText $runInstanceArgs

    Write-Host "Instance created: $instanceId"
    Write-Host "Waiting for instance to run..."

    Invoke-Aws @(
        "ec2", "wait", "instance-running",
        "--region", $Region,
        "--instance-ids", $instanceId
    ) | Out-Null

    $instance = Invoke-AwsJson @(
        "ec2", "describe-instances",
        "--region", $Region,
        "--instance-ids", $instanceId,
        "--query", "Reservations[0].Instances[0]"
    )

    $publicIp = $instance.PublicIpAddress
    $publicDns = $instance.PublicDnsName

    Write-Host ""
    Write-Host "SonarQube EC2 instance is running."
    Write-Host "Instance ID: $instanceId"
    Write-Host "Public IP:   $publicIp"
    Write-Host "Public DNS:  $publicDns"
    Write-Host "URL:         http://$publicIp`:9000"
    Write-Host ""
    Write-Host "Bootstrap can take a few minutes after EC2 becomes running."
    Write-Host "Default SonarQube login is admin/admin, and SonarQube will ask you to change it."

    if ($KeyName) {
        Write-Host "SSH: ssh ubuntu@$publicIp"
    }
}
finally {
    if (Test-Path $userDataFile) {
        Remove-Item -Path $userDataFile -Force
    }
}
