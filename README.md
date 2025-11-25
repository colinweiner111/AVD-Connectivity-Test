# Azure Virtual Desktop Connectivity Test Script

PowerShell script for diagnosing Azure Virtual Desktop (AVD) connectivity issues and disconnects from end-user devices. Performs extensive network testing without requiring Azure credentials.

## Features

### 🔍 Network Interface Detection
- Identifies active connection type (Wi-Fi, Ethernet, VPN)
- Displays link speed, IP/MAC addresses
- Shows Wi-Fi SSID and signal strength
- Warns about power management settings that cause disconnects
- Detects problematic configurations

### 🌐 Comprehensive Connectivity Testing
Tests 9 Azure Virtual Desktop endpoints:
- `rdgateway-r0.wvd.microsoft.com`
- `rdgateway-r1.wvd.microsoft.com`
- `rdgateway-g-us-r0.wvd.microsoft.com`
- `rdgateway-g-us-r1.wvd.microsoft.com`
- `rdbroker.wvd.microsoft.com`
- `rdweb.wvd.microsoft.com`
- `rdgateway.wvd.microsoft.com` (redirect server)
- `licensing.rd.microsoft.com` (RDP licensing)
- `diagnostics.wvd.microsoft.com` (diagnostics)

**Per-endpoint tests:**
- DNS resolution
- TCP port 443 connectivity
- HTTPS endpoint response
- Network latency (ping time)
- Packet loss (20 packet test)
- Network jitter (latency variance)
- Connection stability (detects resets/timeouts)
- MTU size (fragmentation detection)

### 🚨 Advanced Disconnect Diagnostics
- **Azure AD Authentication Tests** - Verifies login.microsoftonline.com, graph.microsoft.com, auth.gfx.ms connectivity
- **WebSocket Connectivity** - Tests RDP Web Client support and protocol upgrade capability
- **DNS Resolution Consistency** - Detects split-DNS, round-robin, and DNS consistency issues
- **TCP Reset Statistics** - Analyzes connection resets, TIME_WAIT states, and system event logs
- **UDP Connectivity** - Tests ports 3478, 3479, 3390 for RDP Shortpath
- **Time Synchronization** - Detects clock drift causing auth failures
- **DNS Cache & TTL** - Identifies stale DNS issues
- **Connection Broker Stress Test** - Tests broker stability under load
- **Background Network Activity** - Detects bandwidth-heavy applications
- **Network Adapter Power Management** - Identifies sleep settings causing disconnects
- **IPv4 vs IPv6 Testing** - Compares protocol performance
- **Sustained Connection Test** - 30 seconds of continuous monitoring to catch intermittent drops

### 📊 Reporting & Analysis
- **Color-coded console output** (Green/Yellow/Red)
- **Detailed log files** - One timestamped log per test run
- **CSV export** - Daily summary file for trending in Excel
- **Success rate calculations**
- **Actionable recommendations** for identified issues

## Requirements

> [!IMPORTANT]
> **PowerShell 7.0 or later is required** - PowerShell 5.1 is NOT supported

- Windows 10/11 or Windows Server
- Internet connectivity
- Administrator privileges recommended (for full diagnostics)

### Installing PowerShell 7

This script requires PowerShell 7 for improved performance and reliability.

**Option 1: Using Windows Package Manager (Recommended)**
```powershell
winget install Microsoft.PowerShell
```

**Option 2: Direct Download**

Download and install from: https://aka.ms/powershell

**Verify Installation**
```powershell
pwsh -Version
```

You should see version 7.0 or higher.

## Installation

### Option 1: Download Just the Script (Easiest)
1. Go to [Test-AVDEndUserConnectivity.ps1](https://github.com/colinweiner111/AVD-Connectivity-Test/blob/master/Test-AVDEndUserConnectivity.ps1)
2. Click the **"Raw"** button (top right)
3. Right-click → **"Save As..."** → Save to your desired location
4. Or use PowerShell to download directly:
```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/colinweiner111/AVD-Connectivity-Test/master/Test-AVDEndUserConnectivity.ps1" -OutFile "Test-AVDEndUserConnectivity.ps1"
```
5. Run with PowerShell 7:
```powershell
pwsh .\Test-AVDEndUserConnectivity.ps1
```

### Option 2: Download All Files as ZIP
1. Go to [https://github.com/colinweiner111/AVD-Connectivity-Test](https://github.com/colinweiner111/AVD-Connectivity-Test)
2. Click the green **"Code"** button
3. Select **"Download ZIP"**
4. Extract the ZIP file to your desired location

### Option 3: Clone with Git (If Git is Installed)
```powershell
git clone https://github.com/colinweiner111/AVD-Connectivity-Test.git
cd AVD-Connectivity-Test
```

### Unblock the Script
After downloading, unblock the script to allow execution:
```powershell
Unblock-File -Path .\Test-AVDEndUserConnectivity.ps1
```

## Usage

### Basic Usage
Run with default settings (tests every 5 minutes):
```powershell
pwsh .\Test-AVDEndUserConnectivity.ps1
```

### Custom Test Interval
Test every 3 minutes:
```powershell
pwsh .\Test-AVDEndUserConnectivity.ps1 -IntervalMinutes 3
```

### Custom Log Location
Save logs to a specific directory:
```powershell
pwsh .\Test-AVDEndUserConnectivity.ps1 -LogPath "C:\AVD-Logs"
```

### Combined Parameters
```powershell
.\Test-AVDEndUserConnectivity.ps1 -IntervalMinutes 10 -LogPath "C:\Logs"
```

### Stop the Script
Press `Ctrl+C` to stop monitoring

## Output Files

### Log Files
- **Format**: `AVD-Connectivity-YYYYMMDD-HHMMSS.log`
- **Location**: Script directory or custom `-LogPath`
- **Content**: Detailed timestamped test results
- **Example**: `AVD-Connectivity-20251124-143022.log`

### CSV Summary Files
- **Format**: `AVD-Connectivity-Summary-YYYYMMDD.csv`
- **Location**: Same as log files
- **Content**: Aggregated metrics for trending analysis
- **Updates**: Appends new row after each test run

#### CSV Columns Include:
- Timestamp
- Overall success rates
- Per-endpoint DNS/TCP/HTTPS status
- Latency, packet loss, jitter metrics
- Connection stability percentages

Import into Excel to:
- Create charts showing performance over time
- Identify patterns (e.g., disconnects at specific times)
- Compare Wi-Fi vs Ethernet performance
- Present evidence to network teams

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `IntervalMinutes` | Integer | 5 | Time in minutes between each connectivity test |
| `LogPath` | String | Script directory | Path where log files will be saved |

## Common Issues Detected

### ⚠️ Network Adapter Power Management
**Symptom**: Random disconnects after periods of inactivity  
**Detection**: Script warns if "Allow computer to turn off device to save power" is enabled  
**Fix**: Disable power management in adapter properties

### ⚠️ Wi-Fi Performance
**Symptom**: Higher latency and jitter compared to Ethernet  
**Detection**: Script identifies connection type and signal strength  
**Fix**: Switch to Ethernet or improve Wi-Fi signal

### ⚠️ UDP Blocked
**Symptom**: Poor video/audio quality, high latency  
**Detection**: UDP ports 3478-3479 unreachable  
**Fix**: Open UDP ports in firewall for RDP Shortpath

### ⚠️ Time Synchronization Issues
**Symptom**: Authentication failures, session drops  
**Detection**: Clock drift exceeds acceptable threshold  
**Fix**: Enable and restart Windows Time service

### ⚠️ High Packet Loss
**Symptom**: Choppy experience, frequent disconnects  
**Detection**: Packet loss percentage >5%  
**Fix**: Check network hardware, ISP connection quality

### ⚠️ IPv6 Performance Issues
**Symptom**: Slow connection establishment, delays  
**Detection**: IPv6 latency significantly higher than IPv4  
**Fix**: Disable IPv6 or fix IPv6 routing

## Understanding Results

### Success Rates
- **100%** - All tests passed (optimal)
- **90-99%** - Minor issues detected
- **70-89%** - Significant issues present
- **<70%** - Severe connectivity problems

### Latency Ratings
- **<50ms** - Excellent
- **50-100ms** - Good
- **100-200ms** - Fair
- **>200ms** - Poor (may cause disconnect issues)

### Packet Loss
- **0%** - Optimal
- **<5%** - Minimal (acceptable)
- **5-15%** - Moderate (may cause issues)
- **>15%** - High (will cause disconnects)

### Jitter
- **<5ms** - Excellent
- **5-15ms** - Acceptable
- **15-30ms** - Moderate
- **>30ms** - High (causes quality issues)

## Troubleshooting

### Script Won't Run
**Error**: "Execution of scripts is disabled on this system"
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Missing Permissions
Some tests require administrator privileges. Run PowerShell as Administrator for complete diagnostics.

### Firewall Blocks
If your organization blocks PowerShell scripts, work with IT to whitelist this script or run in approved environment.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

### Areas for Enhancement
- Email/webhook alerting on failures
- Baseline comparison (alert on deviation)
- Additional cloud environments (GCC High, DoD)
- Session host testing (for VPN-connected users)

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Author

Created for diagnosing Azure Virtual Desktop connectivity issues in enterprise environments.

## Changelog

### Version 1.0.0 (2025-11-24)
- Initial release
- Complete AVD gateway testing suite
- Advanced disconnect diagnostics
- CSV export for trending
- Network interface detection
- Power management checks
- IPv6 testing
- Sustained connection monitoring

## Support

For issues, questions, or feature requests, please open an issue on GitHub.

## Acknowledgments

- Microsoft Azure Virtual Desktop documentation
- PowerShell community for networking cmdlets
- Network troubleshooting best practices

## Microsoft Documentation Resources

### Azure Virtual Desktop
- [AVD Overview and Architecture](https://learn.microsoft.com/en-us/azure/virtual-desktop/overview)
- [Network Connectivity Requirements](https://learn.microsoft.com/en-us/azure/virtual-desktop/network-connectivity)
- [RDP Shortpath for Public Networks](https://learn.microsoft.com/en-us/azure/virtual-desktop/rdp-shortpath?tabs=public-networks)
- [Required URLs and Endpoints](https://learn.microsoft.com/en-us/azure/virtual-desktop/safe-url-list?tabs=azure)

### Troubleshooting Guides
- [Troubleshoot Connections to Azure Virtual Desktop](https://learn.microsoft.com/en-us/azure/virtual-desktop/troubleshoot-connection)
- [Diagnose Graphics Performance Issues](https://learn.microsoft.com/en-us/azure/virtual-desktop/remotefx-graphics-performance-counters)
- [Azure Virtual Desktop Insights](https://learn.microsoft.com/en-us/azure/virtual-desktop/insights)

### Network Requirements
- [Bandwidth Recommendations](https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/network-guidance)
- [Proxy Server Support](https://learn.microsoft.com/en-us/azure/virtual-desktop/proxy-server-support)
- [Azure Virtual Desktop Experience Estimator](https://azure.microsoft.com/en-us/products/virtual-desktop/assessment/)

## How Azure Virtual Desktop Connectivity Works

```
┌─────────────────┐
│   End User      │
│   Device        │ ← This script tests from here
└────────┬────────┘
         │ Internet Connection
         │ (Wi-Fi/Ethernet/VPN)
         │
         ▼
┌─────────────────────────────────────────────┐
│   Azure Virtual Desktop Gateway             │
│   - rdgateway.wvd.microsoft.com            │
│   - rdbroker.wvd.microsoft.com             │
│   - rdweb.wvd.microsoft.com                │
│                                             │
│   Public Endpoints                          │
│   - Port 443 (HTTPS/Gateway)               │
│   - Ports 3478/3479 (STUN/TURN)            │
│   - Port 3390 (UDP RDP Shortpath)          │
└────────┬────────────────────────────────────┘
         │ Azure Backbone Network
         │ (Private/Optimized)
         │
         ▼
┌─────────────────────────────────────────────┐
│   Session Hosts (Private VNet)             │
│   - Windows 10/11 Multi-session            │
│   - Windows Server                          │
│   - Private IP Addresses                    │
└─────────────────────────────────────────────┘

Test Coverage:
✓ User Device → Gateway (All tests)
✗ Gateway → Session Host (Managed by Azure)
```

### Connection Flow
1. **User initiates connection** → Contacts AVD Gateway
2. **Authentication** → Azure AD validates user
3. **Broker assignment** → Determines which session host to use
4. **Gateway establishes tunnel** → Connects to session host
5. **RDP session begins** → User sees their desktop

### Where Disconnects Typically Occur
- 🔴 **User's Internet Connection** (Most Common) - Poor Wi-Fi, ISP issues
- 🔴 **Network Adapter Power Management** - Device goes to sleep
- 🔴 **UDP Blocked** - Forces TCP fallback (slower, less stable)
- 🟡 **High Latency/Jitter** - Network congestion
- 🟡 **DNS Issues** - Stale cache, slow resolution
- 🟢 **Azure Gateway/Session Host** (Rare) - Azure manages reliability

**This script focuses on identifying issues in the user-controllable areas (red/yellow zones).**

---

**Note**: This script is for diagnostic purposes only and does not modify any system settings without user intervention.
