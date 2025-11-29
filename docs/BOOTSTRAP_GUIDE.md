# VMStation Bootstrap Guide

This guide covers the initial setup and bootstrapping process for VMStation cluster nodes.

## Overview

The bootstrap process prepares nodes for cluster deployment by:
- Installing required dependencies
- Configuring SSH access
- Preparing system settings
- Validating prerequisites

## Prerequisites

Before starting the bootstrap process, ensure you have:

- A control node with Linux (Ubuntu 20.04+ or similar)
- Root or sudo access on all nodes
- Network connectivity between all nodes
- Python 3.8+ on all nodes

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/jjbly-vmstation/cluster-setup.git
cd cluster-setup

# 2. Install dependencies
./bootstrap/install-dependencies.sh

# 3. Configure SSH keys
./bootstrap/setup-ssh-keys.sh

# 4. Prepare nodes
./bootstrap/prepare-nodes.sh

# 5. Verify prerequisites
./bootstrap/verify-prerequisites.sh
```

## Step-by-Step Guide

### 1. Install Dependencies

The `install-dependencies.sh` script installs required packages on the control node.

```bash
./bootstrap/install-dependencies.sh
```

**Features:**
- Automatic package manager detection (apt, dnf, yum)
- Version checking for critical tools
- Idempotent operations (safe to run multiple times)
- Rollback capability

**Options:**
```bash
./bootstrap/install-dependencies.sh --help
./bootstrap/install-dependencies.sh --force      # Force reinstall
./bootstrap/install-dependencies.sh --dry-run    # Preview changes
./bootstrap/install-dependencies.sh --rollback   # Undo installations
```

**Required Packages:**
- ansible
- python3 (3.8+)
- python3-pip
- curl, wget
- jq
- sshpass
- git

### 2. Configure SSH Keys

The `setup-ssh-keys.sh` script configures SSH key-based authentication.

```bash
./bootstrap/setup-ssh-keys.sh
```

**Features:**
- Generates ED25519 SSH key pair
- Distributes keys to cluster nodes
- Configures SSH client for easy access
- Validates connectivity

**Options:**
```bash
./bootstrap/setup-ssh-keys.sh generate      # Only generate key
./bootstrap/setup-ssh-keys.sh distribute    # Distribute to nodes
./bootstrap/setup-ssh-keys.sh validate      # Validate connectivity
./bootstrap/setup-ssh-keys.sh interactive   # Interactive mode
```

**Environment Variables:**
```bash
SSH_KEY_PATH=~/.ssh/vmstation_cluster
SSH_KEY_TYPE=ed25519
INVENTORY_FILE=ansible/inventory/hosts.yml
```

### 3. Prepare Nodes

The `prepare-nodes.sh` script prepares cluster nodes for deployment.

```bash
./bootstrap/prepare-nodes.sh
```

**What it does:**
- Updates system packages
- Configures hostnames
- Sets up kernel parameters for Kubernetes
- Disables swap
- Configures firewall rules
- Installs container runtime prerequisites

**Options:**
```bash
./bootstrap/prepare-nodes.sh --dry-run           # Preview changes
./bootstrap/prepare-nodes.sh --user admin        # Specify SSH user
./bootstrap/prepare-nodes.sh 192.168.1.10        # Prepare specific host
```

### 4. Verify Prerequisites

The `verify-prerequisites.sh` script validates the setup.

```bash
./bootstrap/verify-prerequisites.sh
```

**Checks performed:**
- Local tool availability
- SSH key configuration
- Inventory file validation
- Network connectivity
- Remote system requirements
- Ansible connectivity

**Options:**
```bash
./bootstrap/verify-prerequisites.sh --local-only  # Only local checks
./bootstrap/verify-prerequisites.sh --report /tmp/report.txt
```

## Inventory Configuration

Edit `ansible/inventory/hosts.yml` to define your cluster:

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

## Troubleshooting

### SSH Connection Issues

```bash
# Test SSH manually
ssh -i ~/.ssh/vmstation_cluster root@192.168.1.10

# Enable SSH debug mode
ssh -vvv -i ~/.ssh/vmstation_cluster root@192.168.1.10
```

### Package Installation Failures

```bash
# Force reinstall
./bootstrap/install-dependencies.sh --force

# Check package manager
which apt-get dnf yum
```

### Ansible Connectivity

```bash
# Test Ansible ping
ansible -i ansible/inventory/hosts.yml all -m ping

# Check Ansible configuration
ansible-config dump
```

## Best Practices

1. **Always run verification** after bootstrap to catch issues early
2. **Use dry-run mode** first to preview changes
3. **Backup SSH keys** securely
4. **Version control** your inventory file
5. **Test on a single node** before running on all nodes

## Next Steps

After successful bootstrap:
1. Run the initial setup playbook
2. Configure power management
3. Deploy auto-sleep monitoring
4. Set up wake event handler

See [README.md](../README.md) for the complete deployment process.
