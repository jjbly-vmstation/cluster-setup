# VMStation Cluster Setup

This repository contains the complete cluster setup, initialization, and power management infrastructure for the VMStation project.

## Features

- **Bootstrap Scripts**: Automated dependency installation and node preparation
- **Ansible Playbooks**: Idempotent cluster configuration and deployment
- **Power Management**: Auto-sleep, Wake-on-LAN, and graceful shutdown
- **Orchestration**: Unified deployment workflow with progress tracking

## Quick Start

```bash
# Clone the repository
git clone https://github.com/jjbly-vmstation/cluster-setup.git
cd cluster-setup

# Run the full deployment
./orchestration/deploy-wrapper.sh

# Or use quick deploy for specific tasks
./orchestration/quick-deploy.sh setup     # Initial setup
./orchestration/quick-deploy.sh power     # Power management
./orchestration/quick-deploy.sh autosleep # Auto-sleep config
```


## Directory Structure

```
cluster-setup/
├── README.md                      # This file
├── IMPROVEMENTS_AND_STANDARDS.md  # Best practices and standards
├── bootstrap/                     # Bootstrap and preparation scripts
├── ansible/                       # Ansible configuration
├── power-management/              # Power management module
├── orchestration/                 # Deployment orchestration
├── systemd/                       # Systemd unit files
```

## Documentation

All detailed setup and power management documentation has been centralized in the [cluster-docs/components/](../cluster-docs/components/) directory. Please refer to that location for:
- Bootstrap guide
- Power management
- Autosleep configuration
- Wake-on-LAN setup

This repository only contains the README and improvements/standards documentation.

## Prerequisites

- Control node with Linux (Ubuntu 20.04+ recommended)
- Ansible 2.9+
- Python 3.8+
- SSH access to all cluster nodes
- Root or sudo privileges on target nodes

## Installation

### 1. Install Dependencies

```bash
./bootstrap/install-dependencies.sh
```

This installs:
- Ansible and collections
- Python 3 and pip
- SSH utilities
- Required system tools

### 2. Configure Inventory

Edit `ansible/inventory/hosts.yml`:

```yaml
all:
  vars:
    cluster_name: vmstation-cluster
    ansible_ssh_private_key_file: "~/.ssh/vmstation_cluster"
    
  children:
    masters:
      hosts:
        vmstation-master-01:
          ansible_host: 192.168.1.10
          
    workers:
      hosts:
        vmstation-worker-01:
          ansible_host: 192.168.1.11
        vmstation-worker-02:
          ansible_host: 192.168.1.12
```

### 3. Setup SSH Keys

```bash
./bootstrap/setup-ssh-keys.sh
```

### 4. Prepare Nodes

```bash
./bootstrap/prepare-nodes.sh
```

### 5. Verify Prerequisites

```bash
./bootstrap/verify-prerequisites.sh
```

### 6. Run Deployment

```bash
./orchestration/deploy-wrapper.sh
```

## Power Management

### Auto-Sleep

Nodes automatically sleep after configurable inactivity:

```bash
# Configure auto-sleep
./orchestration/quick-deploy.sh autosleep

# Control auto-sleep
vmstation-autosleep-ctl status
vmstation-autosleep-ctl disable
vmstation-autosleep-ctl enable
```

### Wake-on-LAN

Wake sleeping nodes remotely:

```bash
# Wake specific node
/opt/vmstation/power/vmstation-wake.sh worker-01

# Wake all nodes
/opt/vmstation/power/vmstation-wake.sh --all

# Using HTTP API
curl -X POST http://master:9876/wake/worker-01 \
  -H "X-Auth-Token: your-token"
```

### Cluster Shutdown

Gracefully spin down the cluster:

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  power-management/playbooks/spin-down-cluster.yml
```

## Configuration

### Auto-Sleep Settings

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
```

### Wake Handler

The wake event handler runs on port 9876:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/wake/<hostname>` | POST | Wake specific node |
| `/wake/all` | POST | Wake all nodes |
| `/status` | GET | Cluster power status |

## Documentation

- [Bootstrap Guide](docs/BOOTSTRAP_GUIDE.md) - Initial setup instructions
- [Power Management](docs/POWER_MANAGEMENT.md) - Power features overview
- [Auto-Sleep Configuration](docs/AUTOSLEEP_CONFIGURATION.md) - Detailed auto-sleep setup
- [Wake-on-LAN Setup](docs/WAKE_ON_LAN_SETUP.md) - WoL configuration guide
- [Improvements and Standards](IMPROVEMENTS_AND_STANDARDS.md) - Best practices

## Ansible Playbooks

| Playbook | Description |
|----------|-------------|
| `initial-setup.yml` | Initial cluster node setup |
| `setup-autosleep.yml` | Configure auto-sleep monitoring |
| `configure-power-management.yml` | Full power management setup |
| `deploy-event-wake.yml` | Deploy wake event handler |
| `setup-wake-on-lan.yml` | Configure Wake-on-LAN |
| `spin-down-cluster.yml` | Graceful cluster shutdown |

### Running Playbooks

```bash
# Check syntax
ansible-playbook playbooks/initial-setup.yml --syntax-check

# Dry run
ansible-playbook -i inventory/hosts.yml playbooks/initial-setup.yml --check

# Execute
ansible-playbook -i inventory/hosts.yml playbooks/initial-setup.yml

# With tags
ansible-playbook -i inventory/hosts.yml playbooks/initial-setup.yml --tags=packages
```

## Troubleshooting

### SSH Connection Issues

```bash
# Test SSH manually
ssh -i ~/.ssh/vmstation_cluster root@192.168.1.10

# Check Ansible connectivity
ansible -i ansible/inventory/hosts.yml all -m ping
```

### Auto-Sleep Not Working

```bash
# Check service status
systemctl status vmstation-autosleep.service

# View logs
journalctl -u vmstation-autosleep.service -f
```

### Wake-on-LAN Failures

```bash
# Verify WoL is enabled
ethtool eth0 | grep "Wake-on"

# Check wake handler
systemctl status vmstation-wake-event.service
```

## Contributing

Please read [IMPROVEMENTS_AND_STANDARDS.md](IMPROVEMENTS_AND_STANDARDS.md) for coding standards and contribution guidelines.

## License

See [LICENSE](LICENSE) file for details.

## Related Repositories

- [jjbly-vmstation/vmstation](https://github.com/jjbly-vmstation/vmstation) - Main VMStation project
