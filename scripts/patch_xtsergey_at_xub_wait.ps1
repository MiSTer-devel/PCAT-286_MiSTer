<##
Adapt the already AT-keyboard-patched Sergey XT BIOS for the AT XUB wait
contract.

The AT XUB calls INT 15h/AH=86h (wait).  The Sergey XT-derived BIOS does not
implement that AT service and deliberately returns CF=1, which makes XUB fall
back to a BDA-tick wait.  That fallback is not useful during this core's
bring-up and can leave the XUB progress indicator spinning forever.

This produces a separate BIOS image.  The original xtsergey_mod_at.rom is
never overwritten.
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
    $OutputPath = Join-Path $PSScriptRoot '..\SW\ROMs\test\xtsergey_mod_at_xub.rom'
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

# The original INT 15h dispatcher reaches MOV AH,86h and then the generic
# error return. Replace that two-byte instruction with a CALL trampoline. The
# trampoline preserves the old error behavior for every unsupported function,
# but returns AH=00h/CF=0 for AH=86h. The two-byte continuation is CLC/IRET;
# the trampoline returns there only for the successful AH=86h case.
$dispatcherOffset = 0xF873
Assert-Bytes $bytes $dispatcherOffset ([byte[]](0xB4, 0x86, 0x55, 0x89, 0xE5)) 'INT 15h unsupported-service path'

$waitRoutineOffset = 0xF820
$waitRoutine = [byte[]](
    0x80, 0xFC, 0x86,       # CMP AH,86h
    0x75, 0x0B,             # JNZ error path at F830h
    0xF8, 0xB4, 0x00, 0xC3, # CLC / MOV AH,00h / RET
    0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
    0xB4, 0x86,             # error: restore AH=86h
    0x83, 0xC4, 0x02,       # discard CALL return address
    0x55, 0x89, 0xE5,       # PUSH/MOV BP
    0x80, 0x4E, 0x06, 0x01, # set CF in saved FLAGS
    0x5D, 0xCF              # POP BP / IRET
)
Assert-Bytes $bytes $waitRoutineOffset ([byte[]](0xFF) * $waitRoutine.Length) 'INT 15h wait routine padding'

# CALL F820h from F873h (return address F876h), followed by CLC/IRET.
Write-Bytes $bytes $dispatcherOffset ([byte[]](0xE8, 0xAA, 0xFF, 0xF8, 0xCF))
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
Write-Output 'INT 15h/AH=86h: CF cleared, immediate successful return'
Write-Output ('BIOS checksum: 00h; final byte FFFFh = {0:X2}' -f $bytes[0xFFFF])
Write-Output "SHA-256: $outputHash"
