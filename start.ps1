<#
.SYNOPSIS
    rnaseq-nets : launcher for Windows (Docker Desktop).

.DESCRIPTION
    Starts RStudio Server in a container on http://localhost:8888 (no login)
    and shares the folder containing this script with the container in
    /sharedFolder. RStudio starts in that folder.

.EXAMPLE
    .\start.ps1
.EXAMPLE
    .\start.ps1 -Dind            # docker-in-docker variant (privileged)
.EXAMPLE
    .\start.ps1 -Port 9999
.EXAMPLE
    .\start.ps1 -Build           # build the image locally instead of pulling
.EXAMPLE
    .\start.ps1 -Stop
#>
[CmdletBinding()]
param(
    [int]    $Port  = 8888,
    [switch] $Dind,
    [switch] $Build,
    [switch] $Stop,
    [switch] $Logs,
    [switch] $Shell,
    [string] $Image = "",
    [int]    $MinFreeGB = 25,
    [switch] $NoBrowser
)

$ErrorActionPreference = "Stop"

# --- where am I ? ----------------------------------------------------------
if ($PSScriptRoot) {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}
$SharedDir = (Resolve-Path -LiteralPath $ScriptDir).Path

# --- configuration ---------------------------------------------------------
# Order of precedence: environment variables > image.conf > git remote > default
$conf = @{}
$confFile = Join-Path $SharedDir "image.conf"
if (Test-Path -LiteralPath $confFile) {
    foreach ($line in Get-Content -LiteralPath $confFile) {
        $clean = ($line -split "#")[0].Trim()
        if ($clean -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$') {
            $conf[$Matches[1]] = $Matches[2]
        }
    }
}

# if image.conf gives nothing, derive owner/repo from the git remote of the clone
if (-not $conf.ContainsKey("IMAGE_REPO")) {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $remote = (git -C "$SharedDir" config --get remote.origin.url 2>$null)
        if ($remote) {
            $slug = $remote -replace '^git@github\.com:', '' `
                            -replace '^https?://[^/]+/', '' `
                            -replace '\.git$', ''
            if ($slug -match '^[^/]+/[^/]+$') {
                $conf["IMAGE_REPO"] = "ghcr.io/" + $slug.ToLower()
            }
        }
    }
}

function Get-Conf {
    param([string]$Name, [string]$Default)
    $envValue = [Environment]::GetEnvironmentVariable($Name)
    if ($envValue) { return $envValue }
    if ($conf.ContainsKey($Name)) { return $conf[$Name] }
    return $Default
}

$ImageRepo = Get-Conf "IMAGE_REPO" "ghcr.io/reproduciblebioinformatics/rnaseq-nets"
$TagStd    = Get-Conf "TAG_STD"    "latest"
$TagDind   = Get-Conf "TAG_DIND"   "dind"
$RVersion  = Get-Conf "R_VERSION"  "4.6.1"
$DindImage = Get-Conf "DIND_IMAGE" "docker:29-dind"
$ContainerName = if ($Dind) { "rnaseq-nets-dind" } else { "rnaseq-nets" }

if ($Image -eq "") {
    $Image = if ($Dind) { "${ImageRepo}:${TagDind}" } else { "${ImageRepo}:${TagStd}" }
}

function Write-Info  { param([string]$m) Write-Host "[info] $m"  -ForegroundColor Green }
function Write-Warn   { param([string]$m) Write-Host "[warn] $m"  -ForegroundColor Yellow }
function Write-Err    { param([string]$m) Write-Host "[error] $m" -ForegroundColor Red }
function Die          { param([string]$m) Write-Err $m; Read-Host "Press ENTER to close"; exit 1 }

# --- docker available ? ----------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Die "Docker is not installed or not in PATH.`nInstall Docker Desktop: https://www.docker.com/products/docker-desktop/"
}

docker info *> $null
if ($LASTEXITCODE -ne 0) {
    Die "The Docker daemon is not responding.`nStart Docker Desktop and wait until it reports 'Engine running', then run this script again."
}

# --- secondary actions -----------------------------------------------------
$existing = @(docker ps -a --format "{{.Names}}") | ForEach-Object { "$_".Trim() }

if ($Stop) {
    if ($existing -contains $ContainerName) {
        Write-Info "stopping $ContainerName ..."
        docker rm -f $ContainerName *> $null
        Write-Info "done."
    } else {
        Write-Info "no container named $ContainerName."
    }
    exit 0
}
if ($Logs)  { docker logs -f $ContainerName; exit $LASTEXITCODE }
if ($Shell) { docker exec -it $ContainerName bash; exit $LASTEXITCODE }

# --- checks on the shared folder ------------------------------------------
Write-Info "image         : $Image"
Write-Info "shared folder : $SharedDir"

if (-not (Test-Path -LiteralPath $SharedDir)) { Die "the folder to share does not exist: $SharedDir" }

if ($SharedDir.StartsWith("\\")) {
    Die "the folder is on a network path (UNC): $SharedDir`nDocker Desktop cannot bind-mount UNC paths. Copy the folder to a local disk (e.g. C:\Users\<you>\rnaseq-nets)."
}

if ($SharedDir -match "\s") {
    Write-Warn "the path contains spaces. It is handled by this script (everything is quoted), but do not rename folders while the container is running."
}

if ($SharedDir -match "[^\u0020-\u007E]") {
    Write-Warn "the path contains non-ASCII characters (accents/special chars).`n       If the mount fails, move the folder to a simple path such as C:\rnaseq-nets."
}

if ($SharedDir -match "[&`$;|<>*?%]") {
    Write-Warn "the path contains special characters (& `$ ; | < > * ? %). Docker may refuse the bind mount: consider moving the folder."
}

# write test
try {
    $probe = Join-Path $SharedDir ".rnaseq_nets_write_test"
    New-Item -ItemType File -Path $probe -Force -ErrorAction Stop | Out-Null
    Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warn "the folder does not look writable: RStudio will not be able to save files there."
}

# --- free disk space -------------------------------------------------------
try {
    $drive  = [System.IO.DriveInfo]::new((Split-Path -Qualifier $SharedDir) + "\")
    $freeGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
    Write-Info "free space on $($drive.Name) : $freeGB GB"
    if ($freeGB -lt $MinFreeGB) {
        Write-Warn "less than $MinFreeGB GB free. The image is large (~5-8 GB, more for the dind variant) and Docker Desktop stores it in its WSL2 virtual disk on C:."
    }
} catch {
    Write-Warn "could not determine the free disk space."
}

# --- host port free ? ------------------------------------------------------
function Test-PortInUse {
    param([int]$p)
    try {
        $c = Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction Stop
        return ($null -ne $c)
    } catch {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $client.Connect("127.0.0.1", $p)
            $client.Close()
            return $true
        } catch { return $false }
    }
}

if (Test-PortInUse $Port) {
    $running = docker ps --format "{{.Names}} {{.Ports}}"
    if ($running -match "^$ContainerName .*:$Port->") {
        Write-Info "the container $ContainerName is already running on port $Port."
        Write-Info "open http://localhost:$Port   (stop it with: .\start.ps1 -Stop)"
        exit 0
    }
    Die "host port $Port is already in use by another process.`nUse another port:  .\start.ps1 -Port 9999"
}

# --- remove a stale container with the same name ---------------------------
if ($existing -contains $ContainerName) {
    Write-Info "removing the previous container $ContainerName ..."
    docker rm -f $ContainerName *> $null
}

# --- build or pull the image ----------------------------------------------
if ($Build) {
    Write-Info "building the image locally (30-60 minutes the first time) ..."
    docker build --build-arg "R_VERSION=$RVersion" -t "${ImageRepo}:${TagStd}" "$SharedDir"
    if ($LASTEXITCODE -ne 0) { Die "docker build failed." }
    if ($Dind) {
        docker build -f (Join-Path $SharedDir "Dockerfile.dind") `
            --build-arg "BASE_IMAGE=${ImageRepo}:${TagStd}" `
            --build-arg "DIND_IMAGE=$DindImage" `
            -t "${ImageRepo}:${TagDind}" "$SharedDir"
        if ($LASTEXITCODE -ne 0) { Die "docker build (dind) failed." }
    }
} else {
    docker image inspect $Image *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Info "pulling $Image (several GB, be patient) ..."
        docker pull $Image
        if ($LASTEXITCODE -ne 0) {
            Die "pull failed. Check the image name, or build it locally:  .\start.ps1 -Build"
        }
    } else {
        Write-Info "image already present locally : $Image"
    }
}

# --- run -------------------------------------------------------------------
$runArgs = @(
    "run", "-d",
    "--name", $ContainerName,
    "--hostname", "rnaseq-nets",
    "-p", "127.0.0.1:${Port}:8787",
    "-e", "DISABLE_AUTH=true",
    "-e", "ROOT=true",
    "-v", "${SharedDir}:/sharedFolder",
    "--shm-size=2g"
)

if ($Dind) {
    Write-Warn "the dind variant needs --privileged (its own Docker daemon runs inside the container)."
    $runArgs += @("--privileged", "-v", "${ContainerName}-docker-lib:/var/lib/docker")
}

$runArgs += $Image

Write-Info "starting the container ..."
& docker @runArgs *> $null
if ($LASTEXITCODE -ne 0) { Die "docker run failed." }

# --- wait for RStudio to answer -------------------------------------------
Write-Info "waiting for RStudio Server ..."
$ok = $false
for ($i = 0; $i -lt 45; $i++) {
    $alive = @(docker ps --format "{{.Names}}") | ForEach-Object { "$_".Trim() }
    if ($alive -notcontains $ContainerName) {
        Write-Err "the container stopped unexpectedly. Logs:"
        docker logs $ContainerName
        Read-Host "Press ENTER to close"
        exit 1
    }
    try {
        Invoke-WebRequest -Uri "http://localhost:$Port" -UseBasicParsing -TimeoutSec 3 *> $null
        $ok = $true
        break
    } catch { Start-Sleep -Seconds 2 }
}

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  RStudio Server : http://localhost:$Port"
Write-Host "  login          : not required (DISABLE_AUTH)"
Write-Host "  shared folder  : $SharedDir  ->  /sharedFolder"
Write-Host "  container      : $ContainerName"
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  logs  : .\start.ps1 -Logs"
Write-Host "  shell : .\start.ps1 -Shell"
Write-Host "  stop  : .\start.ps1 -Stop"
Write-Host ""

if (-not $ok) {
    Write-Warn "RStudio did not answer yet: wait a few seconds and reload the page."
}

if (-not $NoBrowser) {
    Start-Process "http://localhost:$Port"
}
