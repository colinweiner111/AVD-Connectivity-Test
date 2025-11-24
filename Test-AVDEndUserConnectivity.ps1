<#
.SYNOPSIS
    Azure Virtual Desktop End-User Connectivity Test Script
    
.DESCRIPTION
    This script tests AVD connectivity from an end-user's device perspective.
    It checks gateway endpoints, DNS resolution, network connectivity, and RDP broker availability.
    Runs continuously with configurable test intervals.
    
.PARAMETER IntervalMinutes
    Time in minutes between each connectivity test (default: 5)
    
.PARAMETER LogPath
    Path where log files will be saved (default: current directory)
    
.EXAMPLE
    .\Test-AVDEndUserConnectivity.ps1
    
.EXAMPLE
    .\Test-AVDEndUserConnectivity.ps1 -IntervalMinutes 3 -LogPath "C:\Logs"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [int]$IntervalMinutes = 5,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath = $PSScriptRoot
)

# AVD Commercial Gateway endpoints
$AVDEndpoints = @(
    'rdgateway-r0.wvd.microsoft.com',
    'rdgateway-r1.wvd.microsoft.com',
    'rdgateway-g-us-r0.wvd.microsoft.com',
    'rdgateway-g-us-r1.wvd.microsoft.com',
    'rdbroker.wvd.microsoft.com',
    'rdweb.wvd.microsoft.com'
)

# Initialize log file with timestamp per test run
$LogFile = Join-Path $LogPath "AVD-Connectivity-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARNING', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogMessage = "[$Timestamp] [$Level] $Message"
    
    # Color coding for console output
    $Color = switch ($Level) {
        'SUCCESS' { 'Green' }
        'WARNING' { 'Yellow' }
        'ERROR'   { 'Red' }
        default   { 'White' }
    }
    
    Write-Host $LogMessage -ForegroundColor $Color
    Add-Content -Path $LogFile -Value $LogMessage
}

function Test-DNSResolution {
    param([string]$Hostname)
    
    try {
        $Result = Resolve-DnsName -Name $Hostname -ErrorAction Stop
        Write-Log "DNS Resolution for $Hostname - SUCCESS (IP: $($Result[0].IPAddress))" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "DNS Resolution for $Hostname - FAILED: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Test-NetworkConnectivity {
    param(
        [string]$Hostname,
        [int]$Port = 443
    )
    
    try {
        $TcpClient = New-Object System.Net.Sockets.TcpClient
        $Connect = $TcpClient.BeginConnect($Hostname, $Port, $null, $null)
        $Wait = $Connect.AsyncWaitHandle.WaitOne(3000, $false)
        
        if (!$Wait) {
            $TcpClient.Close()
            Write-Log "TCP Connection to ${Hostname}:${Port} - TIMEOUT" -Level WARNING
            return $false
        }
        else {
            try {
                $TcpClient.EndConnect($Connect)
                $TcpClient.Close()
                Write-Log "TCP Connection to ${Hostname}:${Port} - SUCCESS" -Level SUCCESS
                return $true
            }
            catch {
                Write-Log "TCP Connection to ${Hostname}:${Port} - FAILED: $($_.Exception.Message)" -Level ERROR
                return $false
            }
        }
    }
    catch {
        Write-Log "TCP Connection to ${Hostname}:${Port} - ERROR: $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

function Test-HTTPSEndpoint {
    param([string]$Url)
    
    try {
        $Response = Invoke-WebRequest -Uri "https://$Url" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Write-Log "HTTPS Endpoint $Url - SUCCESS (Status: $($Response.StatusCode))" -Level SUCCESS
        return $true
    }
    catch {
        $StatusCode = $_.Exception.Response.StatusCode.Value__
        if ($StatusCode -eq 401 -or $StatusCode -eq 403) {
            # Authentication required is actually a good sign - endpoint is reachable
            Write-Log "HTTPS Endpoint $Url - REACHABLE (Auth Required: $StatusCode)" -Level SUCCESS
            return $true
        }
        else {
            Write-Log "HTTPS Endpoint $Url - FAILED: $($_.Exception.Message)" -Level WARNING
            return $false
        }
    }
}

function Get-NetworkLatency {
    param([string]$Hostname)
    
    try {
        $PingResult = Test-Connection -ComputerName $Hostname -Count 4 -ErrorAction Stop
        $AvgLatency = ($PingResult | Measure-Object -Property Latency -Average).Average
        
        if ($AvgLatency -lt 50) {
            Write-Log "Network Latency to $Hostname - EXCELLENT (${AvgLatency}ms)" -Level SUCCESS
        }
        elseif ($AvgLatency -lt 100) {
            Write-Log "Network Latency to $Hostname - GOOD (${AvgLatency}ms)" -Level SUCCESS
        }
        elseif ($AvgLatency -lt 200) {
            Write-Log "Network Latency to $Hostname - FAIR (${AvgLatency}ms)" -Level WARNING
        }
        else {
            Write-Log "Network Latency to $Hostname - POOR (${AvgLatency}ms)" -Level WARNING
        }
        
        return $AvgLatency
    }
    catch {
        Write-Log "Network Latency to $Hostname - FAILED: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Test-PacketLoss {
    param(
        [string]$Hostname,
        [int]$Count = 20
    )
    
    try {
        $PingResults = Test-Connection -ComputerName $Hostname -Count $Count -ErrorAction SilentlyContinue
        $Successful = ($PingResults | Measure-Object).Count
        $Lost = $Count - $Successful
        $LossPercentage = [math]::Round(($Lost / $Count) * 100, 2)
        
        if ($LossPercentage -eq 0) {
            Write-Log "Packet Loss to $Hostname - NONE (0% loss, $Successful/$Count packets)" -Level SUCCESS
        }
        elseif ($LossPercentage -lt 5) {
            Write-Log "Packet Loss to $Hostname - MINIMAL ($LossPercentage% loss, $Successful/$Count packets)" -Level SUCCESS
        }
        elseif ($LossPercentage -lt 15) {
            Write-Log "Packet Loss to $Hostname - MODERATE ($LossPercentage% loss, $Successful/$Count packets)" -Level WARNING
        }
        else {
            Write-Log "Packet Loss to $Hostname - HIGH ($LossPercentage% loss, $Successful/$Count packets)" -Level ERROR
        }
        
        return @{
            Total = $Count
            Successful = $Successful
            Lost = $Lost
            LossPercentage = $LossPercentage
        }
    }
    catch {
        Write-Log "Packet Loss Test to $Hostname - FAILED: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Test-NetworkJitter {
    param(
        [string]$Hostname,
        [int]$Count = 20
    )
    
    try {
        $PingResults = Test-Connection -ComputerName $Hostname -Count $Count -ErrorAction Stop
        $Latencies = $PingResults | Select-Object -ExpandProperty Latency
        
        $AvgLatency = ($Latencies | Measure-Object -Average).Average
        $MinLatency = ($Latencies | Measure-Object -Minimum).Minimum
        $MaxLatency = ($Latencies | Measure-Object -Maximum).Maximum
        
        # Calculate jitter (standard deviation)
        $Sum = 0
        foreach ($Latency in $Latencies) {
            $Sum += [math]::Pow($Latency - $AvgLatency, 2)
        }
        $Jitter = [math]::Sqrt($Sum / $Latencies.Count)
        
        if ($Jitter -lt 5) {
            Write-Log "Network Jitter to $Hostname - EXCELLENT (${Jitter}ms std dev, Min: ${MinLatency}ms, Max: ${MaxLatency}ms, Avg: ${AvgLatency}ms)" -Level SUCCESS
        }
        elseif ($Jitter -lt 15) {
            Write-Log "Network Jitter to $Hostname - ACCEPTABLE (${Jitter}ms std dev, Min: ${MinLatency}ms, Max: ${MaxLatency}ms, Avg: ${AvgLatency}ms)" -Level SUCCESS
        }
        elseif ($Jitter -lt 30) {
            Write-Log "Network Jitter to $Hostname - MODERATE (${Jitter}ms std dev, Min: ${MinLatency}ms, Max: ${MaxLatency}ms, Avg: ${AvgLatency}ms)" -Level WARNING
        }
        else {
            Write-Log "Network Jitter to $Hostname - HIGH (${Jitter}ms std dev, Min: ${MinLatency}ms, Max: ${MaxLatency}ms, Avg: ${AvgLatency}ms)" -Level ERROR
        }
        
        return @{
            Jitter = $Jitter
            Average = $AvgLatency
            Minimum = $MinLatency
            Maximum = $MaxLatency
        }
    }
    catch {
        Write-Log "Jitter Test to $Hostname - FAILED: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Test-ConnectionStability {
    param(
        [string]$Hostname,
        [int]$Port = 443,
        [int]$Iterations = 10
    )
    
    $Successful = 0
    $Failed = 0
    $Timeouts = 0
    $ConnectionTimes = @()
    
    for ($i = 1; $i -le $Iterations; $i++) {
        try {
            $StartTime = Get-Date
            $TcpClient = New-Object System.Net.Sockets.TcpClient
            $Connect = $TcpClient.BeginConnect($Hostname, $Port, $null, $null)
            $Wait = $Connect.AsyncWaitHandle.WaitOne(2000, $false)
            
            if (!$Wait) {
                $Timeouts++
                $TcpClient.Close()
            }
            else {
                try {
                    $TcpClient.EndConnect($Connect)
                    $EndTime = Get-Date
                    $ConnectionTime = ($EndTime - $StartTime).TotalMilliseconds
                    $ConnectionTimes += $ConnectionTime
                    $Successful++
                    $TcpClient.Close()
                }
                catch {
                    $Failed++
                }
            }
        }
        catch {
            $Failed++
        }
        
        Start-Sleep -Milliseconds 200
    }
    
    $SuccessRate = [math]::Round(($Successful / $Iterations) * 100, 2)
    
    if ($SuccessRate -eq 100) {
        Write-Log "Connection Stability to ${Hostname}:${Port} - EXCELLENT ($SuccessRate% success, $Successful/$Iterations connections)" -Level SUCCESS
    }
    elseif ($SuccessRate -ge 95) {
        Write-Log "Connection Stability to ${Hostname}:${Port} - GOOD ($SuccessRate% success, $Successful/$Iterations connections, Timeouts: $Timeouts, Resets: $Failed)" -Level SUCCESS
    }
    elseif ($SuccessRate -ge 80) {
        Write-Log "Connection Stability to ${Hostname}:${Port} - FAIR ($SuccessRate% success, $Successful/$Iterations connections, Timeouts: $Timeouts, Resets: $Failed)" -Level WARNING
    }
    else {
        Write-Log "Connection Stability to ${Hostname}:${Port} - POOR ($SuccessRate% success, $Successful/$Iterations connections, Timeouts: $Timeouts, Resets: $Failed)" -Level ERROR
    }
    
    if ($ConnectionTimes.Count -gt 0) {
        $AvgConnTime = [math]::Round(($ConnectionTimes | Measure-Object -Average).Average, 2)
        Write-Log "  Average TCP Connection Time: ${AvgConnTime}ms" -Level INFO
    }
    
    return @{
        Successful = $Successful
        Failed = $Failed
        Timeouts = $Timeouts
        SuccessRate = $SuccessRate
        AvgConnectionTime = if ($ConnectionTimes.Count -gt 0) { $AvgConnTime } else { $null }
    }
}

function Test-UDPConnectivity {
    param(
        [string]$Hostname,
        [int[]]$Ports = @(3478, 3479, 3390)
    )
    
    Write-Log "Testing UDP connectivity for RDP Shortpath..." -Level INFO
    
    foreach ($Port in $Ports) {
        try {
            $UdpClient = New-Object System.Net.Sockets.UdpClient
            $UdpClient.Client.ReceiveTimeout = 2000
            $UdpClient.Connect($Hostname, $Port)
            
            # Send a test packet
            $Bytes = [System.Text.Encoding]::ASCII.GetBytes("TEST")
            [void]$UdpClient.Send($Bytes, $Bytes.Length)
            
            # Try to receive (will likely timeout, but connection attempt is what matters)
            try {
                $RemoteEP = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
                $ReceivedBytes = $UdpClient.Receive([ref]$RemoteEP)
                Write-Log "UDP Port $Port to $Hostname - OPEN and RESPONSIVE" -Level SUCCESS
            }
            catch {
                # Timeout is expected, but if we got here, UDP packet was sent successfully
                Write-Log "UDP Port $Port to $Hostname - LIKELY OPEN (sent successfully, no response expected)" -Level SUCCESS
            }
            
            $UdpClient.Close()
        }
        catch {
            Write-Log "UDP Port $Port to $Hostname - BLOCKED or UNREACHABLE" -Level WARNING
            Write-Log "  WARNING: UDP is required for RDP Shortpath. Fallback to TCP may cause performance issues." -Level WARNING
        }
    }
}

function Test-SustainedConnection {
    param(
        [string]$Hostname,
        [int]$Port = 443,
        [int]$DurationSeconds = 30
    )
    
    Write-Log "Testing sustained connection to ${Hostname}:${Port} for $DurationSeconds seconds..." -Level INFO
    
    $Disconnects = 0
    $StartTime = Get-Date
    $TestInterval = 2  # Check every 2 seconds
    $Iterations = [math]::Floor($DurationSeconds / $TestInterval)
    
    try {
        for ($i = 1; $i -le $Iterations; $i++) {
            try {
                $TcpClient = New-Object System.Net.Sockets.TcpClient
                $Connect = $TcpClient.BeginConnect($Hostname, $Port, $null, $null)
                $Wait = $Connect.AsyncWaitHandle.WaitOne(3000, $false)
                
                if (!$Wait) {
                    $Disconnects++
                    Write-Log "  Iteration $i/$Iterations - CONNECTION TIMEOUT" -Level WARNING
                }
                else {
                    try {
                        $TcpClient.EndConnect($Connect)
                        # Keep connection open briefly
                        Start-Sleep -Milliseconds 500
                        $TcpClient.Close()
                    }
                    catch {
                        $Disconnects++
                        Write-Log "  Iteration $i/$Iterations - CONNECTION RESET" -Level ERROR
                    }
                }
            }
            catch {
                $Disconnects++
                Write-Log "  Iteration $i/$Iterations - CONNECTION FAILED" -Level ERROR
            }
            
            Start-Sleep -Seconds $TestInterval
        }
        
        $EndTime = Get-Date
        $ActualDuration = ($EndTime - $StartTime).TotalSeconds
        $DisconnectRate = [math]::Round(($Disconnects / $Iterations) * 100, 2)
        
        if ($DisconnectRate -eq 0) {
            Write-Log "Sustained Connection Test - EXCELLENT (0% disconnects over ${ActualDuration}s)" -Level SUCCESS
        }
        elseif ($DisconnectRate -lt 5) {
            Write-Log "Sustained Connection Test - GOOD (${DisconnectRate}% disconnects, $Disconnects/$Iterations over ${ActualDuration}s)" -Level SUCCESS
        }
        elseif ($DisconnectRate -lt 15) {
            Write-Log "Sustained Connection Test - FAIR (${DisconnectRate}% disconnects, $Disconnects/$Iterations over ${ActualDuration}s)" -Level WARNING
        }
        else {
            Write-Log "Sustained Connection Test - POOR (${DisconnectRate}% disconnects, $Disconnects/$Iterations over ${ActualDuration}s)" -Level ERROR
            Write-Log "  HIGH DISCONNECT RATE - Likely cause of AVD session drops" -Level ERROR
        }
        
        return @{
            Disconnects = $Disconnects
            Iterations = $Iterations
            DisconnectRate = $DisconnectRate
            Duration = $ActualDuration
        }
    }
    catch {
        Write-Log "Sustained Connection Test - FAILED: $($_.Exception.Message)" -Level ERROR
        return $null
    }
}

function Test-TimeSync {
    Write-Log "Testing time synchronization..." -Level INFO
    
    try {
        # Get local time
        $LocalTime = Get-Date
        
        # Get time from a reliable internet source
        try {
            $WebResponse = Invoke-WebRequest -Uri 'http://worldtimeapi.org/api/ip' -UseBasicParsing -TimeoutSec 5
            $TimeData = $WebResponse.Content | ConvertFrom-Json
            $InternetTime = [DateTime]::Parse($TimeData.datetime)
            
            $TimeDiff = [math]::Abs(($LocalTime - $InternetTime).TotalSeconds)
            
            if ($TimeDiff -lt 5) {
                Write-Log "Time Synchronization - EXCELLENT (${TimeDiff}s difference)" -Level SUCCESS
            }
            elseif ($TimeDiff -lt 30) {
                Write-Log "Time Synchronization - ACCEPTABLE (${TimeDiff}s difference)" -Level SUCCESS
            }
            elseif ($TimeDiff -lt 300) {
                Write-Log "Time Synchronization - DRIFT DETECTED (${TimeDiff}s difference)" -Level WARNING
                Write-Log "  WARNING: Time drift can cause authentication issues in AVD" -Level WARNING
            }
            else {
                Write-Log "Time Synchronization - SIGNIFICANT DRIFT (${TimeDiff}s difference)" -Level ERROR
                Write-Log "  ERROR: Large time drift will cause AVD authentication failures" -Level ERROR
            }
        }
        catch {
            # Fallback: Check Windows Time Service status
            $W32TimeService = Get-Service -Name w32time -ErrorAction SilentlyContinue
            if ($W32TimeService) {
                if ($W32TimeService.Status -eq 'Running') {
                    Write-Log "Time Synchronization - Windows Time Service is running" -Level SUCCESS
                }
                else {
                    Write-Log "Time Synchronization - WARNING: Windows Time Service is not running" -Level WARNING
                }
            }
        }
        
        # Check last successful sync
        try {
            $W32TimeStatus = w32tm /query /status 2>$null
            if ($W32TimeStatus) {
                $LastSync = $W32TimeStatus | Select-String 'Last Successful Sync Time:'
                if ($LastSync) {
                    Write-Log "  $($LastSync -replace '\s+', ' ')" -Level INFO
                }
            }
        }
        catch {
            # Silent fail - not critical
        }
    }
    catch {
        Write-Log "Time Synchronization Test - FAILED: $($_.Exception.Message)" -Level WARNING
    }
}

function Test-DNSCacheTTL {
    param([string]$Hostname)
    
    Write-Log "Testing DNS cache and TTL for $Hostname..." -Level INFO
    
    try {
        # Check DNS cache
        $CacheEntry = Get-DnsClientCache -Name $Hostname -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($CacheEntry) {
            $TTL = $CacheEntry.TimeToLive
            Write-Log "  DNS Cache Entry Found - TTL: $TTL seconds" -Level INFO
            
            if ($TTL -lt 60) {
                Write-Log "  WARNING: Low TTL may cause frequent DNS lookups" -Level WARNING
            }
        }
        else {
            Write-Log "  No DNS cache entry found (will be resolved fresh)" -Level INFO
        }
        
        # Perform fresh DNS lookup and measure time
        $StartTime = Get-Date
        $DnsResult = Resolve-DnsName -Name $Hostname -Type A -ErrorAction Stop
        $EndTime = Get-Date
        $LookupTime = ($EndTime - $StartTime).TotalMilliseconds
        
        if ($LookupTime -lt 50) {
            Write-Log "  DNS Lookup Time - FAST (${LookupTime}ms)" -Level SUCCESS
        }
        elseif ($LookupTime -lt 200) {
            Write-Log "  DNS Lookup Time - ACCEPTABLE (${LookupTime}ms)" -Level SUCCESS
        }
        else {
            Write-Log "  DNS Lookup Time - SLOW (${LookupTime}ms)" -Level WARNING
            Write-Log "  WARNING: Slow DNS can cause connection delays" -Level WARNING
        }
        
        # Check if multiple IPs returned (for load balancing)
        $IPCount = ($DnsResult | Where-Object { $_.Type -eq 'A' } | Measure-Object).Count
        if ($IPCount -gt 1) {
            Write-Log "  DNS returned $IPCount IP addresses (load balanced)" -Level INFO
        }
        
    }
    catch {
        Write-Log "DNS Cache/TTL Test - FAILED: $($_.Exception.Message)" -Level WARNING
    }
}

function Test-ConnectionBrokerStress {
    param(
        [string]$BrokerHostname = 'rdbroker.wvd.microsoft.com',
        [int]$RequestCount = 10
    )
    
    Write-Log "Testing Connection Broker stress ($RequestCount rapid requests)..." -Level INFO
    
    $Successful = 0
    $Failed = 0
    $Timeouts = 0
    $ResponseTimes = @()
    
    for ($i = 1; $i -le $RequestCount; $i++) {
        try {
            $StartTime = Get-Date
            
            $Response = Invoke-WebRequest -Uri "https://$BrokerHostname" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            
            $EndTime = Get-Date
            $ResponseTime = ($EndTime - $StartTime).TotalMilliseconds
            $ResponseTimes += $ResponseTime
            $Successful++
        }
        catch {
            if ($_.Exception.Message -match 'timeout') {
                $Timeouts++
            }
            elseif ($_.Exception.Response.StatusCode.Value__ -in @(401, 403, 405)) {
                # Auth required or method not allowed = broker is responding
                $EndTime = Get-Date
                $ResponseTime = ($EndTime - $StartTime).TotalMilliseconds
                $ResponseTimes += $ResponseTime
                $Successful++
            }
            else {
                $Failed++
            }
        }
        
        Start-Sleep -Milliseconds 100
    }
    
    $SuccessRate = [math]::Round(($Successful / $RequestCount) * 100, 2)
    
    if ($ResponseTimes.Count -gt 0) {
        $AvgResponseTime = [math]::Round(($ResponseTimes | Measure-Object -Average).Average, 2)
        Write-Log "  Average Response Time: ${AvgResponseTime}ms" -Level INFO
    }
    
    if ($SuccessRate -eq 100) {
        Write-Log "Connection Broker Stress Test - EXCELLENT ($SuccessRate% success, $Successful/$RequestCount requests)" -Level SUCCESS
    }
    elseif ($SuccessRate -ge 90) {
        Write-Log "Connection Broker Stress Test - GOOD ($SuccessRate% success, Timeouts: $Timeouts, Failed: $Failed)" -Level SUCCESS
    }
    elseif ($SuccessRate -ge 70) {
        Write-Log "Connection Broker Stress Test - FAIR ($SuccessRate% success, Timeouts: $Timeouts, Failed: $Failed)" -Level WARNING
    }
    else {
        Write-Log "Connection Broker Stress Test - POOR ($SuccessRate% success, Timeouts: $Timeouts, Failed: $Failed)" -Level ERROR
        Write-Log "  WARNING: Broker instability can cause AVD connection failures" -Level ERROR
    }
    
    return @{
        Successful = $Successful
        Failed = $Failed
        Timeouts = $Timeouts
        SuccessRate = $SuccessRate
        AvgResponseTime = if ($ResponseTimes.Count -gt 0) { $AvgResponseTime } else { $null }
    }
}

function Get-BackgroundNetworkActivity {
    Write-Log "Checking for background network activity..." -Level INFO
    
    try {
        # Get top network-consuming processes
        $NetStats = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | 
            Group-Object -Property OwningProcess | 
            Select-Object -First 10
        
        $ActiveProcesses = @()
        
        foreach ($Group in $NetStats) {
            try {
                $Process = Get-Process -Id $Group.Name -ErrorAction SilentlyContinue
                if ($Process) {
                    $ConnectionCount = $Group.Count
                    $ActiveProcesses += [PSCustomObject]@{
                        ProcessName = $Process.ProcessName
                        PID = $Process.Id
                        Connections = $ConnectionCount
                    }
                }
            }
            catch {
                # Skip if process no longer exists
            }
        }
        
        if ($ActiveProcesses.Count -gt 0) {
            Write-Log "  Active network processes detected:" -Level INFO
            $TopProcesses = $ActiveProcesses | Sort-Object -Property Connections -Descending | Select-Object -First 5
            foreach ($Proc in $TopProcesses) {
                Write-Log "    $($Proc.ProcessName) (PID: $($Proc.PID)) - $($Proc.Connections) connections" -Level INFO
            }
            
            # Check for known bandwidth-heavy processes
            $HeavyProcesses = @('OneDrive', 'Windows Update', 'BITS', 'Teams', 'Zoom', 'Backup')
            $DetectedHeavy = $ActiveProcesses | Where-Object { 
                $ProcessName = $_.ProcessName
                $HeavyProcesses | Where-Object { $ProcessName -match $_ }
            }
            
            if ($DetectedHeavy) {
                Write-Log "  WARNING: Bandwidth-heavy applications detected (may impact AVD performance):" -Level WARNING
                foreach ($Heavy in $DetectedHeavy) {
                    Write-Log "    - $($Heavy.ProcessName)" -Level WARNING
                }
            }
        }
        else {
            Write-Log "  No significant background network activity detected" -Level SUCCESS
        }
    }
    catch {
        Write-Log "Background Network Activity Check - FAILED: $($_.Exception.Message)" -Level WARNING
    }
}

function Test-NetworkAdapterPowerManagement {
    Write-Log "Checking network adapter power management settings..." -Level INFO
    
    try {
        $ActiveAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        
        foreach ($Adapter in $ActiveAdapters) {
            try {
                $PowerMgmt = Get-WmiObject -Class MSPower_DeviceEnable -Namespace root\wmi -ErrorAction SilentlyContinue | 
                    Where-Object { $_.InstanceName -match [regex]::Escape($Adapter.InterfaceDescription) }
                
                if ($PowerMgmt) {
                    if ($PowerMgmt.Enable) {
                        Write-Log "  $($Adapter.Name) - Power Saving ENABLED (may cause disconnects)" -Level WARNING
                        Write-Log "    RECOMMENDATION: Disable 'Allow the computer to turn off this device to save power'" -Level WARNING
                    }
                    else {
                        Write-Log "  $($Adapter.Name) - Power Saving DISABLED (optimal)" -Level SUCCESS
                    }
                }
                else {
                    Write-Log "  $($Adapter.Name) - Power management settings unavailable" -Level INFO
                }
            }
            catch {
                Write-Log "  $($Adapter.Name) - Unable to check power settings" -Level WARNING
            }
        }
    }
    catch {
        Write-Log "Network Adapter Power Management Check - FAILED: $($_.Exception.Message)" -Level WARNING
    }
}

function Test-IPv6vsIPv4 {
    param([string]$Hostname)
    
    Write-Log "Testing IPv4 vs IPv6 connectivity to $Hostname..." -Level INFO
    
    try {
        # Check IPv4
        $IPv4Result = $null
        try {
            $IPv4Lookup = Resolve-DnsName -Name $Hostname -Type A -ErrorAction Stop
            if ($IPv4Lookup) {
                $IPv4Time = Measure-Command {
                    Test-Connection -ComputerName $Hostname -Count 2 -ErrorAction SilentlyContinue
                }
                $IPv4Result = $IPv4Time.TotalMilliseconds / 2
                Write-Log "  IPv4 - Available (avg ${IPv4Result}ms)" -Level SUCCESS
            }
        }
        catch {
            Write-Log "  IPv4 - Not available or failed" -Level INFO
        }
        
        # Check IPv6
        $IPv6Result = $null
        try {
            $IPv6Lookup = Resolve-DnsName -Name $Hostname -Type AAAA -ErrorAction Stop
            if ($IPv6Lookup) {
                $IPv6Time = Measure-Command {
                    Test-Connection -ComputerName $Hostname -Count 2 -ErrorAction SilentlyContinue
                }
                $IPv6Result = $IPv6Time.TotalMilliseconds / 2
                Write-Log "  IPv6 - Available (avg ${IPv6Result}ms)" -Level SUCCESS
            }
        }
        catch {
            Write-Log "  IPv6 - Not available or failed" -Level INFO
        }
        
        # Compare and recommend
        if ($IPv4Result -and $IPv6Result) {
            if ($IPv6Result -gt ($IPv4Result * 1.5)) {
                Write-Log "  WARNING: IPv6 is significantly slower than IPv4 (may cause delays)" -Level WARNING
                Write-Log "  RECOMMENDATION: Consider disabling IPv6 or fixing IPv6 routing" -Level WARNING
            }
            elseif ($IPv4Result -gt ($IPv6Result * 1.5)) {
                Write-Log "  IPv6 is faster than IPv4 (optimal configuration)" -Level SUCCESS
            }
            else {
                Write-Log "  IPv4 and IPv6 performance is similar" -Level SUCCESS
            }
        }
        elseif ($IPv4Result -and -not $IPv6Result) {
            Write-Log "  IPv4-only connection (standard configuration)" -Level SUCCESS
        }
        elseif ($IPv6Result -and -not $IPv4Result) {
            Write-Log "  IPv6-only connection" -Level INFO
        }
        
        return @{
            IPv4Latency = $IPv4Result
            IPv6Latency = $IPv6Result
        }
    }
    catch {
        Write-Log "IPv4/IPv6 Test - FAILED: $($_.Exception.Message)" -Level WARNING
        return $null
    }
}

function Export-TestResultsToCSV {
    param(
        [hashtable]$TestResults,
        [string]$ExportPath
    )
    
    try {
        $CSVFile = Join-Path $ExportPath "AVD-Connectivity-Summary-$(Get-Date -Format 'yyyyMMdd').csv"
        
        # Create summary object for CSV
        $SummaryData = [PSCustomObject]@{
            Timestamp = $TestResults.Timestamp.ToString('yyyy-MM-dd HH:mm:ss')
            TotalTests = $TestResults.TotalTests
            PassedTests = $TestResults.PassedTests
            FailedTests = $TestResults.FailedTests
            SuccessRate = [math]::Round(($TestResults.PassedTests / $TestResults.TotalTests) * 100, 2)
        }
        
        # Add endpoint-specific metrics
        foreach ($Endpoint in $TestResults.Endpoints) {
            $EndpointName = $Endpoint.Endpoint -replace '\..*', ''  # Short name
            
            $SummaryData | Add-Member -NotePropertyName "${EndpointName}_DNS" -NotePropertyValue $Endpoint.DNS
            $SummaryData | Add-Member -NotePropertyName "${EndpointName}_TCP443" -NotePropertyValue $Endpoint.TCP443
            $SummaryData | Add-Member -NotePropertyName "${EndpointName}_HTTPS" -NotePropertyValue $Endpoint.HTTPS
            
            if ($Endpoint.Latency) {
                $SummaryData | Add-Member -NotePropertyName "${EndpointName}_Latency_ms" -NotePropertyValue ([math]::Round($Endpoint.Latency, 2))
            }
            
            if ($Endpoint.PacketLoss) {
                $SummaryData | Add-Member -NotePropertyName "${EndpointName}_PacketLoss_%" -NotePropertyValue $Endpoint.PacketLoss.LossPercentage
            }
            
            if ($Endpoint.Jitter) {
                $SummaryData | Add-Member -NotePropertyName "${EndpointName}_Jitter_ms" -NotePropertyValue ([math]::Round($Endpoint.Jitter.Jitter, 2))
            }
            
            if ($Endpoint.ConnectionStability) {
                $SummaryData | Add-Member -NotePropertyName "${EndpointName}_Stability_%" -NotePropertyValue $Endpoint.ConnectionStability.SuccessRate
            }
        }
        
        # Append to CSV (create if doesn't exist)
        if (Test-Path $CSVFile) {
            $SummaryData | Export-Csv -Path $CSVFile -Append -NoTypeInformation
        }
        else {
            $SummaryData | Export-Csv -Path $CSVFile -NoTypeInformation
        }
        
        Write-Log "Test results exported to CSV: $CSVFile" -Level SUCCESS
        return $CSVFile
    }
    catch {
        Write-Log "CSV Export - FAILED: $($_.Exception.Message)" -Level WARNING
        return $null
    }
}

function Test-MTUSize {
    param(
        [string]$Hostname,
        [int]$MaxMTU = 1500
    )
    
    try {
        # Test standard MTU sizes
        $TestSizes = @(1500, 1472, 1460, 1400, 1280)
        $OptimalMTU = $null
        
        foreach ($Size in $TestSizes) {
            $PingResult = Test-Connection -ComputerName $Hostname -BufferSize $Size -Count 1 -DontFragment -ErrorAction SilentlyContinue
            if ($PingResult) {
                $OptimalMTU = $Size + 28  # Add IP + ICMP header size
                break
            }
        }
        
        if ($OptimalMTU) {
            if ($OptimalMTU -ge 1500) {
                Write-Log "MTU Path to $Hostname - OPTIMAL ($OptimalMTU bytes, no fragmentation)" -Level SUCCESS
            }
            elseif ($OptimalMTU -ge 1280) {
                Write-Log "MTU Path to $Hostname - REDUCED ($OptimalMTU bytes, possible fragmentation)" -Level WARNING
            }
            else {
                Write-Log "MTU Path to $Hostname - LOW ($OptimalMTU bytes, fragmentation likely)" -Level ERROR
            }
        }
        else {
            Write-Log "MTU Path to $Hostname - UNABLE TO DETERMINE" -Level WARNING
        }
        
        return $OptimalMTU
    }
    catch {
        Write-Log "MTU Test to $Hostname - FAILED: $($_.Exception.Message)" -Level WARNING
        return $null
    }
}

function Get-NetworkRoute {
    param(
        [string]$Hostname,
        [int]$MaxHops = 15
    )
    
    try {
        Write-Log "Tracing route to $Hostname (max $MaxHops hops)..." -Level INFO
        
        $TraceOutput = Test-NetConnection -ComputerName $Hostname -TraceRoute -Hops $MaxHops -ErrorAction Stop
        
        if ($TraceOutput.TraceRoute) {
            $HopCount = $TraceOutput.TraceRoute.Count
            Write-Log "Route to $Hostname completed in $HopCount hops" -Level SUCCESS
            
            foreach ($i in 0..($TraceOutput.TraceRoute.Count - 1)) {
                $Hop = $TraceOutput.TraceRoute[$i]
                Write-Log "  Hop $($i + 1): $Hop" -Level INFO
            }
            
            if ($HopCount -gt 20) {
                Write-Log "  WARNING: High hop count may indicate suboptimal routing" -Level WARNING
            }
        }
        
        return $TraceOutput.TraceRoute
    }
    catch {
        Write-Log "Route Trace to $Hostname - FAILED: $($_.Exception.Message)" -Level WARNING
        return $null
    }
}

function Get-NetworkInterfaceStats {
    Write-Log "Network Interface Statistics:" -Level INFO
    
    try {
        $Adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        
        foreach ($Adapter in $Adapters) {
            $Stats = Get-NetAdapterStatistics -Name $Adapter.Name
            Write-Log "  $($Adapter.Name) ($($Adapter.InterfaceDescription)):" -Level INFO
            Write-Log "    Link Speed: $($Adapter.LinkSpeed)" -Level INFO
            Write-Log "    Bytes Sent: $([math]::Round($Stats.SentBytes / 1MB, 2)) MB" -Level INFO
            Write-Log "    Bytes Received: $([math]::Round($Stats.ReceivedBytes / 1MB, 2)) MB" -Level INFO
            
            # Check for errors
            if ($Stats.ReceivedUnicastPackets -gt 0) {
                $ErrorRate = [math]::Round(($Stats.ReceivedPacketErrors / $Stats.ReceivedUnicastPackets) * 100, 4)
                if ($ErrorRate -gt 1) {
                    Write-Log "    Packet Errors: $($Stats.ReceivedPacketErrors) ($ErrorRate% error rate)" -Level WARNING
                }
                elseif ($Stats.ReceivedPacketErrors -gt 0) {
                    Write-Log "    Packet Errors: $($Stats.ReceivedPacketErrors) ($ErrorRate% error rate)" -Level INFO
                }
            }
            
            if ($Stats.ReceivedDiscardedPackets -gt 0) {
                Write-Log "    Discarded Packets: $($Stats.ReceivedDiscardedPackets)" -Level WARNING
            }
        }
    }
    catch {
        Write-Log "Network Interface Statistics - FAILED: $($_.Exception.Message)" -Level WARNING
    }
}

function Test-RDPPort {
    param([string]$Hostname)
    
    # Test standard RDP port
    return Test-NetworkConnectivity -Hostname $Hostname -Port 3389
}

function Test-ProxySettings {
    Write-Log "Checking Internet Explorer/System Proxy Settings..." -Level INFO
    
    try {
        $ProxySettings = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        
        if ($ProxySettings.ProxyEnable -eq 1) {
            Write-Log "Proxy is ENABLED - Server: $($ProxySettings.ProxyServer)" -Level INFO
            
            # Check if AVD endpoints are in proxy bypass list
            $ProxyOverride = $ProxySettings.ProxyOverride
            if ($ProxyOverride) {
                Write-Log "Proxy Bypass List: $ProxyOverride" -Level INFO
            }
        }
        else {
            Write-Log "No proxy configured (Direct Internet Connection)" -Level INFO
        }
    }
    catch {
        Write-Log "Unable to read proxy settings: $($_.Exception.Message)" -Level WARNING
    }
}

function Get-PublicIP {
    try {
        $IP = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json' -TimeoutSec 5).ip
        Write-Log "Public IP Address: $IP" -Level INFO
        return $IP
    }
    catch {
        Write-Log "Unable to determine public IP address" -Level WARNING
        return $null
    }
}

function Get-ActiveNetworkInterface {
    try {
        # Get the adapter with the default route (active internet connection)
        $DefaultRoute = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | 
            Sort-Object -Property RouteMetric | 
            Select-Object -First 1
        
        if ($DefaultRoute) {
            $Adapter = Get-NetAdapter -InterfaceIndex $DefaultRoute.InterfaceIndex -ErrorAction Stop
            $IPConfig = Get-NetIPAddress -InterfaceIndex $Adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop
            
            # Determine connection type
            $ConnectionType = 'Unknown'
            if ($Adapter.Name -match 'Wi-Fi|Wireless|WLAN') {
                $ConnectionType = 'Wi-Fi'
            }
            elseif ($Adapter.Name -match 'Ethernet|LAN') {
                $ConnectionType = 'Ethernet'
            }
            elseif ($Adapter.InterfaceDescription -match 'VPN|Virtual|TAP') {
                $ConnectionType = 'VPN'
            }
            elseif ($Adapter.Name -match 'Ethernet') {
                $ConnectionType = 'Ethernet'
            }
            else {
                # Try to determine by media type
                if ($Adapter.MediaType -match '802.3') {
                    $ConnectionType = 'Ethernet'
                }
                elseif ($Adapter.MediaType -match '802.11|Wireless') {
                    $ConnectionType = 'Wi-Fi'
                }
            }
            
            $InterfaceInfo = @{
                Name = $Adapter.Name
                Description = $Adapter.InterfaceDescription
                Type = $ConnectionType
                Status = $Adapter.Status
                LinkSpeed = $Adapter.LinkSpeed
                IPAddress = $IPConfig.IPAddress
                MACAddress = $Adapter.MacAddress
            }
            
            # Get Wi-Fi signal strength if wireless
            if ($ConnectionType -eq 'Wi-Fi') {
                try {
                    $WifiInfo = (netsh wlan show interfaces) | Select-String 'Signal' | ForEach-Object { $_ -replace '.*:\s*', '' }
                    $InterfaceInfo.SignalStrength = $WifiInfo
                    
                    $SSID = (netsh wlan show interfaces) | Select-String 'SSID' | Where-Object { $_ -notmatch 'BSSID' } | ForEach-Object { ($_ -replace '.*:\s*', '').Trim() }
                    $InterfaceInfo.SSID = $SSID
                }
                catch {
                    $InterfaceInfo.SignalStrength = 'Unknown'
                    $InterfaceInfo.SSID = 'Unknown'
                }
            }
            
            return $InterfaceInfo
        }
        
        return $null
    }
    catch {
        Write-Log "Unable to determine active network interface: $($_.Exception.Message)" -Level WARNING
        return $null
    }
}

function Write-NetworkInterfaceInfo {
    param($InterfaceInfo)
    
    if ($InterfaceInfo) {
        Write-Log "Active Network Interface Information:" -Level INFO
        Write-Log "  Interface: $($InterfaceInfo.Name)" -Level INFO
        Write-Log "  Description: $($InterfaceInfo.Description)" -Level INFO
        Write-Log "  Connection Type: $($InterfaceInfo.Type)" -Level $(if ($InterfaceInfo.Type -eq 'Ethernet') { 'SUCCESS' } else { 'INFO' })
        Write-Log "  Link Speed: $($InterfaceInfo.LinkSpeed)" -Level INFO
        Write-Log "  IP Address: $($InterfaceInfo.IPAddress)" -Level INFO
        Write-Log "  MAC Address: $($InterfaceInfo.MACAddress)" -Level INFO
        
        if ($InterfaceInfo.Type -eq 'Wi-Fi') {
            if ($InterfaceInfo.SSID) {
                Write-Log "  Wi-Fi SSID: $($InterfaceInfo.SSID)" -Level INFO
            }
            if ($InterfaceInfo.SignalStrength) {
                Write-Log "  Wi-Fi Signal: $($InterfaceInfo.SignalStrength)" -Level INFO
            }
            Write-Log "  NOTE: Wi-Fi connections may experience more latency/jitter than Ethernet" -Level WARNING
        }
        elseif ($InterfaceInfo.Type -eq 'Ethernet') {
            Write-Log "  Recommended connection type for optimal AVD performance" -Level SUCCESS
        }
        elseif ($InterfaceInfo.Type -eq 'VPN') {
            Write-Log "  NOTE: VPN connection detected - may add latency overhead" -Level WARNING
        }
    }
}

function Test-AVDConnectivity {
    $TestResults = @{
        Timestamp = Get-Date
        TotalTests = 0
        PassedTests = 0
        FailedTests = 0
        Endpoints = @()
    }
    
    Write-Log "================================================" -Level INFO
    Write-Log "Starting AVD Connectivity Test" -Level INFO
    Write-Log "================================================" -Level INFO
    
    # Get and display active network interface
    Write-Log "" -Level INFO
    $ActiveInterface = Get-ActiveNetworkInterface
    Write-NetworkInterfaceInfo -InterfaceInfo $ActiveInterface
    
    # Get public IP
    Write-Log "" -Level INFO
    $PublicIP = Get-PublicIP
    
    # Check proxy settings
    Write-Log "" -Level INFO
    Test-ProxySettings
    
    Write-Log "" -Level INFO
    Write-Log "Testing AVD Gateway Endpoints..." -Level INFO
    Write-Log "--------------------------------" -Level INFO
    
    foreach ($Endpoint in $AVDEndpoints) {
        Write-Log "" -Level INFO
        Write-Log "Testing: $Endpoint" -Level INFO
        Write-Log "================================" -Level INFO
        
        $EndpointResult = @{
            Endpoint = $Endpoint
            DNS = $false
            TCP443 = $false
            HTTPS = $false
            Latency = $null
            PacketLoss = $null
            Jitter = $null
            ConnectionStability = $null
            MTU = $null
        }
        
        # Test DNS Resolution
        $EndpointResult.DNS = Test-DNSResolution -Hostname $Endpoint
        $TestResults.TotalTests++
        if ($EndpointResult.DNS) { $TestResults.PassedTests++ } else { $TestResults.FailedTests++ }
        
        if ($EndpointResult.DNS) {
            # Test TCP Port 443
            $EndpointResult.TCP443 = Test-NetworkConnectivity -Hostname $Endpoint -Port 443
            $TestResults.TotalTests++
            if ($EndpointResult.TCP443) { $TestResults.PassedTests++ } else { $TestResults.FailedTests++ }
            
            # Test HTTPS Endpoint
            $EndpointResult.HTTPS = Test-HTTPSEndpoint -Url $Endpoint
            $TestResults.TotalTests++
            if ($EndpointResult.HTTPS) { $TestResults.PassedTests++ } else { $TestResults.FailedTests++ }
            
            # Measure Latency
            Write-Log "" -Level INFO
            $EndpointResult.Latency = Get-NetworkLatency -Hostname $Endpoint
            
            # Test Packet Loss
            Write-Log "" -Level INFO
            $EndpointResult.PacketLoss = Test-PacketLoss -Hostname $Endpoint -Count 20
            
            # Test Network Jitter
            Write-Log "" -Level INFO
            $EndpointResult.Jitter = Test-NetworkJitter -Hostname $Endpoint -Count 20
            
            # Test Connection Stability (detect resets)
            Write-Log "" -Level INFO
            $EndpointResult.ConnectionStability = Test-ConnectionStability -Hostname $Endpoint -Port 443 -Iterations 10
            
            # Test MTU Size
            Write-Log "" -Level INFO
            $EndpointResult.MTU = Test-MTUSize -Hostname $Endpoint
        }
        
        $TestResults.Endpoints += $EndpointResult
    }
    
    # Advanced Disconnect Diagnostics
    Write-Log "" -Level INFO
    Write-Log "================================" -Level INFO
    Write-Log "Advanced Disconnect Diagnostics" -Level INFO
    Write-Log "================================" -Level INFO
    
    # Test UDP Connectivity (RDP Shortpath)
    Write-Log "" -Level INFO
    Test-UDPConnectivity -Hostname $AVDEndpoints[0]
    
    # Test Time Synchronization
    Write-Log "" -Level INFO
    Test-TimeSync
    
    # Test DNS Cache and TTL
    Write-Log "" -Level INFO
    Test-DNSCacheTTL -Hostname $AVDEndpoints[0]
    
    # Test Connection Broker Stress
    Write-Log "" -Level INFO
    Test-ConnectionBrokerStress -BrokerHostname 'rdbroker.wvd.microsoft.com' -RequestCount 10
    
    # Check Background Network Activity
    Write-Log "" -Level INFO
    Get-BackgroundNetworkActivity
    
    # Check Network Adapter Power Management
    Write-Log "" -Level INFO
    Test-NetworkAdapterPowerManagement
    
    # Test IPv4 vs IPv6
    Write-Log "" -Level INFO
    Test-IPv6vsIPv4 -Hostname $AVDEndpoints[0]
    
    # Sustained Connection Test (30 seconds)
    Write-Log "" -Level INFO
    Test-SustainedConnection -Hostname $AVDEndpoints[0] -Port 443 -DurationSeconds 30
    
    # Network Interface Statistics
    Write-Log "" -Level INFO
    Write-Log "================================" -Level INFO
    Get-NetworkInterfaceStats
    
    # Trace route to first endpoint (provides routing visibility)
    Write-Log "" -Level INFO
    Write-Log "================================" -Level INFO
    Get-NetworkRoute -Hostname $AVDEndpoints[0] -MaxHops 15
    
    # Summary
    Write-Log "" -Level INFO
    Write-Log "================================================" -Level INFO
    Write-Log "Test Summary" -Level INFO
    Write-Log "================================================" -Level INFO
    Write-Log "Total Tests: $($TestResults.TotalTests)" -Level INFO
    Write-Log "Passed: $($TestResults.PassedTests)" -Level SUCCESS
    Write-Log "Failed: $($TestResults.FailedTests)" -Level $(if ($TestResults.FailedTests -gt 0) { 'ERROR' } else { 'SUCCESS' })
    
    $SuccessRate = [math]::Round(($TestResults.PassedTests / $TestResults.TotalTests) * 100, 2)
    Write-Log "Success Rate: $SuccessRate%" -Level $(if ($SuccessRate -ge 90) { 'SUCCESS' } elseif ($SuccessRate -ge 70) { 'WARNING' } else { 'ERROR' })
    
    if ($TestResults.FailedTests -gt 0) {
        Write-Log "" -Level INFO
        Write-Log "RECOMMENDATION: Check firewall rules, proxy settings, and network connectivity" -Level WARNING
    }
    
    # Export results to CSV for trending
    Write-Log "" -Level INFO
    Export-TestResultsToCSV -TestResults $TestResults -ExportPath $LogPath
    
    return $TestResults
}

# Main execution loop
Write-Log "AVD End-User Connectivity Monitor Started" -Level INFO
Write-Log "Test Interval: $IntervalMinutes minutes" -Level INFO
Write-Log "Log File: $LogFile" -Level INFO
Write-Log "Press Ctrl+C to stop monitoring" -Level INFO
Write-Log "" -Level INFO

$TestCount = 0

try {
    while ($true) {
        $TestCount++
        Write-Log "" -Level INFO
        Write-Log "########################################" -Level INFO
        Write-Log "Test Run #$TestCount - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level INFO
        Write-Log "########################################" -Level INFO
        
        $Results = Test-AVDConnectivity
        
        Write-Log "" -Level INFO
        Write-Log "Next test in $IntervalMinutes minutes..." -Level INFO
        Write-Log "" -Level INFO
        
        Start-Sleep -Seconds ($IntervalMinutes * 60)
    }
}
catch {
    Write-Log "Script terminated: $($_.Exception.Message)" -Level INFO
}
finally {
    Write-Log "" -Level INFO
    Write-Log "AVD Connectivity Monitor Stopped - Total Tests Run: $TestCount" -Level INFO
}
