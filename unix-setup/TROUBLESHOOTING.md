# Troubleshooting Guide - Nucamp DefSec VM Setup

This guide covers common issues encountered during the VM setup process, with specific focus on Arch Linux snapd seeding problems.

## Quick Fix for Snapd Issues (Arch Linux)

If you see the error `"device not yet seeded"`, run this automated fix:

```bash
curl -fsSL https://raw.githubusercontent.com/nucamp/defsec/main/unix-setup/fix-snapd-arch.sh | bash
```

Then retry the main setup:

```bash
curl -fsSL https://raw.githubusercontent.com/nucamp/defsec/main/unix-setup/setup-improved.sh | bash
```

## Common Issues and Solutions

### 1. Snapd Seeding Error (Arch Linux)

**Error Message:**
```
error: too early for operation, device not yet seeded or device model not acknowledged
```

**What it means:**
Snapd was just installed and needs time to initialize its core system.

**Solution A - Automated Fix:**
```bash
curl -fsSL https://raw.githubusercontent.com/nucamp/defsec/main/unix-setup/fix-snapd-arch.sh | bash
```

**Solution B - Manual Steps:**
```bash
# 1. Restart snapd service
sudo systemctl restart snapd

# 2. Wait for seeding to complete
sudo snap wait system seed.loaded

# 3. Test snap functionality
sudo snap install hello-world
sudo snap remove hello-world

# 4. Install multipass
sudo snap install multipass

# 5. Retry main setup script
curl -fsSL <script-url> | bash
```

**Solution C - If above fails:**
```bash
# Reboot and try again
sudo reboot

# After reboot, run the recovery script
curl -fsSL https://raw.githubusercontent.com/nucamp/defsec/main/unix-setup/fix-snapd-arch.sh | bash
```

### 2. Multipass Installation Failures

**Error Messages:**
- `Failed to install multipass via snap`
- `multipass: command not found`

**Solutions:**

**Check snap status:**
```bash
sudo systemctl status snapd
sudo snap version
```

**Restart services:**
```bash
sudo systemctl restart snapd.socket
sudo systemctl restart snapd
```

**Manual multipass installation:**
```bash
sudo snap install multipass
multipass version
```

### 3. Network Connectivity Issues

**Error Message:**
```
Network connectivity test failed for VM
```

**Solutions:**

**Check host connectivity:**
```bash
ping -c 3 8.8.8.8
curl -I https://google.com
```

**Check multipass network:**
```bash
multipass exec vm-name -- ping -c 3 8.8.8.8
```

**Restart multipass:**
```bash
sudo systemctl restart multipass  # Linux
brew services restart multipass   # macOS
```

### 4. Insufficient Disk Space

**Error Messages:**
- `No space left on device`
- `Failed to create VM`

**Check disk space:**
```bash
df -h
```

**Free up space:**
```bash
# Clean package cache
sudo pacman -Scc     # Arch
sudo apt clean       # Ubuntu/Debian
brew cleanup         # macOS

# Clean Docker (if installed)
docker system prune -a

# Remove old logs
sudo journalctl --vacuum-time=7d
```

### 5. Permission Errors

**Error Messages:**
- `Permission denied`
- `Operation not permitted`

**Solutions:**

**Don't run as root:**
```bash
./setup.sh          # ✅ Correct
sudo ./setup.sh     # ❌ Wrong
```

**Fix multipass permissions:**
```bash
sudo chown -R $USER:$USER ~/.multipass
```

### 6. VM Creation Failures

**Error Messages:**
- `Failed to create VM`
- `launch failed`

**Check existing VMs:**
```bash
multipass list
```

**Delete conflicting VMs:**
```bash
multipass delete vm-name
multipass purge
```

**Check multipass status:**
```bash
multipass version
multipass info
```

## System-Specific Troubleshooting

### Arch Linux

**Common Issues:**
- Snapd seeding delays
- AUR package conflicts
- Missing dependencies

**Diagnostic Commands:**
```bash
# Check snapd status
sudo systemctl status snapd.socket
sudo snap version

# Check AUR helper
which yay
yay --version

# Check system updates
sudo pacman -Syu
```

### Ubuntu/Debian

**Common Issues:**
- Snap not installed
- Outdated packages

**Diagnostic Commands:**
```bash
# Update packages
sudo apt update && sudo apt upgrade

# Check snap
which snap
snap version

# Install snap if missing
sudo apt install snapd
```

### macOS

**Common Issues:**
- Homebrew not installed
- Virtualization not enabled

**Diagnostic Commands:**
```bash
# Check Homebrew
which brew
brew --version

# Check virtualization
sysctl kern.hv_support

# Install Homebrew if missing
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## Recovery Procedures

### Complete Reset

If everything fails, perform a complete reset:

```bash
# Remove all VMs
multipass delete --all
multipass purge

# Remove multipass
sudo snap remove multipass  # Linux
brew uninstall multipass    # macOS

# Remove snapd (Linux only, if needed)
sudo pacman -R snapd        # Arch
sudo apt remove snapd       # Ubuntu

# Restart system
sudo reboot

# Run setup again
curl -fsSL <script-url> | bash
```

### Partial Recovery

If VMs exist but have issues:

```bash
# List VMs
multipass list

# Get VM info
multipass info vm-name

# Restart VM
multipass restart vm-name

# Access VM for manual fixes
multipass shell vm-name
```

## Log Analysis

### Finding Log Files

Setup logs are saved to:
```
/tmp/nucamp-setup-<timestamp>.log
```

### Useful Log Commands

```bash
# Find latest log
ls -la /tmp/nucamp-setup-*.log

# View log
cat /tmp/nucamp-setup-*.log

# Search for errors
grep -i error /tmp/nucamp-setup-*.log

# Follow log in real-time (during setup)
tail -f /tmp/nucamp-setup-*.log
```

### System Logs

```bash
# Snapd logs
sudo journalctl -u snapd

# Multipass logs
sudo journalctl -u multipass

# System messages
sudo dmesg | tail -20
```

## Getting Help

### Before Asking for Help

1. **Check this troubleshooting guide**
2. **Run diagnostic commands** for your system
3. **Check log files** for specific errors
4. **Try the recovery procedures** listed above

### Information to Provide

When seeking help, include:

1. **Operating system and version**
   ```bash
   uname -a
   cat /etc/os-release
   ```

2. **Error message** (exact text)

3. **Log file contents** (relevant sections)

4. **System resources**
   ```bash
   free -h
   df -h
   ```

5. **Network connectivity**
   ```bash
   ping -c 3 8.8.8.8
   ```

### Diagnostic Script

Run this to gather system information:

```bash
#!/bin/bash
echo "=== System Information ==="
uname -a
cat /etc/os-release 2>/dev/null || sw_vers

echo -e "\n=== Resources ==="
free -h 2>/dev/null || vm_stat
df -h

echo -e "\n=== Network ==="
ping -c 3 8.8.8.8

echo -e "\n=== Snapd Status ==="
systemctl status snapd 2>/dev/null || echo "Snapd not available"
snap version 2>/dev/null || echo "Snap command not available"

echo -e "\n=== Multipass Status ==="
multipass version 2>/dev/null || echo "Multipass not available"
multipass list 2>/dev/null || echo "Cannot list VMs"
```

## Prevention Tips

### Before Running Setup

1. **Ensure sufficient resources** (4GB RAM, 40GB disk)
2. **Update your system** packages
3. **Check internet connectivity**
4. **Close unnecessary applications**

### Best Practices

1. **Run on a clean system** when possible
2. **Don't interrupt** the setup process
3. **Check logs** if anything seems wrong
4. **Reboot if needed** before retrying

### Monitoring Setup

```bash
# Monitor resources during setup
watch -n 5 'free -h && df -h'

# Monitor logs
tail -f /tmp/nucamp-setup-*.log

# Check process status
ps aux | grep -E "(snap|multipass)"
```

---

**Need more help?** Contact Nucamp support with the diagnostic information listed above.