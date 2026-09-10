<#
Patch the user-supplied Sergey XT BIOS for a SPK286 bring-up run.

The original image is never modified.  The patch changes only the conditional
branch which prints the 8088 segment-register warning; the CPU probe and all
other BIOS code remain byte-for-byte identical.
#>
[CmdletBinding()]
param(
    [string]$InputPath,
    [string]$OutputPath,
    [switch]$BypassFpu
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $InputPath = Join-Path $PSScriptRoot '..\SW\ROMs\test\xtsergey_mod.rom'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $suffix = if ($BypassFpu) { 'spk286_nofpu' } else { 'spk286' }
    $OutputPath = Join-Path $PSScriptRoot "..\SW\ROMs\test\xtsergey_mod_$suffix.rom"
}

$expectedInputSha256 = 'DF25BBC8ABA4E35EB56CA585B2C7054DA1D7435278B2BFE0F0C7FFAE2F85F443'
$patches = @(
    @{ Offset = 0xD721; Expected = [byte[]](0x75, 0x06); Replacement = [byte[]](0xEB, 0x06); Description = 'skip the 8088 segment-register warning' }
)
if ($BypassFpu) {
    $patches += @{ Offset = 0xD752; Expected = [byte[]](0xDB, 0xE3); Replacement = [byte[]](0x90, 0x90); Description = 'replace FNINIT with NOPs' }
    $patches += @{ Offset = 0xD763; Expected = [byte[]](0xD9, 0x3E, 0xFE, 0x03); Replacement = [byte[]](0x90, 0x90, 0x90, 0x90); Description = 'replace FNSTCW with NOPs' }
}

$inputFullPath = [IO.Path]::GetFullPath($InputPath)
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
if (-not [IO.File]::Exists($inputFullPath)) {
    throw "Input ROM not found: $inputFullPath"
}

$inputHash = (Get-FileHash -LiteralPath $inputFullPath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($inputHash -ne $expectedInputSha256) {
    throw "Unexpected input ROM SHA-256 ($inputHash). Refusing to patch a different image."
}

$bytes = [IO.File]::ReadAllBytes($inputFullPath)
if ($bytes.Length -ne 65536) {
    throw "Unexpected input ROM size: $($bytes.Length) bytes (expected 65536)."
}
foreach ($patch in $patches) {
    $offset = $patch.Offset
    $expectedBytes = $patch.Expected
    for ($i = 0; $i -lt $expectedBytes.Length; $i++) {
        if ($bytes[$offset + $i] -ne $expectedBytes[$i]) {
            $got = ($bytes[$offset..($offset + $expectedBytes.Length - 1)] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            $expected = ($expectedBytes | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            throw ('Unexpected bytes at ROM offset 0x{0:X4}: got {1}, expected {2}.' -f $offset, $got, $expected)
        }
    }
    for ($i = 0; $i -lt $patch.Replacement.Length; $i++) {
        $bytes[$offset + $i] = $patch.Replacement[$i]
    }
}

$outputDirectory = Split-Path -Parent $outputFullPath
if (-not [IO.Directory]::Exists($outputDirectory)) {
    [IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}
if ([IO.File]::Exists($outputFullPath)) {
    $existingHash = (Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256).Hash.ToUpperInvariant()
    $newHash = ([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)
    $newHashText = ([BitConverter]::ToString($newHash) -replace '-', '').ToUpperInvariant()
    if ($existingHash -ne $newHashText) {
        throw "Refusing to overwrite an existing different output ROM: $outputFullPath"
    }
    Write-Output "Already present: $outputFullPath"
    Write-Output "SHA-256: $existingHash"
    exit 0
}

[IO.File]::WriteAllBytes($outputFullPath, $bytes)
$outputHash = (Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256).Hash.ToUpperInvariant()
Write-Output "Created: $outputFullPath"
foreach ($patch in $patches) {
    $oldBytes = ($patch.Expected | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
    $newBytes = ($patch.Replacement | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
    Write-Output ('Patched ROM offset: 0x{0:X4} ({1} -> {2}; {3})' -f $patch.Offset, $oldBytes, $newBytes, $patch.Description)
}
Write-Output "SHA-256: $outputHash"
