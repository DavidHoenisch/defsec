# Custom Safe-Sleep function
function Safe-Sleep {
    param (
        [int]$seconds = 0
    )

    if ($seconds -gt 0) {
        Start-Sleep -Seconds $seconds
    }
}

# Function to wait for VM to be ready
function Wait-ForVMReady {
    param (
        [string]$vmName,
        [int]$maxWaitSeconds = 600,  # Increased timeout for resource contention
        [int]$checkIntervalSeconds = 15
    )

    Write-Host "Waiting for $vmName to be ready..." -ForegroundColor Yellow
    $elapsed = 0
    $lastState = ""

    while ($elapsed -lt $maxWaitSeconds) {
        try {
            # Check if VM is running
            $vmInfo = multipass info $vmName --format json | ConvertFrom-Json
            $vmState = $vmInfo.info.$vmName.state

            # Show state changes
            if ($vmState -ne $lastState) {
                Write-Host "  $vmName state changed: $lastState -> $vmState" -ForegroundColor Cyan
                $lastState = $vmState
            }

            if ($vmState -eq "Running") {
                # Try a simple command to see if VM is responsive
                Write-Host "  Testing $vmName responsiveness..." -ForegroundColor Gray
                $testResult = multipass exec $vmName -- echo "ready" 2>$null
                if ($LASTEXITCODE -eq 0 -and $testResult -eq "ready") {
                    Write-Host "✔ $vmName is ready!" -ForegroundColor Green
                    return $true
                } else {
                    Write-Host "  $vmName is running but not yet responsive..." -ForegroundColor Gray
                }
            } elseif ($vmState -eq "Starting") {
                Write-Host "  $vmName is starting up..." -ForegroundColor Gray
            } elseif ($vmState -eq "Stopped") {
                Write-Host "  $vmName is stopped, attempting to start..." -ForegroundColor Yellow
                multipass start $vmName
            }

            Start-Sleep -Seconds $checkIntervalSeconds
            $elapsed += $checkIntervalSeconds
        }
        catch {
            Write-Host "  Checking $vmName readiness... ($elapsed/$maxWaitSeconds seconds)" -ForegroundColor Gray
            Start-Sleep -Seconds $checkIntervalSeconds
            $elapsed += $checkIntervalSeconds
        }
    }

    Write-Host "[!] Timeout waiting for $vmName to be ready after $maxWaitSeconds seconds" -ForegroundColor Red
    Write-Host "Diagnostic information:" -ForegroundColor Yellow
    try {
        multipass info $vmName
    } catch {
        Write-Host "Could not get VM info: $($_.Exception.Message)" -ForegroundColor Red
    }
    return $false
}

# Function to execute command with retry logic
function Invoke-MultipassCommand {
    param (
        [string]$vmName,
        [string]$command,
        [int]$maxRetries = 3,
        [int]$retryDelaySeconds = 5
    )

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            Write-Host "  Executing on $vmName (attempt $attempt/$maxRetries): $command" -ForegroundColor Gray
            $result = multipass exec $vmName -- $command

            if ($LASTEXITCODE -eq 0) {
                return $result
            } else {
                Write-Host "  Command failed with exit code $LASTEXITCODE" -ForegroundColor Yellow
                if ($attempt -lt $maxRetries) {
                    Write-Host "  Retrying in $retryDelaySeconds seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds $retryDelaySeconds
                }
            }
        }
        catch {
            Write-Host "  Exception on attempt $attempt : $($_.Exception.Message)" -ForegroundColor Yellow
            if ($attempt -lt $maxRetries) {
                Write-Host "  Retrying in $retryDelaySeconds seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds $retryDelaySeconds
            }
        }
    }

    Write-Host "[!] Command failed after $maxRetries attempts: $command" -ForegroundColor Red
    return $null
}

# Function to check if running as administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Check if running as administrator
if (-not (Test-Administrator)) {
    Write-Host "[!] This script requires administrator privileges. Please run PowerShell as Administrator." -ForegroundColor Red
    Pause
    exit 1
}

Write-Host @"
Hey there!!

Imma just be over here setting up nucamp VMs on your machine :) I will be sure
to let you know all the things that I am doing

"@ -ForegroundColor Green

Safe-Sleep 2

# Check if Chocolatey is already installed
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    try {
        iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    }
    catch {
        Write-Host "[!] Failed to install Chocolatey: $($_.Exception.Message)" -ForegroundColor Red
        Pause
        exit 1
    }
} else {
    Write-Host "Chocolatey is already installed." -ForegroundColor Green
}

# Refresh environment variables to ensure choco is available
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Check if VirtualBox is already installed
$vboxInstalled = $false
if (Get-Command "VBoxManage" -ErrorAction SilentlyContinue) {
    Write-Host "VirtualBox is already installed." -ForegroundColor Green
    $vboxInstalled = $true
} else {
    Write-Host "Installing VirtualBox..." -ForegroundColor Yellow
    try {
        choco install virtualbox -y --force
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] VirtualBox installation failed. Trying alternative method..." -ForegroundColor Yellow
            # Try downloading and installing directly
            $vboxUrl = "https://download.virtualbox.org/virtualbox/7.1.10/VirtualBox-7.1.10-169112-Win.exe"
            $vboxInstaller = "$env:TEMP\VirtualBox-installer.exe"
            Write-Host "Downloading VirtualBox directly..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $vboxUrl -OutFile $vboxInstaller
            Write-Host "Installing VirtualBox (this may take a few minutes)..." -ForegroundColor Yellow
            Start-Process -FilePath $vboxInstaller -ArgumentList "/S" -Wait
            Remove-Item $vboxInstaller -Force
        }
        $vboxInstalled = $true
    }
    catch {
        Write-Host "[!] Failed to install VirtualBox: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Please install VirtualBox manually from https://www.virtualbox.org/wiki/Downloads" -ForegroundColor Yellow
        Pause
        exit 1
    }
}

# Check if Multipass is already installed
$multipassInstalled = $false
if (Get-Command multipass -ErrorAction SilentlyContinue) {
    Write-Host "Multipass is already installed." -ForegroundColor Green
    $multipassInstalled = $true
} else {
    Write-Host "Installing Multipass..." -ForegroundColor Yellow
    try {
        if ($vboxInstalled) {
            choco install multipass --params="'/HyperVisor:VirtualBox'" -y --force
        } else {
            choco install multipass -y --force
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] Multipass installation via Chocolatey failed. Trying direct download..." -ForegroundColor Yellow
            $multipassUrl = "https://github.com/canonical/multipass/releases/download/v1.15.1/multipass-1.15.1+win-win64.msi"
            $multipassInstaller = "$env:TEMP\multipass-installer.msi"
            Invoke-WebRequest -Uri $multipassUrl -OutFile $multipassInstaller
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$multipassInstaller`" /passive" -Wait
            Remove-Item $multipassInstaller -Force
        }
        $multipassInstalled = $true
    }
    catch {
        Write-Host "[!] Failed to install Multipass: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Please install Multipass manually from https://multipass.run/" -ForegroundColor Yellow
        Pause
        exit 1
    }
}

# Refresh PATH again to ensure multipass is available
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host "Waiting for installations to complete..." -ForegroundColor Yellow
Safe-Sleep 10

# Check if multipass is now available
if (-not (Get-Command multipass -ErrorAction SilentlyContinue)) {
    Write-Host "[!] Multipass is not available in PATH. You may need to restart your computer or PowerShell session." -ForegroundColor Red
    Write-Host "After restart, you can continue from checking existing instances." -ForegroundColor Yellow
    Pause
    exit 1
}

Write-Host @"
Ok, first I will check if you already have multipass machines running on your
computer. This will help avoid potential naming conflicts.
"@ -ForegroundColor Cyan

Safe-Sleep 2

# Get current instances with error handling
try {
    $currentInstances = multipass list --format json | ConvertFrom-Json
    $currentCount = $currentInstances.list.Count
    $currentNames = $currentInstances.list | Select-Object -ExpandProperty name
}
catch {
    Write-Host "[!] Error getting multipass instances: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Continuing anyway..." -ForegroundColor Yellow
    $currentCount = 0
    $currentNames = @()
}

if ($currentCount -gt 0) {
    Write-Host "`nHey look, I found some running instances!`n" -ForegroundColor Yellow
    $currentNames | ForEach-Object { Write-Host " - $_" -ForegroundColor White }
}

$newMachines = @("nucamp-ubuntu-machine-1", "nucamp-ubuntu-machine-2")

Write-Host @"
Now I will check for naming conflicts.
The machines I plan to create are:

- nucamp-ubuntu-machine-1
- nucamp-ubuntu-machine-2

If I find a conflict, I will offer to fix it automatically.

"@ -ForegroundColor Cyan

Safe-Sleep 2

# Check for existing machines and handle conflicts
$conflictsFound = $false
foreach ($name in $newMachines) {
    if ($currentNames -contains $name) {
        Write-Host "`n[!] Found name conflict: $name already exists!" -ForegroundColor Red
        $conflictsFound = $true
    }
}

if ($conflictsFound) {
    Write-Host @"

Would you like me to automatically delete the existing conflicting VMs and recreate them?
This will permanently delete any data in the existing VMs.

"@ -ForegroundColor Yellow

    $response = Read-Host "Type 'yes' to delete and recreate, or 'no' to exit"

    if ($response.ToLower() -eq 'yes' -or $response.ToLower() -eq 'y') {
        Write-Host "Deleting conflicting VMs..." -ForegroundColor Yellow
        foreach ($name in $newMachines) {
            if ($currentNames -contains $name) {
                try {
                    multipass delete $name
                    Write-Host "Deleted $name" -ForegroundColor Green
                }
                catch {
                    Write-Host "[!] Failed to delete $name" -ForegroundColor Red
                }
            }
        }
        multipass purge
        Write-Host "Purged deleted instances." -ForegroundColor Green
    } else {
        Write-Host "Exiting. Please resolve conflicts manually:" -ForegroundColor Yellow
        Write-Host @"
Rename existing VM:
multipass stop <vm-name>
# Then manually rename or delete via multipass commands

Delete and purge:
multipass delete <vm-name>
multipass purge
"@ -ForegroundColor White
        Pause
        exit 1
    }
}

Write-Host "`nNo conflicts found! Creating your VMs now..." -ForegroundColor Green
Safe-Sleep 3

foreach ($name in $newMachines) {
    Write-Host "Creating $name..." -ForegroundColor Yellow
    try {
        multipass launch --cpus 2 --memory 2G --name $name 24.04 --disk 20GB
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✔ Successfully launched $name" -ForegroundColor Green

            # Wait for VM to be fully ready before continuing
            if (-not (Wait-ForVMReady -vmName $name -maxWaitSeconds 300)) {
                Write-Host "[!] $name failed to become ready within timeout period" -ForegroundColor Red
                Write-Host "You can check VM status with: multipass info $name" -ForegroundColor Yellow
                Pause
                exit 1
            }
        } else {
            Write-Host "[!] Failed to create machine: $name (Exit code: $LASTEXITCODE)" -ForegroundColor Red
            Pause
            exit 1
        }
    }
    catch {
        Write-Host "[!] Exception creating $name : $($_.Exception.Message)" -ForegroundColor Red
        Pause
        exit 1
    }
}

Write-Host @"
✔ All machines created successfully!

Now I will check if each VM can reach the internet by pinging 1.1.1.1...
"@ -ForegroundColor Green

foreach ($name in $newMachines) {
    Write-Host "`nChecking network for $name..." -ForegroundColor Yellow
    $pingResult = Invoke-MultipassCommand -vmName $name -command "ping -c 3 1.1.1.1" -maxRetries 3 -retryDelaySeconds 10

    if ($pingResult -ne $null) {
        Write-Host "✔ Network check passed for $name" -ForegroundColor Green
    } else {
        Write-Host "[!] Network check failed for $name after multiple attempts!" -ForegroundColor Red
        Write-Host "VM may have network issues. You can check later with: multipass exec $name -- ping -c 3 1.1.1.1" -ForegroundColor Yellow
    }
}

Write-Host @"
✔ Network checks completed!

Now downloading and executing the setup script on the hacking machine...
"@ -ForegroundColor Green

Safe-Sleep 3

# Download setup script with better error handling
$setupScriptUrl = "https://raw.githubusercontent.com/nucamp/defsec/refs/heads/main/kali/setup.sh"
$setupScriptPath = "./ubuntu_setup.sh"

try {
    Write-Host "Downloading setup script..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $setupScriptUrl -OutFile $setupScriptPath -UseBasicParsing

    if (Test-Path $setupScriptPath) {
        Write-Host "Transferring setup script to nucamp-ubuntu-machine-2..." -ForegroundColor Yellow
        multipass transfer $setupScriptPath nucamp-ubuntu-machine-2:/home/ubuntu/setup.sh

        Write-Host "Executing setup script (this may take several minutes)..." -ForegroundColor Yellow
        multipass exec nucamp-ubuntu-machine-2 -- sudo bash /home/ubuntu/setup.sh

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✔ Setup script executed successfully!" -ForegroundColor Green
        } else {
            Write-Host "[!] Setup script execution completed with exit code: $LASTEXITCODE" -ForegroundColor Yellow
            Write-Host "Check the VM logs for details: multipass exec nucamp-ubuntu-machine-2 -- sudo journalctl -xe" -ForegroundColor Yellow
        }

        # Clean up local setup script
        Remove-Item $setupScriptPath -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "[!] Failed to download setup.sh. Please check your internet connection." -ForegroundColor Red
        Pause
        exit 1
    }
}
catch {
    Write-Host "[!] Error with setup script: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "You can manually run the setup later inside the VM." -ForegroundColor Yellow
}

Write-Host @"

🎉 Done setting up your VMs!

Your VMs are ready:
- nucamp-ubuntu-machine-1 (basic Ubuntu)
- nucamp-ubuntu-machine-2 (with setup script applied)

To access your VMs:
multipass shell nucamp-ubuntu-machine-1
multipass shell nucamp-ubuntu-machine-2

To see all VMs:
multipass list

If you run into issues, you can:
- Check VM status: multipass info <vm-name>
- View VM logs: multipass exec <vm-name> -- sudo journalctl -xe
- Restart a VM: multipass restart <vm-name>

"@ -ForegroundColor Green

Write-Host "Press Enter to exit..." -ForegroundColor Cyan
Read-Host
