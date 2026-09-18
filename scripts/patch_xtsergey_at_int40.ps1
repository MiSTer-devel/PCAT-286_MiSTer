<#
Install the AT floppy-service vector INT 40h before option ROM initialization.
XUB AT r631 calls INT 40h/AH=08h while deciding whether INT 13h already owns
hard disks. Sergey XT initializes only vectors 00h-1Fh, so that call otherwise
lands at 0000:0000. Copy the original INT 13h vector to INT 40h during POST.

Default input is the previously tested AT-PIC variant. The source ROM and
all existing service routines are preserved; output is a separate 64KiB ROM.
#>
[CmdletBinding()]
param(
    [string]$InputPath,
    [string]$OutputPath,
    [string]$ReplaceOutputSha256
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($InputPath)) {
    $InputPath = Join-Path $PSScriptRoot '..\SW\ROMs\test\xtsergey_mod_at_atpic.rom'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot '..\SW\ROMs\test\xtsergey_mod_at_atpic_int40.rom'
}
$inputFullPath = [IO.Path]::GetFullPath($InputPath)
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
if ($inputFullPath -eq $outputFullPath) { throw 'Input and output must differ.' }
$hash = (Get-FileHash -LiteralPath $inputFullPath -Algorithm SHA256).Hash
$known = @(
    'D023FD7B2777845775C78F0A149CA379ABA2A4BFF61D057BD184731691897624',
    'B2EB742FBE6363473CBB2D824767DB9BA695B5E7A3E732331C115C0679E5DB70',
    '731B19DD1E19AA1780CBA899A029323EE1B029943CB7DBDB5B50E20A4EBE1B59'
)
if ($hash -notin $known) { throw "Unsupported source BIOS SHA256: $hash" }
$bytes = [IO.File]::ReadAllBytes($inputFullPath)
if ($bytes.Length -ne 65536) { throw 'BIOS must be exactly 64KiB.' }
function Assert-Bytes([int]$Offset, [byte[]]$Expected) {
    for ($i=0; $i -lt $Expected.Length; $i++) {
        if ($bytes[$Offset+$i] -ne $Expected[$i]) {
            throw ('Unexpected source byte at {0:X4}' -f ($Offset+$i))
        }
    }
}
$hook = 0xE1AB
Assert-Bytes $hook ([byte[]](0xB8,0x40,0x00,0x8E,0xD8))
$target = 0xE370
# ES=0000h here: the preceding loop has just installed the original IVT.
# These MOVs preserve FLAGS and every register except AX/DS, whose final
# values are the same as the replaced MOV AX,0040h / MOV DS,AX sequence.
$routine = [byte[]](
    0x26,0xA1,0x4C,0x00, # MOV AX,[ES:004Ch] (INT13 offset)
    0x26,0xA3,0x00,0x01, # MOV [ES:0100h],AX (INT40 offset)
    0x26,0xA1,0x4E,0x00, # MOV AX,[ES:004Eh] (INT13 segment)
    0x26,0xA3,0x02,0x01, # MOV [ES:0102h],AX (INT40 segment)
    0xB8,0x40,0x00,      # MOV AX,0040h
    0x8E,0xD8,           # MOV DS,AX
    0xC3                # RET
)
Assert-Bytes $target ([byte[]](0xFF) * $routine.Length)
$disp = $target - ($hook+3)
$replacement = [byte[]](0xE8,($disp -band 0xFF),(($disp -shr 8) -band 0xFF),0x90,0x90)
[Array]::Copy($replacement,0,$bytes,$hook,$replacement.Length)
[Array]::Copy($routine,0,$bytes,$target,$routine.Length)
$sum=0
for ($i=0; $i -lt 65535; $i++) { $sum=($sum+$bytes[$i]) -band 255 }
$bytes[65535]=(-$sum) -band 255
$outputHash=([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($bytes))).Replace('-','')
if (Test-Path -LiteralPath $outputFullPath) {
    $existingHash = (Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($existingHash -ne $outputHash) {
        if ([string]::IsNullOrWhiteSpace($ReplaceOutputSha256) -or
            $existingHash -ne $ReplaceOutputSha256.ToUpperInvariant()) {
            throw "Refusing to overwrite a different ROM: $outputFullPath"
        }
        [IO.File]::WriteAllBytes($outputFullPath,$bytes)
    }
} else {
    [IO.File]::WriteAllBytes($outputFullPath,$bytes)
}
Write-Output "Created/verified: $outputFullPath"
Write-Output 'INT40 -> original INT13; size=65536; sum8=00; reset vector preserved'
Write-Output "SHA256: $outputHash"
