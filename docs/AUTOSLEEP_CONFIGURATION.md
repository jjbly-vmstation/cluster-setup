# Auto-Sleep Configuration Guide

This guide provides detailed information on configuring the VMStation auto-sleep functionality.

## Overview

Auto-sleep automatically puts idle cluster nodes into suspend mode to conserve power. When activity is detected or the node is needed, it can be woken using Wake-on-LAN.

## Configuration File

The main configuration file is located at `/etc/vmstation/autosleep/autosleep.conf`.

### Full Configuration Reference

```ini
#################################################
# VMStation Auto-Sleep Configuration
#################################################

[general]
# Enable or disable auto-sleep
enabled=true

# Minutes of inactivity before initiating sleep
# Default: 120 (2 hours)
inactivity_timeout_minutes=120

# How often to check for activity (minutes)
# Default: 5
check_interval_minutes=5

# Grace period after timeout before actual sleep (minutes)
# Gives time for notification and last-minute activity
# Default: 10
grace_period_minutes=10

#################################################
[activity_detection]
#################################################

# Check for running pods (excluding system namespaces)
check_pods=true

# Check CPU usage
check_cpu=true

# CPU usage threshold (percent)
# If CPU is above this, consider active
cpu_threshold_percent=10

# Check network activity
check_network=true

# Network activity threshold (bytes per second)
network_threshold_bytes=1024

# Check for active SSH sessions
check_ssh_sessions=true

#################################################
[excluded_namespaces]
#################################################
# Pods in these namespaces do not prevent sleep
# One namespace per line
kube-system
kube-public
kube-node-lease
monitoring
logging
cert-manager

#################################################
[prevent_sleep_labels]
#################################################
# Pods with these labels prevent the node from sleeping
# Format: label=value
vmstation.io/prevent-sleep=true
app.kubernetes.io/always-on=true

#################################################
[notification]
#################################################

# Send notification before sleep
enabled=true

# Minutes before sleep to send notification
minutes_before=5

# Notification method: log, webhook, slack
method=webhook

# Webhook URL for notifications
webhook_url=https://hooks.example.com/vmstation

# Slack channel (if method=slack)
slack_channel=#ops-alerts

#################################################
[logging]
#################################################

# Log directory
log_dir=/var/log/vmstation

# Log level: DEBUG, INFO, WARN, ERROR
log_level=INFO

# Maximum log file size (MB)
max_log_size=100

# Number of log files to keep
log_retention=7
```

## Environment Variables

The auto-sleep monitor accepts environment variables that override configuration file settings:

| Variable | Description | Default |
|----------|-------------|---------|
| `CONFIG_FILE` | Path to config file | `/etc/vmstation/autosleep/autosleep.conf` |
| `STATE_FILE` | Path to state file | `/var/lib/vmstation/autosleep/state` |
| `LOG_FILE` | Path to log file | `/var/log/vmstation/autosleep.log` |
| `INACTIVITY_TIMEOUT_MINUTES` | Timeout before sleep | `120` |
| `CHECK_INTERVAL_MINUTES` | Check interval | `5` |
| `GRACE_PERIOD_MINUTES` | Grace period | `10` |
| `CPU_THRESHOLD_PERCENT` | CPU threshold | `10` |
| `NETWORK_THRESHOLD_BYTES` | Network threshold | `1024` |
| `NETWORK_INTERFACE` | Network interface to monitor | `eth0` |
| `NOTIFICATION_ENABLED` | Enable notifications | `false` |
| `NOTIFICATION_WEBHOOK_URL` | Webhook URL | (empty) |

## State File

The state file tracks the current auto-sleep state:

```bash
# Location
/var/lib/vmstation/autosleep/state

# Contents
LAST_ACTIVITY=1699900000
SLEEP_PENDING=false
SLEEP_ENABLED=true
LAST_CHECK=1699900300
```

### State Fields

| Field | Description |
|-------|-------------|
| `LAST_ACTIVITY` | Unix timestamp of last detected activity |
| `SLEEP_PENDING` | Whether sleep sequence has started |
| `SLEEP_ENABLED` | Whether auto-sleep is enabled |
| `LAST_CHECK` | Timestamp of last activity check |

## Tuning for Your Workload

### High-Activity Clusters

For clusters with frequent workload changes:

```ini
[general]
inactivity_timeout_minutes=240  # 4 hours
check_interval_minutes=10
grace_period_minutes=15

[activity_detection]
cpu_threshold_percent=5
network_threshold_bytes=512
```

### Development Clusters

For development environments that are often idle:

```ini
[general]
inactivity_timeout_minutes=60   # 1 hour
check_interval_minutes=5
grace_period_minutes=5

[activity_detection]
check_pods=true
check_cpu=true
cpu_threshold_percent=15
```

### Batch Processing Clusters

For clusters running scheduled batch jobs:

```ini
[general]
inactivity_timeout_minutes=30
check_interval_minutes=2
grace_period_minutes=5

[activity_detection]
check_pods=true
check_cpu=true
cpu_threshold_percent=5
```

## Preventing Sleep

### Using Labels

Add labels to critical pods:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: critical-app
spec:
  template:
    metadata:
      labels:
        vmstation.io/prevent-sleep: "true"
```

### Temporary Disable

```bash
# Disable for a node
vmstation-autosleep-ctl disable

# Re-enable
vmstation-autosleep-ctl enable
```

### Maintenance Window

For scheduled maintenance:

```bash
# Disable via API or config
ssh worker-01 "vmstation-autosleep-ctl disable"

# Perform maintenance...

# Re-enable
ssh worker-01 "vmstation-autosleep-ctl enable"
```

## Pre-Sleep Hooks

Custom scripts can be run before sleep.

### Hook Directory

```bash
/opt/vmstation/autosleep/pre-sleep.d/
```

### Hook Script Example

```bash
#!/bin/bash
# /opt/vmstation/autosleep/pre-sleep.d/01-notify.sh

# Notify external system
curl -X POST "https://api.example.com/nodes/$(hostname)/sleeping" \
  -H "Authorization: Bearer $API_TOKEN"
```

### Hook Requirements

- Must be executable: `chmod +x script.sh`
- Should exit with 0 on success
- Hooks run in alphabetical order
- Failing hooks are logged but don't prevent sleep

## Monitoring Auto-Sleep

### Check Service Status

```bash
systemctl status vmstation-autosleep.service
```

### View Logs

```bash
# Follow logs in real-time
journalctl -u vmstation-autosleep.service -f

# Last 100 lines
journalctl -u vmstation-autosleep.service -n 100

# Since last boot
journalctl -u vmstation-autosleep.service -b
```

### Log Format

```
[2024-01-15T10:30:00+00:00] [INFO] Node idle for 60 minutes (timeout: 120 minutes)
[2024-01-15T10:35:00+00:00] [INFO] Activity detected, reset idle timer
[2024-01-15T12:30:00+00:00] [INFO] Node idle for 120 minutes (timeout: 120 minutes)
[2024-01-15T12:30:00+00:00] [INFO] Sleep pending, grace period started
[2024-01-15T12:40:00+00:00] [INFO] Initiating sleep sequence
```

## Integration with Ansible

### Deploy Configuration

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/setup-autosleep.yml \
  -e autosleep_timeout_minutes=180 \
  -e autosleep_check_interval_minutes=10
```

### Update Configuration

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/setup-autosleep.yml \
  --tags=config
```

## Troubleshooting

### Node Sleeps Too Quickly

1. Increase `inactivity_timeout_minutes`
2. Lower `cpu_threshold_percent`
3. Add more activity checks

### Node Never Sleeps

1. Check for running pods: `kubectl get pods --all-namespaces`
2. Check CPU usage: `top -bn1`
3. Check SSH sessions: `who`
4. Review excluded namespaces

### Activity Not Detected

1. Verify kubectl access: `kubectl get nodes`
2. Check network interface name
3. Lower detection thresholds

### Service Crashes

1. Check logs: `journalctl -u vmstation-autosleep.service`
2. Verify config file syntax
3. Check file permissions
4. Ensure state directory exists

## Best Practices

1. **Start with longer timeouts** and reduce based on experience
2. **Monitor power savings** to validate effectiveness
3. **Document which nodes can sleep** in your runbooks
4. **Test wake procedures** regularly
5. **Configure notifications** to track sleep events
6. **Review logs weekly** to tune thresholds
