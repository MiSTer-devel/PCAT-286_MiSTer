<#
Adapt the user-supplied Sergey XT BIOS to the SPK286 AT keyboard boundary.

The XT BIOS image is preserved.  The generated image changes only:
  - the keyboard-controller initialization block;
  - the IRQ1 read/acknowledge prologue;
  - a small 8042 enable routine placed in unused ROM padding;
  - the final ROM checksum byte.
#>
[CmdletBinding()]
param(
    [string]$InputPath,
    [string]$OutputPath,
    # Replacing an earlier generated ROM requires its exact current hash.
    [string]$ReplaceOutputSha256
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $InputPath = Join-Path $PSScriptRoot '..\SW\ROMs\xtsergey_mod.rom'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot '..\SW\ROMs\xtsergey_mod_at.rom'
}

$expectedInputSha256 = 'DF25BBC8ABA4E35EB56CA585B2C7054DA1D7435278B2BFE0F0C7FFAE2F85F443'
$inputFullPath = [IO.Path]::GetFullPath($InputPath)
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
if ($inputFullPath -eq $outputFullPath) {
    throw 'The output must be different from the original XT ROM.'
}

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

function Assert-Bytes([byte[]]$Image, [int]$Offset, [byte[]]$Expected, [string]$Description) {
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Image[$Offset + $i] -ne $Expected[$i]) {
            $got = ($Image[$Offset..($Offset + $Expected.Length - 1)] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            $want = ($Expected | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            throw ('Unexpected bytes for {0} at 0x{1:X4}: got {2}, expected {3}.' -f $Description, $Offset, $got, $want)
        }
    }
}

function Write-Bytes([byte[]]$Image, [int]$Offset, [byte[]]$Replacement) {
    for ($i = 0; $i -lt $Replacement.Length; $i++) {
        $Image[$Offset + $i] = $Replacement[$i]
    }
}

# The original XT reset/flush sequence manipulates the 8255 PPI at 61h.
# Replace it with: write AT 8042 command-byte command, set IRQ1/system/
# translation bits, then enable the keyboard interface.
$initOffset = 0xE1DD
$routineOffset = 0xD894
$initOriginal = [byte[]](
    0xE4, 0x61, 0x24, 0x3F, 0xE6, 0x61, 0xB9, 0x56, 0x29,
    0xE2, 0xFE, 0x0C, 0xC0, 0xE6, 0x61, 0x24, 0x7F, 0xE6,
    0x61, 0xB9, 0xE8, 0x03, 0xB4, 0x01, 0xCD, 0x16, 0x74,
    0x04, 0xB4, 0x00, 0xCD, 0x16, 0xE2, 0xF4
)
Assert-Bytes $bytes $initOffset $initOriginal 'XT keyboard initialization'
# The block is 34 bytes (22h), ending at E1FEh. E1FFh is the opcode of
# CALL EB9Dh (kbd_buffer_init), not padding. Derive lengths from verified
# bytes so replacement padding cannot eat the following instruction.
$initLength = $initOriginal.Length
$resumeOffset = $initOffset + $initLength
if ($resumeOffset -ne 0xE1FF) {
    throw 'Unexpected keyboard initialization boundary.'
}
$resumeCall = [byte[]](0xE8, 0x9B, 0x09)
Assert-Bytes $bytes $resumeOffset $resumeCall 'following CALL kbd_buffer_init'
$initDisplacement = ($routineOffset - ($initOffset + 3)) -band 0xFFFF
$initReplacement = [byte[]](0xE8, ($initDisplacement -band 0xFF), ($initDisplacement -shr 8)) + [byte[]](0x90) * ($initLength - 3)

# The XT ISR clears the keyboard latch through PPI port 61h.  On AT, reading
# port 60h consumes the 8042 output-buffer byte, so the PPI sequence must go.
$irqOffset = 0xE987
$irqOriginal = [byte[]](
    0x50, 0x53, 0x1E, 0xB8, 0x40, 0x00, 0x8E, 0xD8, 0xE4, 0x60,
    0x88, 0xC4, 0xE4, 0x61, 0x0C, 0x80, 0xE6, 0x61, 0x24, 0x7F,
    0xE6, 0x61, 0x88, 0xE0, 0xFB
)
Assert-Bytes $bytes $irqOffset $irqOriginal 'XT IRQ1 keyboard acknowledge'
$irqLength = $irqOriginal.Length
$irqReplacement = [byte[]](0x50, 0x53, 0x1E, 0xB8, 0x40, 0x00, 0x8E, 0xD8, 0xE4, 0x60, 0xFB) + [byte[]](0x90) * ($irqLength - 11)

# Unused ROM padding between the fixed BIOS routines.
$routine = [byte[]](
    0xB0, 0x60,       # MOV AL,60h
    0xE6, 0x64,       # OUT 64h,AL   (write command byte)
    0xB0, 0x65,       # MOV AL,65h   (IRQ1 + system + translation)
    0xE6, 0x60,       # OUT 60h,AL   (write command byte value)
    0xB0, 0xAE,       # MOV AL,AEh
    0xE6, 0x64,       # OUT 64h,AL   (enable keyboard interface)
    0xC3              # RET
)
Assert-Bytes $bytes $routineOffset ([byte[]](0xFF) * $routine.Length) 'unused routine padding'
Write-Bytes $bytes $initOffset $initReplacement
Write-Bytes $bytes $irqOffset $irqReplacement
Write-Bytes $bytes $routineOffset $routine
Assert-Bytes $bytes $resumeOffset $resumeCall 'preserved CALL kbd_buffer_init after patch'
if ((($initOffset + 3 + $bytes[$initOffset + 1] + 256 * $bytes[$initOffset + 2]) -band 0xFFFF) -ne $routineOffset) {
    throw 'Invalid displacement in the AT initialization CALL.'
}

# Use the last byte as the ROM checksum byte.  The system model byte at FFFEh
# remains untouched.  A valid 64 KiB image has a modulo-256 sum of zero.
Assert-Bytes $bytes 0xFFFF ([byte[]](0xFF)) 'original final checksum placeholder'
$sumWithoutChecksum = 0
for ($i = 0; $i -lt ($bytes.Length - 1); $i++) {
    $sumWithoutChecksum = ($sumWithoutChecksum + $bytes[$i]) -band 0xFF
}
$bytes[0xFFFF] = ((-$sumWithoutChecksum) -band 0xFF)

$finalSum = 0
foreach ($value in $bytes) {
    $finalSum = ($finalSum + $value) -band 0xFF
}
if ($finalSum -ne 0) {
    throw ('ROM checksum validation failed: final sum is {0:X2}.' -f $finalSum)
}

$outputDirectory = Split-Path -Parent $outputFullPath
if (-not [IO.Directory]::Exists($outputDirectory)) {
    [IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

$outputHashBytes = ([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes)
$outputHash = ([BitConverter]::ToString($outputHashBytes) -replace '-', '').ToUpperInvariant()
if ([IO.File]::Exists($outputFullPath)) {
    $existingHash = (Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($existingHash -ne $outputHash) {
        if ([string]::IsNullOrWhiteSpace($ReplaceOutputSha256) -or $existingHash -ne $ReplaceOutputSha256) {
            throw "Refusing to overwrite an existing different output ROM: $outputFullPath"
        }
        [IO.File]::WriteAllBytes($outputFullPath, $bytes)
    }
} else {
    [IO.File]::WriteAllBytes($outputFullPath, $bytes)
}

Write-Output "Created/verified: $outputFullPath"
Write-Output ('AT init call: 0x{0:X4} -> routine 0x{1:X4}' -f $initOffset, $routineOffset)
Write-Output ('Original CALL kbd_buffer_init preserved at 0x{0:X4}' -f $resumeOffset)
Write-Output ('AT IRQ1 prologue patched at 0x{0:X4}' -f $irqOffset)
Write-Output ('ROM checksum: 00h; final byte FFFFh = {0:X2}' -f $bytes[0xFFFF])
Write-Output "SHA-256: $outputHash"
