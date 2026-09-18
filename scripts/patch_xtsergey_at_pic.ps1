<##
Convert only the XT single-PIC initialization in the AT-keyboard-patched
Sergey BIOS into the normal AT master/slave cascade initialization.

This is intentionally an isolated experiment: INT 15h/AH=86h and every
other BIOS routine remain byte-for-byte unchanged. The original ROM is never
overwritten.
#>
[CmdletBinding()]
param(
    [string]$InputPath,
    [string]$OutputPath,
    [string]$ReplaceOutputSha256
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $InputPath = Join-Path $PSScriptRoot '..\SW\ROMs\test\xtsergey_mod_at.rom'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot '..\SW\ROMs\test\xtsergey_mod_at_atpic.rom'
}

$expectedInputSha256 = 'D023FD7B2777845775C78F0A149CA379ABA2A4BFF61D057BD184731691897624'
$inputFullPath = [IO.Path]::GetFullPath($InputPath)
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
if ($inputFullPath -eq $outputFullPath) {
    throw 'The output must be different from the input BIOS.'
}
if (-not [IO.File]::Exists($inputFullPath)) {
    throw "Input BIOS not found: $inputFullPath"
}

$inputHash = (Get-FileHash -LiteralPath $inputFullPath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($inputHash -ne $expectedInputSha256) {
    throw "Unexpected input BIOS SHA-256 ($inputHash); refusing to patch a different image."
}

$bytes = [IO.File]::ReadAllBytes($inputFullPath)
if ($bytes.Length -ne 65536) {
    throw "Unexpected BIOS size: $($bytes.Length) bytes (expected 65536)."
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

# The original XT POST sequence is 12 bytes. Replace it with a CALL plus
# nine NOPs so the following POST code keeps its original address.
$callOffset = 0xE1CD
$original = [byte[]](
    0xB0, 0x13, 0xE6, 0x20, 0xB0, 0x08,
    0xE6, 0x21, 0xB0, 0x09, 0xE6, 0x21
)
Assert-Bytes $bytes $callOffset $original 'XT single-PIC initialization'

# AT-compatible 8259 initialization, matching the SECOND_PIC branch of the
# Sergey BIOS source: vectors 08h/70h, master cascade IR2, slave ID 2, ICW4
# in 8086 mode. The routine lives in an FF-filled ROM hole.
$routineOffset = 0xFA27
$routine = [byte[]](
    0xB0, 0x11,       # MOV AL,11h
    0xE6, 0x20,       # OUT 20h,AL
    0xE6, 0xA0,       # OUT A0h,AL
    0xB0, 0x08,       # MOV AL,08h
    0xE6, 0x21,       # OUT 21h,AL
    0xB0, 0x70,       # MOV AL,70h
    0xE6, 0xA1,       # OUT A1h,AL
    0xB0, 0x04,       # MOV AL,04h
    0xE6, 0x21,       # OUT 21h,AL
    0xB0, 0x02,       # MOV AL,02h
    0xE6, 0xA1,       # OUT A1h,AL
    0xB0, 0x01,       # MOV AL,01h
    0xE6, 0x21,       # OUT 21h,AL
    0xE6, 0xA1,       # OUT A1h,AL
    0xC3              # RET
)
Assert-Bytes $bytes $routineOffset ([byte[]](0xFF) * $routine.Length) 'AT PIC routine padding'
$displacement = $routineOffset - ($callOffset + 3)
$call = [byte[]](0xE8, ($displacement -band 0xFF), (($displacement -shr 8) -band 0xFF)) + ([byte[]](0x90) * 9)
Write-Bytes $bytes $callOffset $call
Write-Bytes $bytes $routineOffset $routine

# The XT image later unmasks the master with BCh and never initializes the
# slave mask. Replace only that five-byte enable sequence with a call into a
# second ROM hole. The routine keeps STI in the same logical position and
# leaves the following NMI/port-61 code untouched.
$enableCallOffset = 0xE206
$enableOriginal = [byte[]](0xB0, 0xBC, 0xE6, 0x21, 0xFB)
Assert-Bytes $bytes $enableCallOffset $enableOriginal 'XT PIC enable/mask sequence'
$enableRoutineOffset = 0xE359
$enableRoutine = [byte[]](
    0xB0, 0xB8,       # MOV AL,B8h: unmask IRQ0, IRQ1, IRQ2 and IRQ6
    0xE6, 0x21,       # OUT 21h,AL
    0xB0, 0xFB,       # MOV AL,FBh: unmask slave IRQ8; keep IRQ9 masked
    0xE6, 0xA1,       # OUT A1h,AL
    0xFB,             # STI
    0xC3              # RET
)
Assert-Bytes $bytes $enableRoutineOffset ([byte[]](0xFF) * $enableRoutine.Length) 'AT PIC mask routine padding'
$enableDisplacement = $enableRoutineOffset - ($enableCallOffset + 3)
$enableCall = [byte[]](0xE8, ($enableDisplacement -band 0xFF), (($enableDisplacement -shr 8) -band 0xFF), 0x90, 0x90)
Write-Bytes $bytes $enableCallOffset $enableCall
Write-Bytes $bytes $enableRoutineOffset $enableRoutine

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
    throw ('BIOS checksum validation failed: final sum is {0:X2}.' -f $finalSum)
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
            throw "Refusing to overwrite an existing different BIOS: $outputFullPath"
        }
        [IO.File]::WriteAllBytes($outputFullPath, $bytes)
    }
} else {
    [IO.File]::WriteAllBytes($outputFullPath, $bytes)
}

Write-Output "Created/verified: $outputFullPath"
Write-Output 'Only BIOS change: AT PIC cascade initialization (20h/21h + A0h/A1h)'
Write-Output ('BIOS checksum: 00h; final byte FFFFh = {0:X2}' -f $bytes[0xFFFF])
Write-Output "SHA-256: $outputHash"
