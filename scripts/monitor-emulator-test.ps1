param([string]$Device = 'emulator-5554', [string]$Log = 'emulator-tests.log', [int]$TimeoutSeconds = 600)
$ErrorActionPreference = 'Stop'
$adbPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if ((& $adbPath -s $Device shell getprop ro.kernel.qemu).Trim() -ne '1') {
    throw 'Screen-off/doze checks only run on an Android emulator.'
}
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$asleep = $false
Write-Output "Watching emulator test markers in $Log"
try {
    while ((Get-Date) -lt $deadline) {
        [string]$contents = if (Test-Path -LiteralPath $Log) { Get-Content -LiteralPath $Log -Raw } else { '' }
        if (!$asleep -and $contents -match 'SCREEN_OFF_TEST_FINISHED') {
            throw 'The test already finished. Clear the log and start this harness before the test.'
        }
        if (!$asleep -and $contents -match 'SCREEN_OFF_TEST_READY') {
            & $adbPath -s $Device shell pm grant com.example.electrowave_mobile android.permission.POST_NOTIFICATIONS
            & $adbPath -s $Device shell dumpsys battery unplug
            & $adbPath -s $Device shell input keyevent 223
            & $adbPath -s $Device shell dumpsys deviceidle force-idle
            $asleep = $true
            Write-Output "$(Get-Date -Format o) Emulator screen off; forced doze enabled."
        }
        if ($asleep -and $contents -match 'SCREEN_OFF_TEST_FINISHED|ORIGINAL_TEST_FAILURE') { break }
        Start-Sleep -Seconds 1
    }
} finally {
    if ($asleep) {
        & $adbPath -s $Device shell dumpsys deviceidle unforce
        & $adbPath -s $Device shell dumpsys battery reset
        & $adbPath -s $Device shell input keyevent 224
        & $adbPath -s $Device shell wm dismiss-keyguard
        Write-Output "$(Get-Date -Format o) Emulator power state restored."
    }
}
