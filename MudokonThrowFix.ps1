[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Restore', 'Status')]
    [string]$Action = 'Apply',
    [string]$Path,
    [string]$Fixes = '1,2,3'
)

$ErrorActionPreference = 'Stop'

if (-not $Path) {
    $Path = Join-Path (Split-Path -Parent $PSScriptRoot) 'GameAssembly.dll'
}
$Backup = "$Path.pre-mudokon-fix.bak"
$OriginalSha256 = 'D8F3F565159D76402BD29DB28A10A5A645821C833B9DD6742ACA4E69E10F9226'
[int[]]$Selected = $Fixes -split '[,; ]+' | Where-Object { $_ } | ForEach-Object { [int]$_ }
foreach ($f in $Selected) { if ($f -lt 1 -or $f -gt 3) { throw "Unknown fix number $f (use 1, 2, 3)." } }

$RestoreLastThrow      = 0x148DECA
$RestoreLastWaterThrow = 0x148DEDB
$ThrowExitSite   = 0x11ECB2A
$ThrowExitResume = 0x11ECB31
$QueueSite       = 0x149BA91
$QueueResume     = 0x149BA9D
$CaveStart       = 0x2149F9C
$CaveEnd         = 0x214A000
$Cave1           = 0x2149FA0
$Cave2           = 0x2149FC0
$Il2cppVSizeOld  = 0x1E54F9C
$Il2cppVSizeNew  = 0x1E55000
$GoToThrowFlag   = 0x11E9EFE
$GateSite        = 0x11EC417
$GateCheck       = 0x11EC41F
$GateAbort       = 0x11EC45D
$GateSkip        = 0x11EC46C
$PantsSligClass  = 0x2C2DC28
$DeadMethod      = 0x11D2B70
$Cave3           = 0x11D2B80
$DeadMethodOld   = '48895c240848897c241055488bec4883ec700f29742460488bd9803dcc69a20100754c488b055696a101486390b8000000488b052096a1018b8c02f01c04004533c04c8945d04c8945d84c8945e04c8d45d08b9402f41c0400e862fbecfe9033c9ff1591af830190c6057e69a201010f28059ab365010f'

[byte[]]$Nop8 = 0x0F, 0x1F, 0x84, 0x00, 0x00, 0x00, 0x00, 0x00

function ConvertFrom-Hex([string]$Hex) {
    $out = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $out.Length; $i++) { $out[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16) }
    return ,$out
}

function Get-Rel32([int]$From, [int]$To) {

    return ,[BitConverter]::GetBytes([int32]($To - ($From + 5)))
}

function Get-Rel8([int]$From, [int]$To) {

    $d = $To - ($From + 2)
    if ($d -lt -128 -or $d -gt 127) { throw 'short jump out of range' }
    return [byte]($d -band 0xFF)
}

function Get-GateStub {
    $abort = $Cave3 + 93
    $skip  = $Cave3 + 98
    [byte[]]$b = 0x80, 0xBB, 0xB0, 0x0F, 0x00, 0x00, 0x01
    $b += 0x0F, 0x82
    $b += Get-Rel32 ($Cave3 + 8) $GateCheck
    $b += 0x77, (Get-Rel8 ($Cave3 + 13) $skip)
    $b += 0x8B, 0x83, 0xB8, 0x0F, 0x00, 0x00
    $b += 0x85, 0xC0
    $b += 0x74, 0x05
    $b += 0x83, 0xF8, 0x02
    $b += 0x75, (Get-Rel8 ($Cave3 + 28) $skip)
    $b += 0x48, 0x8B, 0x8B, 0x88, 0x0B, 0x00, 0x00
    $b += 0x48, 0x85, 0xC9
    $b += 0x74, (Get-Rel8 ($Cave3 + 40) $skip)
    $b += 0x48, 0x8B, 0x49, 0x10
    $b += 0x48, 0x85, 0xC9
    $b += 0x74, (Get-Rel8 ($Cave3 + 49) $skip)
    $b += 0x83, 0xB9, 0xA4, 0x03, 0x00, 0x00, 0x00
    $b += 0x7E, (Get-Rel8 ($Cave3 + 58) $abort)
    $b += 0x48, 0x8B, 0x11
    $b += 0x48, 0x3B, 0x15
    $b += [BitConverter]::GetBytes([int32]($PantsSligClass - ($Cave3 + 70)))
    $b += 0x75, (Get-Rel8 ($Cave3 + 70) $skip)
    $b += 0x8B, 0x81, 0xC8, 0x0E, 0x00, 0x00
    $b += 0x83, 0xF8, 0x09
    $b += 0x74, (Get-Rel8 ($Cave3 + 81) $abort)
    $b += 0x83, 0xF8, 0x10
    $b += 0x74, (Get-Rel8 ($Cave3 + 86) $abort)
    $b += 0x83, 0xF8, 0x12
    $b += 0x75, (Get-Rel8 ($Cave3 + 91) $skip)
    $b += 0xE9
    $b += Get-Rel32 ($Cave3 + 93) $GateAbort
    $b += 0xE9
    $b += Get-Rel32 ($Cave3 + 98) $GateSkip
    if ($b.Length -ne 103) { throw "gate stub is $($b.Length) bytes, expected 103" }
    return ,$b
}

function Get-Sections([byte[]]$Data) {
    $pe = [BitConverter]::ToInt32($Data, 0x3C)
    if ([BitConverter]::ToUInt32($Data, $pe) -ne 0x4550) { throw 'Not a PE file.' }
    $count = [BitConverter]::ToUInt16($Data, $pe + 6)
    $optSize = [BitConverter]::ToUInt16($Data, $pe + 20)
    $table = $pe + 24 + $optSize
    $list = @()
    for ($i = 0; $i -lt $count; $i++) {
        $o = $table + $i * 40
        $list += [pscustomobject]@{
            Name    = [Text.Encoding]::ASCII.GetString($Data, $o, 8).TrimEnd([char]0)
            Header  = $o
            VSize   = [BitConverter]::ToUInt32($Data, $o + 8)
            VA      = [BitConverter]::ToUInt32($Data, $o + 12)
            RawSize = [BitConverter]::ToUInt32($Data, $o + 16)
            Raw     = [BitConverter]::ToUInt32($Data, $o + 20)
        }
    }
    return $list
}

function Get-Patches([byte[]]$Data) {
    $il2cpp = Get-Sections $Data | Where-Object { $_.Name -eq 'il2cpp' }
    if (-not $il2cpp) { throw 'il2cpp section not found.' }
    if ($il2cpp.VA + $il2cpp.RawSize -ne $CaveEnd) { throw 'Unexpected il2cpp section layout.' }
    $delta = [int]$il2cpp.Raw - [int]$il2cpp.VA

    $cave = New-Object byte[] ($CaveEnd - $CaveStart)
    for ($i = 0; $i -lt $cave.Length; $i++) { $cave[$i] = 0xCC }

    [byte[]]$s1 = 0xC6, 0x83, 0xA8, 0x0F, 0x00, 0x00, 0x00,
                  0x66, 0xC7, 0x83, 0xB0, 0x0F, 0x00, 0x00, 0x00, 0x00
    $s1 += 0xE9
    $s1 += Get-Rel32 ($Cave1 + 16) $ThrowExitResume
    [Array]::Copy($s1, 0, $cave, $Cave1 - $CaveStart, $s1.Length)

    [byte[]]$s2 = 0x33, 0xC9,
                  0x41, 0x81, 0x7E, 0x70, 0x19, 0x08, 0x00, 0x00,
                  0x75, 0x09,
                  0x41, 0x38, 0x8E, 0xB0, 0x0F, 0x00, 0x00,
                  0x75, 0x02,
                  0xB1, 0x01
    $s2 += 0xE9
    $s2 += Get-Rel32 ($Cave2 + 23) $QueueResume
    [Array]::Copy($s2, 0, $cave, $Cave2 - $CaveStart, $s2.Length)
    [byte[]]$hook1 = @(0xE9) + (Get-Rel32 $ThrowExitSite $Cave1) + @(0x66, 0x90)
    [byte[]]$hook2 = @(0xE9) + (Get-Rel32 $QueueSite $Cave2) + @(0x0F, 0x1F, 0x80, 0x00, 0x00, 0x00, 0x00)

    $deadOld = ConvertFrom-Hex $DeadMethodOld
    $deadNew = New-Object byte[] $deadOld.Length
    $deadNew[0] = 0xC3
    for ($i = 1; $i -lt 16; $i++) { $deadNew[$i] = 0xCC }
    $s3 = Get-GateStub
    if (16 + $s3.Length -ne $deadOld.Length) { throw 'dead-method patch size mismatch' }
    [Array]::Copy($s3, 0, $deadNew, $Cave3 - $DeadMethod, $s3.Length)
    [byte[]]$hook3 = @(0xE9) + (Get-Rel32 $GateSite $Cave3) + @(0x0F, 0x1F, 0x00)

    return @(
        [pscustomobject]@{ Fix = 1; Name = 'keep m_fLastThrow on load'; Offset = $RestoreLastThrow + $delta
            Old = [byte[]](0xF3, 0x0F, 0x11, 0x8E, 0x70, 0x0B, 0x00, 0x00); New = $Nop8 }
        [pscustomobject]@{ Fix = 1; Name = 'keep m_fLastWaterThrow on load'; Offset = $RestoreLastWaterThrow + $delta
            Old = [byte[]](0xF3, 0x0F, 0x11, 0x86, 0x74, 0x0B, 0x00, 0x00); New = $Nop8 }
        [pscustomobject]@{ Fix = 2; Name = 'il2cpp VirtualSize'; Offset = $il2cpp.Header + 8
            Old = [BitConverter]::GetBytes([uint32]$Il2cppVSizeOld); New = [BitConverter]::GetBytes([uint32]$Il2cppVSizeNew) }
        [pscustomobject]@{ Fix = 2; Name = 'il2cpp code cave'; Offset = $CaveStart + $delta
            Old = (New-Object byte[] $cave.Length); New = $cave }
        [pscustomobject]@{ Fix = 2; Name = 'MudokonSlaveThrowExit hook'; Offset = $ThrowExitSite + $delta
            Old = [byte[]](0xC6, 0x83, 0xA8, 0x0F, 0x00, 0x00, 0x00); New = $hook1 }
        [pscustomobject]@{ Fix = 2; Name = 'UpdateMudThrowQueues hook'; Offset = $QueueSite + $delta
            Old = [byte[]](0x33, 0xC9, 0x41, 0x38, 0x8E, 0xB0, 0x0F, 0x00, 0x00, 0x0F, 0x94, 0xC1); New = $hook2 }
        [pscustomobject]@{ Fix = 3; Name = 'GoToThrow flag value 0x81'; Offset = $GoToThrowFlag + $delta
            Old = [byte[]](0x01); New = [byte[]](0x81) }
        [pscustomobject]@{ Fix = 3; Name = 'gate stub in OnDrawGizmosSelected'; Offset = $DeadMethod + $delta
            Old = $deadOld; New = $deadNew }
        [pscustomobject]@{ Fix = 3; Name = 'ThrowExecute validity-gate hook'; Offset = $GateSite + $delta
            Old = [byte[]](0x38, 0x83, 0xB0, 0x0F, 0x00, 0x00, 0x75, 0x4D); New = $hook3 }
    )
}

function Test-Bytes([byte[]]$Data, [int]$Offset, [byte[]]$Expected) {
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Data[$Offset + $i] -ne $Expected[$i]) { return $false }
    }
    return $true
}

function Test-Same([byte[]]$A, [byte[]]$B) {
    return [System.Linq.Enumerable]::SequenceEqual($A, $B)
}

function Assert-GameNotRunning {
    if (Get-Process -Name soulstorm -ErrorAction SilentlyContinue) {
        throw 'Oddworld: Soulstorm is running. Close the game first.'
    }
}

function Test-BackupIsOriginal {
    return (Test-Path -LiteralPath $Backup) -and
        ((Get-FileHash -LiteralPath $Backup -Algorithm SHA256).Hash -eq $OriginalSha256)
}

function Get-Pristine([byte[]]$Current, [switch]$CreateBackup) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $OriginalSha256) {
        if ($CreateBackup -and -not (Test-Path -LiteralPath $Backup)) {
            Copy-Item -LiteralPath $Path -Destination $Backup
            Write-Host "Backup: $Backup"
        }
        return ,$Current
    }
    if (-not (Test-BackupIsOriginal)) { return $null }
    $pristine = [IO.File]::ReadAllBytes($Backup)

    if ($Current.Length -ne $pristine.Length -or -not (Test-Bytes $Current 0 ([byte[]]$pristine[0..0x1FF]))) { return $null }
    return ,$pristine
}

function New-Image([byte[]]$Pristine, [int[]]$FixSet) {
    $img = [byte[]]$Pristine.Clone()
    foreach ($p in Get-Patches $Pristine) {
        if (-not (Test-Bytes $Pristine $p.Offset $p.Old)) { throw "Original bytes for '$($p.Name)' are not what this patch expects." }
        if ($FixSet -contains $p.Fix) { [Array]::Copy($p.New, 0, $img, $p.Offset, $p.New.Length) }
    }
    return ,$img
}

if (-not (Test-Path -LiteralPath $Path)) { throw "Not found: $Path" }
Write-Host "Target: $Path"

switch ($Action) {
    'Status' {
        $data = [IO.File]::ReadAllBytes($Path)
        $pristine = Get-Pristine $data
        if (-not $pristine) { Write-Host 'State:  not the build this patch was made for (or no valid backup to compare with)'; break }
        $on = @()
        foreach ($fix in 1, 2, 3) {
            $group = @(Get-Patches $pristine | Where-Object { $_.Fix -eq $fix })
            $applied = @($group | Where-Object { Test-Bytes $data $_.Offset $_.New }).Count
            $state = if ($applied -eq $group.Count) { $on += $fix; 'applied' } elseif ($applied -eq 0) { 'not applied' } else { 'PARTLY applied' }
            Write-Host ("  fix {0}: {1}" -f $fix, $state)
        }
        $clean = Test-Same $data (New-Image $pristine $on)
        Write-Host ("State:  {0}" -f $(if ($clean) { 'clean (only the fixes listed above differ from the original)' } else { 'has other differences from the original - run Apply to rebuild it' }))
        Write-Host ("Backup: {0}" -f $(if (Test-Path -LiteralPath $Backup) { $Backup } else { '(none)' }))
    }

    'Apply' {
        Assert-GameNotRunning
        $data = [IO.File]::ReadAllBytes($Path)
        $pristine = Get-Pristine $data -CreateBackup
        if (-not $pristine) {
            throw 'GameAssembly.dll is not the build this patch was made for, or the pristine backup is missing. Nothing was changed.'
        }
        if (-not (Test-BackupIsOriginal)) { throw "Backup $Backup is missing or is not the original file. Nothing was changed." }
        $image = New-Image $pristine $Selected
        if (Test-Same $data $image) { Write-Host ("Already has exactly fix(es) {0} - nothing to do." -f ($Selected -join ', ')); break }
        [IO.File]::WriteAllBytes($Path, $image)
        if (-not (Test-Same ([IO.File]::ReadAllBytes($Path)) $image)) { throw 'Verification after write failed.' }
        Write-Host ("Done. GameAssembly.dll now has fix(es): {0}" -f ($Selected -join ', '))
    }

    'Restore' {
        Assert-GameNotRunning
        if (-not (Test-BackupIsOriginal)) { throw "Backup $Backup is missing or does not match the original file hash. Not restoring." }
        Copy-Item -LiteralPath $Backup -Destination $Path -Force
        Write-Host 'Original GameAssembly.dll restored.'
    }
}
