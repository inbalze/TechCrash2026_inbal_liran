$p = Start-Process -FilePath "C:\intelFPGA_lite\17.1\quartus\bin64\quartus_sh.exe" -ArgumentList "--flow compile fp8_adder" -NoNewWindow -PassThru
Write-Host "Started Quartus compile with Process ID: $($p.Id)"
$prevLog = ""
while (-not $p.HasExited) {
    Start-Sleep -Seconds 30
    if (Test-Path fp8_adder.flow.rpt) {
        $lines = Get-Content fp8_adder.flow.rpt -Tail 30
        $running = "Unknown"
        if ($lines -match "quartus_sta") { $running = "quartus_sta (Timing Analyzer)" }
        elseif ($lines -match "quartus_asm") { $running = "quartus_asm (Assembler)" }
        elseif ($lines -match "quartus_fit") { $running = "quartus_fit (Fitter)" }
        elseif ($lines -match "quartus_map") { $running = "quartus_map (Synthesis)" }
        
        $currentLog = "STATUS UPDATE: Currently running/latest module is: $running"
        if ($currentLog -ne $prevLog) {
            Write-Host $currentLog
            $prevLog = $currentLog
        }
    } else {
        Write-Host "STATUS UPDATE: Waiting for flow report..."
    }
}
Write-Host "Quartus compile finished with exit code: $($p.ExitCode)"
if (Test-Path fp8_adder.sta.summary) {
    $summary = Get-Content fp8_adder.sta.summary
    $found = $false
    for ($i=0; $i -lt $summary.Length; $i++) {
        if ($summary[$i] -match "Setup .*pll1\|clk") {
            Write-Host "FINAL TIMING RESULTS: $($summary[$i])"
            Write-Host "$($summary[$i+1])"
            $found = $true
            break
        }
    }
    if (-not $found) {
        Write-Host "Could not find PLL clock in timing summary."
    }
}
