# Build the Budget APK without Android Studio / Gradle.
# Requires: JRE 17, ECJ, Android build-tools, platform android.jar.
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$tools = Join-Path $env:TEMP 'apkbuild'
$build = Join-Path $root 'build'
$certDir = Join-Path $root 'signing'
if (-not (Test-Path (Join-Path $certDir 'key.pk8'))) {
  $certDir = Join-Path $tools 'cert'
}

$jre = Get-ChildItem $tools -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
  Where-Object { Test-Path (Join-Path $_.FullName 'bin\java.exe') } | Select-Object -First 1
if (-not $jre) { throw 'JRE not found' }

$java = Join-Path $jre.FullName 'bin\java.exe'

$bt = Get-ChildItem $tools -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
  Where-Object { Test-Path (Join-Path $_.FullName 'aapt2.exe') } | Select-Object -First 1
if (-not $bt) { throw 'build-tools not found' }

$platform = Get-ChildItem $tools -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
  Where-Object { Test-Path (Join-Path $_.FullName 'android.jar') } | Select-Object -First 1
if (-not $platform) { throw 'platform android.jar not found' }

$androidJar = Join-Path $platform.FullName 'android.jar'
$ecj = Join-Path $tools 'ecj.jar'
$aapt2 = Join-Path $bt.FullName 'aapt2.exe'
$d8bat = Join-Path $bt.FullName 'd8.bat'
$zipalign = Join-Path $bt.FullName 'zipalign.exe'
$apksigner = Join-Path $bt.FullName 'lib\apksigner.jar'

$env:JAVA_HOME = $jre.FullName
$env:PATH = (Join-Path $jre.FullName 'bin') + ';' + $env:PATH

if (Test-Path $build) { Remove-Item $build -Recurse -Force }
New-Item -ItemType Directory -Force (Join-Path $build 'classes'), (Join-Path $build 'dex') | Out-Null

Write-Host '1/7 compile java (ecj)...'
$sources = Get-ChildItem (Join-Path $root 'src') -Recurse -Filter *.java | ForEach-Object { $_.FullName }
& $java -jar $ecj -source 8 -target 8 -bootclasspath $androidJar -nowarn -d (Join-Path $build 'classes') $sources
if ($LASTEXITCODE -ne 0) { throw 'ecj failed' }

Write-Host '2/7 dex (d8)...'
$classes = Get-ChildItem (Join-Path $build 'classes') -Recurse -Filter *.class | ForEach-Object { $_.FullName }
& $d8bat --release --lib $androidJar --min-api 21 --output (Join-Path $build 'dex') $classes
if ($LASTEXITCODE -ne 0) { throw 'd8 failed' }

Write-Host '3/7 compile resources (aapt2)...'
& $aapt2 compile --dir (Join-Path $root 'res') -o (Join-Path $build 'res.zip')
if ($LASTEXITCODE -ne 0) { throw 'aapt2 compile failed' }

Write-Host '4/7 link apk (aapt2)...'
& $aapt2 link -o (Join-Path $build 'base.apk') -I $androidJar `
  --manifest (Join-Path $root 'AndroidManifest.xml') `
  --min-sdk-version 21 --target-sdk-version 34 `
  --version-code 3 --version-name 1.2 `
  -R (Join-Path $build 'res.zip') --auto-add-overlay
if ($LASTEXITCODE -ne 0) { throw 'aapt2 link failed' }

Write-Host '5/7 add classes.dex and assets...'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open((Join-Path $build 'base.apk'), 'Update')
try {
  [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
    $zip, (Join-Path $build 'dex\classes.dex'), 'classes.dex',
    [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
  [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
    $zip, (Join-Path $root 'assets\index.html'), 'assets/index.html',
    [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
} finally { $zip.Dispose() }

Write-Host '6/7 zipalign...'
& $zipalign -f 4 (Join-Path $build 'base.apk') (Join-Path $build 'aligned.apk')
if ($LASTEXITCODE -ne 0) { throw 'zipalign failed' }

Write-Host '7/7 sign (apksigner)...'
$outApk = Join-Path $root ([string][char]0x9884 + [char]0x7B97 + [char]0x7BA1 + [char]0x7406 + '.apk')
& $java -jar $apksigner sign `
  --key (Join-Path $certDir 'key.pk8') `
  --cert (Join-Path $certDir 'cert.pem') `
  --out $outApk (Join-Path $build 'aligned.apk')
if ($LASTEXITCODE -ne 0) { throw 'sign failed' }

& $java -jar $apksigner verify --print-certs $outApk
& $aapt2 dump badging $outApk | Select-Object -First 12

Write-Host ''
Write-Host "done: $outApk"
Get-Item $outApk | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,2)}}
