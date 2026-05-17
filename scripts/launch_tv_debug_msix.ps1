param(
  [int]$Port = 9222,
  [switch]$NoKill
)

$ErrorActionPreference = 'Stop'

function Get-ClassicTradingViewPath {
  $candidates = @(
    "$env:LOCALAPPDATA\TradingView\TradingView.exe",
    "$env:LOCALAPPDATA\Programs\TradingView\TradingView.exe",
    "$env:ProgramFiles\TradingView\TradingView.exe",
    "${env:ProgramFiles(x86)}\TradingView\TradingView.exe"
  )

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
      return $candidate
    }
  }

  $fromPath = Get-Command TradingView.exe -ErrorAction SilentlyContinue
  if ($fromPath) {
    return $fromPath.Source
  }

  return $null
}

function New-MsixInfo {
  param(
    [string]$InstallLocation,
    [string]$PackageFamilyName
  )

  $manifestPath = Join-Path $InstallLocation 'AppxManifest.xml'
  if (-not (Test-Path -LiteralPath $manifestPath)) {
    return $null
  }

  [xml]$manifest = Get-Content -LiteralPath $manifestPath
  $application = @($manifest.Package.Applications.Application)[0]
  $identityName = [string]$manifest.Package.Identity.Name
  $appId = [string]$application.Id
  $executable = Join-Path $InstallLocation ([string]$application.Executable)

  if (-not $PackageFamilyName) {
    $directoryName = Split-Path -Leaf $InstallLocation
    if ($directoryName -match '__(.+)$') {
      $PackageFamilyName = "${identityName}_$($matches[1])"
    }
  }

  if (-not $PackageFamilyName -or -not $appId -or -not (Test-Path -LiteralPath $executable)) {
    return $null
  }

  [pscustomobject]@{
    PackageFamilyName = $PackageFamilyName
    AppId             = $appId
    Executable        = $executable
    InstallLocation   = $InstallLocation
  }
}

function Get-MsixTradingViewInfo {
  $package = Get-AppxPackage -Name 'TradingView.Desktop' -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending |
    Select-Object -First 1

  if ($package -and $package.InstallLocation) {
    $info = New-MsixInfo -InstallLocation $package.InstallLocation -PackageFamilyName $package.PackageFamilyName
    if ($info) {
      return $info
    }
  }

  $windowsApps = Join-Path $env:ProgramFiles 'WindowsApps'
  $directories = Get-Item -Path (Join-Path $windowsApps 'TradingView.Desktop_*') -ErrorAction SilentlyContinue |
    Where-Object { $_.PSIsContainer } |
    Sort-Object LastWriteTime -Descending

  foreach ($directory in $directories) {
    $info = New-MsixInfo -InstallLocation $directory.FullName -PackageFamilyName $null
    if ($info) {
      return $info
    }
  }

  return $null
}

if (-not $NoKill) {
  Stop-Process -Name TradingView -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

$classicPath = Get-ClassicTradingViewPath
if ($classicPath) {
  Write-Host "Found classic TradingView at: $classicPath"
  Start-Process -FilePath $classicPath -ArgumentList "--remote-debugging-port=$Port"
} else {
  $msixInfo = Get-MsixTradingViewInfo
  if (-not $msixInfo) {
    throw 'TradingView not found. Checked classic install locations and MSIX/WindowsApps packages.'
  }

  if (-not (Get-Command Invoke-CommandInDesktopPackage -ErrorAction SilentlyContinue)) {
    throw 'Invoke-CommandInDesktopPackage is not available on this Windows installation.'
  }

  Write-Host "Found MSIX TradingView at: $($msixInfo.Executable)"
  Invoke-CommandInDesktopPackage `
    -PackageFamilyName $msixInfo.PackageFamilyName `
    -AppId $msixInfo.AppId `
    -Command $msixInfo.Executable `
    -Args "--remote-debugging-port=$Port" `
    -PreventBreakaway
}

Write-Host "Waiting for CDP at http://127.0.0.1:$Port ..."
for ($i = 0; $i -lt 15; $i++) {
  Start-Sleep -Seconds 1
  try {
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json/version" -UseBasicParsing -TimeoutSec 3
    Write-Host "CDP ready at http://127.0.0.1:$Port"
    $response.Content
    exit 0
  } catch {
    # Keep waiting.
  }
}

Write-Warning "TradingView launched, but CDP did not respond on port $Port yet."
exit 1
