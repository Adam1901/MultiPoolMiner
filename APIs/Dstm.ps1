﻿using module ..\Include.psm1

class Dstm : Miner {
    [PSCustomObject]GetMinerData ([Bool]$Safe = $false) {
        $MinerData = ([Miner]$this).GetMinerData($Safe)

        if ($this.GetStatus() -ne [MinerStatus]::Running) {return $MinerData}

        $Server = "localhost"
        $Timeout = 10 #seconds

        $Delta = 0.05
        $Interval = 5
        $HashRates = @()

        $Request = @{id = 1; method = "getstat"} | ConvertTo-Json -Compress

        do {
            $HashRates += $HashRate = [PSCustomObject]@{}

            try {
                $Response = Invoke-TcpRequest $Server $this.Port $Request $Timeout -ErrorAction Stop
                $Data = $Response | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                Write-Log -Level Error "Failed to connect to miner ($($this.Name)). "
                break
            }

            $HashRate_Name = [String]$this.Algorithm[0]
            $HashRate_Value = [Double]($Data.result.sol_ps | Measure-Object -Sum).Sum
            if (-not $HashRate_Value) {$HashRate_Value = [Double]($Data.result.speed_sps | Measure-Object -Sum).Sum} #ewbf fix

            $HashRate | Where-Object {$HashRate_Name} | Add-Member @{$HashRate_Name = [Int64]$HashRate_Value}

            $this.Algorithm | Where-Object {-not $HashRate.$_} | ForEach-Object {break}

            if (-not $Safe) {break}

            $HashRate_Value = [Double]($Data.result.avg_sol_ps | Measure-Object -Sum).Sum

            if ($HashRate_Value) {
                $HashRates += $HashRate = [PSCustomObject]@{}

                $HashRate | Where-Object {$HashRate_Name} | Add-Member @{$HashRate_Name = [Int64]$HashRate_Value}

                $this.Algorithm | Where-Object {-not $HashRate.$_} | ForEach-Object {break}
            }

            Start-Sleep $Interval
        } while ($HashRates.Count -lt 6)

        $HashRate = [PSCustomObject]@{}
        $this.Algorithm | ForEach-Object {$HashRate | Add-Member @{$_ = [Int64]($HashRates.$_ | Measure-Object -Maximum -Minimum -Average | Where-Object {$_.Maximum - $_.Minimum -le $_.Average * $Delta}).Maximum}}
        $this.Algorithm | Where-Object {-not $HashRate.$_} | Select-Object -First 1 | ForEach-Object {$this.Algorithm | ForEach-Object {$HashRate.$_ = [Int64]0}}

        $MinerData | Add-Member HashRate $HashRate -Force
        return $MinerData
    }
}