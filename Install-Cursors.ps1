param(
    [ValidateSet('Install','Restore','Validate')]
    [string]$Action = 'Validate'
)
$ErrorActionPreference = 'Stop'
$registryPath = 'Control Panel\Cursors'
$installRoot = Join-Path $env:LOCALAPPDATA 'GrokBot-CursorStudy-v2'
$snapshotPath = Join-Path $installRoot 'previous-pointers.clixml'
$roles = 'Arrow','Help','AppStarting','Wait','Crosshair','IBeam','NWPen','No','SizeNS','SizeWE',
         'SizeNWSE','SizeNESW','SizeAll','UpArrow','Hand','Pin','Person'
$tracked = @('', 'Scheme Source') + $roles

function Save-Values($Key, [string[]]$Names) {
    $present = $Key.GetValueNames()
    foreach ($name in $Names) {
        if ($present -contains $name) {
            [pscustomobject]@{
                Name = $name; Present = $true; Kind = $Key.GetValueKind($name).ToString()
                Data = $Key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            }
        } else {
            [pscustomobject]@{Name = $name; Present = $false}
        }
    }
}

function Restore-Values($Key, $Entries) {
    foreach ($entry in $Entries) {
        if ($entry.Present) {
            $Key.SetValue([string]$entry.Name,$entry.Data,[Microsoft.Win32.RegistryValueKind]$entry.Kind)
        } else {
            $Key.DeleteValue([string]$entry.Name,$false)
        }
    }
}

function Reload-Pointers {
    if (-not [GrokBotCursorV2.Native]::SystemParametersInfo(0x57,0,[IntPtr]::Zero,0)) {
        throw 'Windows could not reload the cursor settings.'
    }
}

$paths = @{}
if ($Action -ne 'Restore') {
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'Scheme.json') | ConvertFrom-Json
    if ($manifest.Theme -notin 'Pure','Soft-Pointer') { throw 'Unknown theme.' }
    $schemeName = "Grok Bot Study v4.1 ($($manifest.Theme))"
    $assets = Join-Path (Join-Path $installRoot 'v4.1') $manifest.Theme
    $expected = $roles
    $provided = @($manifest.Roles.PSObject.Properties.Name)
    if ($provided.Count -ne $expected.Count -or (Compare-Object $expected $provided)) { throw 'Invalid role list.' }
    foreach ($role in $expected) {
        $file = $manifest.Roles.$role
        if ($file -cnotmatch '^Motions/[a-z-]+\.ani$') { throw "Invalid cursor path: $file" }
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) { throw "Missing file: $file" }
        $paths[$role] = Join-Path $assets $file
    }
    if ($Action -eq 'Validate') { Write-Host "Validated $($paths.Count) mapped roles."; return }
    if ($assets.Contains(',')) { throw 'Windows scheme paths cannot contain a comma.' }
} elseif (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
    Write-Host 'There are no saved pointer settings to restore.'
    return
}

Add-Type -Namespace GrokBotCursorV2 -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
[return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
public static extern bool SystemParametersInfo(uint action, uint param, System.IntPtr data, uint flags);
'@
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($registryPath,$true)
if (-not $key) { throw 'Could not open pointer settings.' }
$before = @(Save-Values $key $tracked)
$schemes = $null
$oldScheme = $null
$newSnapshot = $false
try {
    $previous = $before
    if (Test-Path -LiteralPath $snapshotPath -PathType Leaf) {
        $previous = @(Import-Clixml -LiteralPath $snapshotPath)
        $previousNames = @($previous | ForEach-Object { $_.Name })
        if ($previousNames.Count -ne $tracked.Count -or (Compare-Object $tracked $previousNames)) { throw 'Invalid backup.' }
    }
    if ($Action -eq 'Restore') {
        Restore-Values $key $previous
        Reload-Pointers
        Remove-Item -LiteralPath $snapshotPath
        Write-Host 'Restored the previous pointer configuration.'
    } else {
        $schemePaths = foreach ($role in $roles) { $paths[$role] }
        [void][IO.Directory]::CreateDirectory($assets)
        foreach ($dir in 'Motions','Shapes') {
            $target = Join-Path $assets $dir
            [void][IO.Directory]::CreateDirectory($target)
            Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $dir) -File | Copy-Item -Destination $target -Force
        }
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Normal-Still.cur') -Destination $assets -Force
        if (-not (Test-Path -LiteralPath $snapshotPath)) {
            $before | Export-Clixml -LiteralPath "$snapshotPath.tmp"
            Move-Item -LiteralPath "$snapshotPath.tmp" -Destination $snapshotPath
            $newSnapshot = $true
        }
        $schemes = $key.CreateSubKey('Schemes')
        $oldScheme = @(Save-Values $schemes @($schemeName))
        $schemes.SetValue($schemeName,($schemePaths -join ','),'String')
        Restore-Values $key $previous
        foreach ($role in $paths.Keys) { $key.SetValue($role,$paths[$role],'String') }
        $key.SetValue('',$schemeName,'String')
        $key.SetValue('Scheme Source',1,'DWord')
        Reload-Pointers
        Write-Host "Applied $schemeName. Use option 2 to restore your previous pointers."
    }
} catch {
    $failure = $_
    try {
        if ($schemes -and $oldScheme) { Restore-Values $schemes $oldScheme }
        Restore-Values $key $before
        Reload-Pointers
        if ($newSnapshot) { Remove-Item -LiteralPath $snapshotPath }
    } catch {
        Write-Warning "Automatic rollback could not finish: $($_.Exception.Message)"
    }
    throw $failure
} finally {
    if ($schemes) { $schemes.Dispose() }
    $key.Dispose()
}
