param(
    [ValidateSet("win-x64", "win-arm64")]
    [string]$Runtime = "win-x64",

    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",

    [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$solutionPath = Join-Path $repoRoot "windows/ClipDock.sln"
$projectPath = Join-Path $repoRoot "windows/src/ClipDock.App/ClipDock.App.csproj"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot "dist/windows/$Runtime"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

dotnet restore $solutionPath
dotnet test $solutionPath --configuration $Configuration --no-restore
dotnet publish $projectPath `
    --configuration $Configuration `
    --runtime $Runtime `
    --self-contained true `
    -p:PublishSingleFile=false `
    -p:WindowsAppSDKSelfContained=true `
    -p:PublishReadyToRun=true `
    --output $OutputDirectory

Write-Host "ClipDock Windows package created at: $OutputDirectory"
