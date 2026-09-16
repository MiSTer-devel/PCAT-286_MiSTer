<##
Adapt the already AT-keyboard-patched Sergey XT BIOS for the AT XUB and the
AT interrupt controller.

The supplied BIOS is XT-derived: it has an AT keyboard patch, but its POST
still initializes a single XT-style 8259 with ICW1=13h.  The AT XUB also uses
INT 15h/AH=86h while probing.  This produces a separate diagnostic BIOS with:

  - AT cascade initialization (master 20h/21h, slave A0h/A1h), and
  - a successful INT 15h/AH=86h service.

The original xtsergey_mod_at.rom is never overwritten.
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
    $OutputPath = Join-Path $PSScriptRoot '..\SW\ROMs\test\xtsergey_mod_at_xub_atpic.rom'
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

# Replace the XT single-PIC sequence with a near call into an unused ROM
# padding area.  The code after this 12-byte sequence (the POST-port write at
# E1D9) remains at the original address and is therefore still executed.
$picCallOffset = 0xE1CD
$picCallOriginal = [byte[]](
    0xB0, 0x13, 0xE6, 0x20, 0xB0, 0x08,
    0xE6, 0x21, 0xB0, 0x09, 0xE6, 0x21
)
Assert-Bytes $bytes $picCallOffset $picCallOriginal 'XT single-PIC initialization'

# This is the same sequence used by the AT-capable Xi8088 build: ICW1 to both
# PICs, vectors 08h/70h, cascade on master IR2 and slave ID 2, then ICW4=01.
$picRoutineOffset = 0xFA27
$picRoutine = [byte[]](
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
Assert-Bytes $bytes $picRoutineOffset ([byte[]](0xFF) * $picRoutine.Length) 'AT PIC routine padding'
$picDisplacement = $picRoutineOffset - ($picCallOffset + 3)
$picCall = [byte[]](0xE8, ($picDisplacement -band 0xFF), (($picDisplacement -shr 8) -band 0xFF)) + ([byte[]](0x90) * 9)
Write-Bytes $bytes $picCallOffset $picCall
Write-Bytes $bytes $picRoutineOffset $picRoutine

# The XT image later unmasks the master with BCh and never initializes the
# slave mask. Replace that five-byte enable sequence with an AT version while
# keeping STI and the following POST code at the same logical point.
$enableCallOffset = 0xE206
$enableOriginal = [byte[]](0xB0, 0xBC, 0xE6, 0x21, 0xFB)
Assert-Bytes $bytes $enableCallOffset $enableOriginal 'XT PIC enable/mask sequence'
$enableRoutineOffset = 0xE359
$enableRoutine = [byte[]](
    0xB0, 0xB8,       # MOV AL,B8h: unmask IRQ0, IRQ1, IRQ2 and IRQ6
    0xE6, 0x21,       # OUT 21h,AL
    0xB0, 0xFD,       # MOV AL,FDh: unmask slave IRQ8/IRQ9
    0xE6, 0xA1,       # OUT A1h,AL
    0xFB,             # STI
    0xC3              # RET
)
Assert-Bytes $bytes $enableRoutineOffset ([byte[]](0xFF) * $enableRoutine.Length) 'AT PIC mask routine padding'
$enableDisplacement = $enableRoutineOffset - ($enableCallOffset + 3)
$enableCall = [byte[]](0xE8, ($enableDisplacement -band 0xFF), (($enableDisplacement -shr 8) -band 0xFF), 0x90, 0x90)
Write-Bytes $bytes $enableCallOffset $enableCall
Write-Bytes $bytes $enableRoutineOffset $enableRoutine

# The original INT 15h dispatcher reaches MOV AH,86h and then the generic
# error return.  Preserve that error path for all other functions, but make
# AH=86h return with AH=00h and CF=0 so the AT XUB does not enter its fallback
# BDA-tick wait while this XT-derived BIOS is being used.
$dispatcherOffset = 0xF873
Assert-Bytes $bytes $dispatcherOffset ([byte[]](0xB4, 0x86, 0x55, 0x89, 0xE5)) 'INT 15h unsupported-service path'

$waitRoutineOffset = 0xF81C
$waitRoutine = [byte[]](
    0x80, 0xFC, 0x86,       # CMP AH,86h
    0x75, 0x0B,             # JNZ error path at F82Ch
    0xF8, 0xB4, 0x00, 0xC3, # CLC / MOV AH,00h / RET
    0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
    0xB4, 0x86,             # error: restore AH=86h
    0x83, 0xC4, 0x02,       # discard CALL return address
    0x55, 0x89, 0xE5,       # PUSH/MOV BP
    0x80, 0x4E, 0x06, 0x01, # set CF in saved FLAGS
    0x5D, 0xCF              # POP BP / IRET
)
Assert-Bytes $bytes $waitRoutineOffset ([byte[]](0xFF) * $waitRoutine.Length) 'INT 15h wait routine padding'

$waitDisplacement = $waitRoutineOffset - ($dispatcherOffset + 3)
Write-Bytes $bytes $dispatcherOffset ([byte[]](0xE8, ($waitDisplacement -band 0xFF), (($waitDisplacement -shr 8) -band 0xFF), 0xF8, 0xCF))
Write-Bytes $bytes $waitRoutineOffset $waitRoutine

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
Write-Output 'AT PIC cascade: master 20h/21h, slave A0h/A1h, vectors 08h/70h, cascade IR2'
Write-Output 'INT 15h/AH=86h: CF cleared, immediate successful return'
Write-Output ('BIOS checksum: 00h; final byte FFFFh = {0:X2}' -f $bytes[0xFFFF])
Write-Output "SHA-256: $outputHash"
