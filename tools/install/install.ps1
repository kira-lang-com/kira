# Installs Kira: knvm for this machine, then `knvm setup`, which installs klf,
# the LLVM it links with, every language, and the launchers onto PATH.
#
#   irm https://github.com/kira-lang-com/kira/releases/latest/download/install.ps1 | iex
#
# Run again to bring everything up to date.
$ErrorActionPreference = 'Stop'

$hostKey = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'x86_64-windows-msvc' }
    'ARM64' { 'aarch64-windows-msvc' }
    default { throw "Kira does not publish for $env:PROCESSOR_ARCHITECTURE Windows yet" }
}
$releases = 'https://github.com/kira-lang-com/kira/releases/latest/download'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("kira-install-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Force $scratch | Out-Null
try {
    $version = (Invoke-RestMethod "$releases/version").Trim()
    $archive = "knvm-$version-$hostKey.tar.gz"
    Write-Host "Fetching knvm $version for $hostKey"
    Invoke-WebRequest "$releases/$archive" -OutFile (Join-Path $scratch $archive)
    $expected = ((Invoke-RestMethod "$releases/$archive.sha256") -split '\s+')[0].ToLower()
    $actual = (Get-FileHash (Join-Path $scratch $archive) -Algorithm SHA256).Hash.ToLower()
    if ($expected -ne $actual) { throw "$archive does not match its published checksum" }

    $unpacked = Join-Path $scratch 'knvm'
    New-Item -ItemType Directory -Force $unpacked | Out-Null
    tar -xzf (Join-Path $scratch $archive) -C $unpacked
    if ($LASTEXITCODE -ne 0) { throw "could not unpack $archive" }
    $knvm = Get-ChildItem (Join-Path $unpacked 'bin') -Filter 'knvm*' | Select-Object -First 1
    & $knvm.FullName setup
    if ($LASTEXITCODE -ne 0) { throw "knvm setup failed" }

    # Windows reads PATH from the user's environment, not from the `env`
    # script knvm writes for a unix shell.
    $klfHome = if ($env:KLFD_HOME) { $env:KLFD_HOME } else { Join-Path $HOME '.klf' }
    $bin = Join-Path $klfHome 'bin'
    $path = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (($path -split ';') -contains $bin)) {
        [Environment]::SetEnvironmentVariable('Path', ($bin + ';' + $path).TrimEnd(';'), 'User')
    }
    Write-Host "Open a new terminal: klf, kira and knvm are on your PATH."
}
finally {
    Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
}
