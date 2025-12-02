# VMStation Cluster Setup

This repository contains the complete cluster setup, initialization, and power management infrastructure for the VMStation project. It serves as the **central CI/CD orchestration repository** for the modular VMStation architecture.

## Features

- **Multi-Repo Orchestration**: Deploy across all modular VMStation repositories
- **Bootstrap Scripts**: Automated dependency installation and node preparation
- **Ansible Playbooks**: Idempotent cluster configuration and deployment
- **Power Management**: Auto-sleep, Wake-on-LAN, and graceful shutdown
- **Safety Controls**: Dry-run mode, confirmation prompts, automatic backups
- **Unified Logging**: Consistent logging across all deployment phases

## Quick Start

```bash
# Clone the repository
git clone https://github.com/jjbly-vmstation/cluster-setup.git
cd cluster-setup

# Full deployment (recommended for new clusters)
./orchestration/deploy.sh

# Or use specific commands
./orchestration/deploy.sh setup       # Initial setup only
./orchestration/deploy.sh kubespray   # Deploy Kubernetes
./orchestration/deploy.sh monitoring  # Deploy monitoring stack
./orchestration/deploy.sh validate    # Validate cluster health

# Dry-run mode (preview without changes)
./orchestration/deploy.sh --check
```

## Orchestration Commands

The main orchestration script (`orchestration/deploy.sh`) supports these commands:

| Command | Description |
|---------|-------------|
| `all` | Full deployment (all phases) |
| `debian` | Debian base setup |
| `kubespray` | Deploy Kubernetes via Kubespray |
| `monitoring` | Deploy monitoring stack (Prometheus, Grafana, Loki) |
| `infrastructure` | Deploy infrastructure services (NTP, Syslog) |
| `applications` | Deploy application stack (Jellyfin, etc.) |
| `reset` | Reset cluster |
| `setup` | Initial setup only |
| `spindown` | Graceful cluster shutdown |
| `validate` | Run validation suite |
| `status` | Show cluster status |

### Command Flags

| Flag | Description |
|------|-------------|
| `--yes`, `-y` | Skip confirmation prompts |
| `--check`, `--dry-run` | Validate without making changes |
| `--log-dir DIR` | Custom log directory |
| `--enable-autosleep` | Enable auto-sleep after deployment |
| `--offline` | Use local repositories only |
| `--phase N` | Start from phase N (1-5) |
| `--to-phase N` | Stop at phase N |
| `-v`, `--verbose` | Enable verbose output |

### Deployment Phases

1. **Infrastructure** (cluster-infra): Kubespray deployment, cluster health validation
2. **Configuration** (cluster-config): NTP, Syslog, system configurations
3. **Monitoring** (cluster-monitor-stack): Prometheus, Grafana, Loki
4. **Applications** (cluster-application-stack): Jellyfin and other apps
5. **Validation** (cluster-tools): Validation suite, deployment report

## Multi-Repo Workflow

The orchestration system manages deployments across these modular repositories:

```
cluster-setup (this repo)
├── Clones/updates modular repos to ~/.vmstation/repos/
│   ├── cluster-infra        → Kubespray & infrastructure
│   ├── cluster-config       → System configuration
│   ├── cluster-monitor-stack → Monitoring
│   ├── cluster-application-stack → Applications
│   └── cluster-tools        → Utilities & validation
└── Orchestrates deployment across all repos
```

### Offline Mode

If network is unavailable, use `--offline` to run with locally cached repositories:

```bash
./orchestration/deploy.sh --offline monitoring
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
│   ├── deploy.sh                  # Main orchestrator (multi-repo)
│   ├── reset.sh                   # Cluster reset
│   ├── validate.sh                # Validation suite
│   ├── deploy-wrapper.sh          # Legacy wrapper (single-repo)
│   ├── quick-deploy.sh            # Quick deployment helper
│   ├── lib/                       # Shared libraries
│   │   ├── common.sh              # Common functions
│   │   ├── logging.sh             # Logging utilities
│   │   └── safety.sh              # Safety controls
│   └── config/
│       └── defaults.env           # Default configuration
└── systemd/                       # Systemd unit files
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

Edit /srv/vmstation-org/cluster-setup/ansible/inventory/hosts.yml`:

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
# Full multi-repo deployment
./orchestration/deploy.sh

# Or use the legacy single-repo wrapper
./orchestration/deploy-wrapper.sh
```

## Safety Features

The orchestration system includes comprehensive safety controls:

### Dry-Run Mode
Preview all changes without executing:
```bash
./orchestration/deploy.sh --check
./orchestration/reset.sh --check
```

### Confirmation Prompts
Destructive operations require typed confirmation:
```bash
./orchestration/reset.sh --hard  # Requires typing "RESET"
./orchestration/reset.sh --full  # Requires typing "DESTROY"
```

### Safe Mode
Block all destructive operations:
```bash
export VMSTATION_SAFE_MODE=1
./orchestration/deploy.sh reset  # Will be blocked
```

### Auto-Yes Mode
Skip prompts for automation (use with caution):
```bash
./orchestration/deploy.sh --yes
# Or: export AUTO_YES=true
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `WORKSPACE_DIR` | Repository workspace | `~/.vmstation/repos` |
| `LOG_DIR` | Log directory | `~/.vmstation/logs` |
| `STATE_DIR` | State directory | `~/.vmstation/state` |
| `DRY_RUN` | Enable dry-run mode | `false` |
| `AUTO_YES` | Skip confirmations | `false` |
| `OFFLINE_MODE` | Use local repos only | `false` |
| `VMSTATION_SAFE_MODE` | Block destructive ops | `0` |

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
ansible-playbook -i /srv/vmstation-org/cluster-setup/ansible/inventory/hosts.yml \
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
ansible-playbook -i /srv/vmstation-org/cluster-setup/ansible/inventory/hosts.yml playbooks/initial-setup.yml --check

# Execute
ansible-playbook -i /srv/vmstation-org/cluster-setup/ansible/inventory/hosts.yml playbooks/initial-setup.yml

# With tags
ansible-playbook -i /srv/vmstation-org/cluster-setup/ansible/inventory/hosts.yml playbooks/initial-setup.yml --tags=packages
```

## Troubleshooting

### SSH Connection Issues

```bash
# Test SSH manually
ssh -i ~/.ssh/vmstation_cluster root@192.168.1.10

# Check Ansible connectivity
ansible -i /srv/vmstation-org/cluster-setup/ansible/inventory/hosts.yml all -m ping
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

### Deployment Issues

```bash
# Check deployment logs
ls -la ~/.vmstation/logs/

# View latest deployment log
tail -f ~/.vmstation/logs/deploy_*.log

# Run validation
./orchestration/validate.sh full

# Check cluster status
./orchestration/deploy.sh status
```

## Migration from Monorepo

If migrating from the legacy monorepo (`vmstation/deploy.sh`):

1. The new `orchestration/deploy.sh` preserves all original commands
2. Flags are compatible (`--yes`, `--check`, `--dry-run`, `--log-dir`, `--enable-autosleep`)
3. Multi-repo support is automatic - repos are cloned to `~/.vmstation/repos/`
4. Legacy single-repo workflows still work via `deploy-wrapper.sh`

### Key Differences

| Feature | Monorepo | Multi-Repo |
|---------|----------|------------|
| Script | `vmstation/deploy.sh` | `orchestration/deploy.sh` |
| Repos | Single repository | 5+ modular repos |
| Workspace | In-repo | `~/.vmstation/repos/` |
| State | `/tmp/` | `~/.vmstation/state/` |
| Logs | `artifacts/` | `~/.vmstation/logs/` |

## Contributing

Please read [IMPROVEMENTS_AND_STANDARDS.md](IMPROVEMENTS_AND_STANDARDS.md) for coding standards and contribution guidelines.

## License

See [LICENSE](LICENSE) file for details.

## Related Repositories

- [jjbly-vmstation/vmstation](https://github.com/jjbly-vmstation/vmstation) - Main VMStation project (legacy monorepo)
- [jjbly-vmstation/cluster-infra](https://github.com/jjbly-vmstation/cluster-infra) - Kubespray and infrastructure
- [jjbly-vmstation/cluster-config](https://github.com/jjbly-vmstation/cluster-config) - System configuration
- [jjbly-vmstation/cluster-monitor-stack](https://github.com/jjbly-vmstation/cluster-monitor-stack) - Monitoring stack
- [jjbly-vmstation/cluster-application-stack](https://github.com/jjbly-vmstation/cluster-application-stack) - Applications
- [jjbly-vmstation/cluster-tools](https://github.com/jjbly-vmstation/cluster-tools) - Utilities and tools
