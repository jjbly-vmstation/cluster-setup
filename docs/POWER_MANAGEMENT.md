# VMStation Power Management Guide

This guide covers the power management features of the VMStation cluster, including auto-sleep, Wake-on-LAN, and cluster shutdown.

## Overview

The VMStation power management system provides:
- **Auto-sleep**: Automatically suspends idle nodes to save power
- **Wake-on-LAN**: Remotely wakes nodes when needed
- **Graceful shutdown**: Properly shuts down the cluster with workload migration

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Master Node   │     │  Worker Node 1  │     │  Worker Node 2  │
│                 │     │                 │     │                 │
│  Wake Handler   │────▶│ Autosleep Mon.  │     │ Autosleep Mon.  │
│  (HTTP API)     │     │                 │     │                 │
│                 │     │  WoL Enabled    │     │  WoL Enabled    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        │                       ▼                       ▼
        │               ┌───────────────────────────────────┐
        └──────────────▶│          Magic Packets           │
                        └───────────────────────────────────┘
```

## Quick Start

### Enable Power Management

```bash
# Configure power management on all nodes
./orchestration/quick-deploy.sh power

# Configure auto-sleep on sleepable nodes
./orchestration/quick-deploy.sh autosleep

# Deploy wake event handler on master
./orchestration/quick-deploy.sh wake
```

### Manual Control

```bash
# Wake a specific node
/opt/vmstation/power/vmstation-wake.sh worker-01

# Wake all nodes
/opt/vmstation/power/vmstation-wake.sh --all

# Put a node to sleep
/opt/vmstation/power/vmstation-sleep.sh

# Check cluster power status
curl http://master:9876/status
```

## Auto-Sleep

### How It Works

The auto-sleep monitor continuously checks for node activity:

1. **Pod activity**: Checks for running user pods
2. **CPU usage**: Monitors CPU utilization
3. **Network activity**: Detects network traffic
4. **SSH sessions**: Checks for active sessions

When no activity is detected for the configured timeout, the node enters sleep mode.

### Configuration

Edit `/etc/vmstation/autosleep/autosleep.conf`:

```ini
[general]
enabled=true
inactivity_timeout_minutes=120
check_interval_minutes=5
grace_period_minutes=10

[activity_detection]
check_pods=true
check_cpu=true
cpu_threshold_percent=10
check_network=true
network_threshold_bytes=1024
check_ssh_sessions=true

[excluded_namespaces]
kube-system
monitoring
logging

[notification]
enabled=true
minutes_before=5
method=webhook
webhook_url=http://your-webhook-url
```

### Control Commands

```bash
# Check status
vmstation-autosleep-ctl status

# Disable auto-sleep temporarily
vmstation-autosleep-ctl disable

# Enable auto-sleep
vmstation-autosleep-ctl enable

# Reset activity timer
vmstation-autosleep-ctl reset
```

### Systemd Service

```bash
# Check service status
systemctl status vmstation-autosleep.service

# View logs
journalctl -u vmstation-autosleep.service -f

# Stop service
systemctl stop vmstation-autosleep.service
```

## Wake-on-LAN

### Prerequisites

- Network interface must support WoL
- WoL enabled in BIOS/UEFI
- Network switch must support passing magic packets

### Setup

```bash
# Check WoL support
ethtool eth0 | grep "Wake-on"

# Enable WoL
ethtool -s eth0 wol g

# Verify
ethtool eth0 | grep "Wake-on"
# Should show: Wake-on: g
```

### Wake Commands

```bash
# Using vmstation-wake script
/opt/vmstation/power/vmstation-wake.sh worker-01

# Using wakeonlan directly
wakeonlan AA:BB:CC:DD:EE:FF

# Using the HTTP API
curl -X POST http://master:9876/wake/worker-01 \
  -H "X-Auth-Token: your-token"
```

### Wake Event Handler API

The wake event handler provides an HTTP API on port 9876:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/wake/<hostname>` | POST | Wake specific node |
| `/wake/all` | POST | Wake all nodes |
| `/status` | GET | Cluster power status |

Example:
```bash
# Wake a node with verification
curl -X POST "http://master:9876/wake/worker-01?verify=true" \
  -H "X-Auth-Token: your-token"

# Get cluster status
curl http://master:9876/status
```

## Graceful Cluster Shutdown

### Spin-Down Process

The spin-down playbook performs:

1. Cordon all worker nodes
2. Drain workloads from workers
3. Scale deployments to zero
4. Preserve state
5. Shutdown workers
6. Shutdown storage nodes
7. Shutdown masters (optional)

### Running Spin-Down

```bash
# Full cluster shutdown
ansible-playbook -i ansible/inventory/hosts.yml \
  power-management/playbooks/spin-down-cluster.yml

# Dry run
ansible-playbook -i ansible/inventory/hosts.yml \
  power-management/playbooks/spin-down-cluster.yml --check

# Skip master shutdown
ansible-playbook -i ansible/inventory/hosts.yml \
  power-management/playbooks/spin-down-cluster.yml \
  -e shutdown_control_plane=false
```

### Cluster Recovery

To restart the cluster:

1. Wake master nodes first
2. Wait for control plane to be ready
3. Wake storage nodes
4. Wake worker nodes
5. Uncordon workers

```bash
# Wake all nodes
/opt/vmstation/power/vmstation-wake.sh --all --verify

# Uncordon workers
kubectl uncordon worker-01
kubectl uncordon worker-02
```

## Prevent Sleep Labels

Add labels to pods that should prevent node sleep:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: critical-pod
  labels:
    vmstation.io/prevent-sleep: "true"
spec:
  containers:
  - name: app
    image: myapp:latest
```

## Pre-Sleep Hooks

Add custom scripts to run before sleep:

```bash
# Create hook directory
mkdir -p /opt/vmstation/power/pre-sleep.d

# Add a hook script
cat > /opt/vmstation/power/pre-sleep.d/01-save-state.sh << 'EOF'
#!/bin/bash
# Save application state before sleep
kubectl get pods --all-namespaces -o yaml > /var/lib/vmstation/pod-backup.yaml
EOF

chmod +x /opt/vmstation/power/pre-sleep.d/01-save-state.sh
```

## Monitoring

### Logs

```bash
# Auto-sleep logs
journalctl -u vmstation-autosleep.service

# Wake handler logs
journalctl -u vmstation-wake-event.service

# Power management logs
tail -f /var/log/vmstation/power.log
```

### Metrics

The system logs can be parsed for metrics:
- Sleep events per node
- Wake events per node
- Activity detection triggers
- Failed wake attempts

## Troubleshooting

### Node Won't Wake

1. Check WoL is enabled in BIOS
2. Verify WoL is enabled on interface: `ethtool eth0 | grep "Wake-on"`
3. Check MAC address is correct
4. Ensure magic packets reach the node

### Auto-Sleep Not Working

1. Check service status: `systemctl status vmstation-autosleep.service`
2. Verify configuration: `cat /etc/vmstation/autosleep/autosleep.conf`
3. Check logs: `journalctl -u vmstation-autosleep.service`
4. Verify state file: `cat /var/lib/vmstation/autosleep/state`

### Wake Handler Connection Refused

1. Check service is running: `systemctl status vmstation-wake-event.service`
2. Verify port is open: `ss -tlnp | grep 9876`
3. Check firewall: `ufw status` or `firewall-cmd --list-ports`

## Security Considerations

1. **Authentication**: Always enable auth token for wake handler
2. **Network**: Restrict wake handler access to trusted networks
3. **Firewall**: Limit WoL ports access
4. **Logging**: Monitor wake events for unauthorized attempts

## Best Practices

1. **Test thoroughly** before enabling auto-sleep in production
2. **Set appropriate timeouts** based on workload patterns
3. **Monitor power consumption** to validate savings
4. **Document wake procedures** for operations team
5. **Configure notifications** for sleep/wake events
