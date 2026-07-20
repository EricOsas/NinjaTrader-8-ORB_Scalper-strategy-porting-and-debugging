$startDate = [DateTime]"2010-01-01"
$endDate = [DateTime]::Now

$csvPath = "C:\Users\Administrator\Documents\NinjaTrader 8\bin\Custom\Strategies\ORB_NT\historical_calendar.csv"
$stream = [System.IO.StreamWriter]::new($csvPath)
$stream.WriteLine("Date,Time_ET,Currency,Impact,Title")

# Helpers
function Get-NextWeekday($date) {
    while ($date.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $date.DayOfWeek -eq [System.DayOfWeek]::Sunday) {
        $date = $date.AddDays(1)
    }
    return $date
}

function Get-PreviousWeekday($date) {
    while ($date.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $date.DayOfWeek -eq [System.DayOfWeek]::Sunday) {
        $date = $date.AddDays(-1)
    }
    return $date
}

function Write-Event($date, $timeStr, $title) {
    $dateStr = $date.ToString("yyyy-MM-dd")
    $stream.WriteLine("$dateStr,$timeStr,USD,High,$title")
}

for ($year = $startDate.Year; $year -le $endDate.Year; $year++) {
    for ($month = 1; $month -le 12; $month++) {
        # Break if we are past the end date
        if ($year -eq $endDate.Year -and $month -gt $endDate.Month) { break }
        
        # 1. Non-Farm Payrolls (First Friday)
        $nfpDate = [DateTime]::new($year, $month, 1)
        while ($nfpDate.DayOfWeek -ne [System.DayOfWeek]::Friday) {
            $nfpDate = $nfpDate.AddDays(1)
        }
        if ($nfpDate -le $endDate) {
            Write-Event $nfpDate "08:30" "Non-Farm Employment Change"
        }

        # 2. CPI (Approx mid-month, say 13th)
        $cpiDate = Get-NextWeekday([DateTime]::new($year, $month, 13))
        if ($cpiDate -le $endDate) {
            Write-Event $cpiDate "08:30" "CPI m/m"
            Write-Event $cpiDate "08:30" "Core CPI m/m"
        }

        # 3. Core PCE (Approx end of month, say 28th)
        $pceDate = Get-PreviousWeekday([DateTime]::new($year, $month, 28))
        if ($pceDate -le $endDate) {
            Write-Event $pceDate "08:30" "Core PCE Price Index m/m"
        }

        # 4. GDP (Quarterly: Jan, Apr, Jul, Oct - around 28th)
        if ($month -in @(1, 4, 7, 10)) {
            $gdpDate = Get-PreviousWeekday([DateTime]::new($year, $month, 28))
            if ($gdpDate -le $endDate) {
                Write-Event $gdpDate "08:30" "Advance GDP q/q"
            }
        }

        # 5. FOMC (Approx 8 times a year: Jan, Mar, May, Jun, Jul, Sep, Nov, Dec)
        if ($month -in @(1, 3, 5, 6, 7, 9, 11, 12)) {
            # Usually Wednesday in the middle/late of the month (approx 18th)
            $fomcDate = [DateTime]::new($year, $month, 18)
            while ($fomcDate.DayOfWeek -ne [System.DayOfWeek]::Wednesday) {
                $fomcDate = $fomcDate.AddDays(1)
            }
            if ($fomcDate -le $endDate) {
                Write-Event $fomcDate "14:00" "FOMC Economic Projections"
                Write-Event $fomcDate "14:00" "FOMC Statement"
                Write-Event $fomcDate "14:00" "Federal Funds Rate"
                Write-Event $fomcDate "14:30" "FOMC Press Conference"
            }
        }
    }
}

# 6. Initial Jobless Claims (Every Thursday)
$claimsDate = $startDate
while ($claimsDate.DayOfWeek -ne [System.DayOfWeek]::Thursday) {
    $claimsDate = $claimsDate.AddDays(1)
}
while ($claimsDate -le $endDate) {
    Write-Event $claimsDate "08:30" "Unemployment Claims"
    $claimsDate = $claimsDate.AddDays(7)
}

$stream.Close()
$stream.Dispose()
Write-Host "historical_calendar.csv generated."
