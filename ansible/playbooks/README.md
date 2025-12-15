# VMStation Ansible Playbooks

This directory contains comprehensive Ansible playbooks for setting up, configuring, and validating the VMStation Kubernetes cluster.

## Core Infrastructure Playbooks

### 1. baseline-hardening.yml
**Purpose:** Establish baseline security, system requirements, and directory structure

**What it does:**
- Hardens SSH configuration (disable root login, key-based auth, strong ciphers)
- Creates system users and groups for monitoring services (prometheus, grafana, loki)
- Configures time synchronization with chrony/NTP
- Sets up Kubernetes system requirements (sysctl parameters, kernel modules)
- Installs base packages (curl, git, python3, vim, htop, etc.)
- Creates required directory structure (/opt/vmstation-org, /data/monitoring/*, /data/applications)
- Configures firewall (ufw for Ubuntu, firewalld for RHEL/Rocky)
- Hardens file permissions on sensitive files
- Disables unnecessary services

**Usage:**
```bash
# Run from ansible/ directory
ansible-playbook -i ../inventory/hosts.yml baseline-hardening.yml

# Dry run (check mode)
ansible-playbook -i ../inventory/hosts.yml baseline-hardening.yml --check

# Run specific tags
ansible-playbook -i ../inventory/hosts.yml baseline-hardening.yml --tags=ssh,firewall
```

**Available tags:**
- `ssh` - SSH configuration and hardening
- `users` - System users and groups
- `time` - Time synchronization
- `sysctl` - Kernel parameters
- `kernel` - Kernel modules
- `packages` - Package installation
- `directories` - Directory structure
- `firewall` - Firewall configuration
- `permissions` - File permissions
- `services` - Service management

### 2. infrastructure-services.yml
**Purpose:** Deploy and configure core infrastructure services

**What it does:**
- Configures DNS resolution (systemd-resolved or /etc/resolv.conf)
- Sets up system logging (rsyslog and journald)
- Installs and configures NFS client for storage
- Prepares monitoring stack (users, kernel modules, sysctl)
- Installs Helm and kubectl for application deployment
- Validates all services are running and enabled

**Usage:**
```bash
# Run from ansible/ directory
ansible-playbook -i ../inventory/hosts.yml infrastructure-services.yml

# Dry run
ansible-playbook -i ../inventory/hosts.yml infrastructure-services.yml --check

# Run specific tags
ansible-playbook -i ../inventory/hosts.yml infrastructure-services.yml --tags=dns,storage
```

**Available tags:**
- `ntp` - Time synchronization (if not configured in baseline)
- `dns` - DNS resolution configuration
- `logging` - System logging configuration
- `storage` - NFS and storage preparation
- `monitoring` - Monitoring stack preparation
- `applications` - Application stack preparation
- `validation` - Service validation

### 3. preflight-checks.yml
**Purpose:** Validate cluster readiness for Kubernetes deployment

**What it does:**
- Validates system requirements (OS, kernel, packages, resources)
- Checks SSH configuration and connectivity
- Tests network connectivity between nodes
- Verifies DNS resolution
- Checks time synchronization
- Validates directory structure and permissions
- Verifies kernel parameters and modules
- Checks service status
- Validates security hardening
- Generates comprehensive report

**Usage:**
```bash
# Run from ansible/ directory
ansible-playbook -i ../inventory/hosts.yml preflight-checks.yml

# Run specific checks
ansible-playbook -i ../inventory/hosts.yml preflight-checks.yml --tags=network,security

# View report
cat /tmp/preflight-report-*.txt
```

**Available tags:**
- `system` - System requirements checks
- `ssh` - SSH connectivity checks
- `network` - Network validation
- `time` - Time synchronization checks
- `filesystem` - Directory and filesystem checks
- `kernel` - Kernel and sysctl checks
- `services` - Service status checks
- `security` - Security validation
- `drift` - Configuration drift detection

**Report location:** `/tmp/preflight-report-<timestamp>.txt`

## Deployment Workflow

### Recommended Order

1. **Initial Hardening**
   ```bash
   ansible-playbook -i ../inventory/hosts.yml baseline-hardening.yml
   ```

2. **Infrastructure Services**
   ```bash
   ansible-playbook -i ../inventory/hosts.yml infrastructure-services.yml
   ```

3. **Validate Readiness**
   ```bash
   ansible-playbook -i ../inventory/hosts.yml preflight-checks.yml
   ```

4. **Deploy Kubernetes** (using Kubespray or other tools)

5. **Re-validate** (optional)
   ```bash
   ansible-playbook -i ../inventory/hosts.yml preflight-checks.yml
   ```

## Other Playbooks

### initial-setup.yml
Legacy initial setup playbook - provides basic system configuration. Consider using `baseline-hardening.yml` for new deployments.

### Power Management Playbooks

- `configure-power-management.yml` - Configure power management features
- `deploy-event-wake.yml` - Deploy wake event handler service
- `setup-autosleep.yml` - Configure auto-sleep monitoring

See [power-management documentation](../../power-management/README.md) for details.

## Configuration

### Inventory
All playbooks use the canonical inventory at `ansible/inventory/hosts.yml`. Ensure your inventory is properly configured before running playbooks.

### Variables
Playbooks include sensible defaults but can be customized by:
- Setting variables in inventory (`group_vars/all.yml`)
- Passing variables on command line: `--extra-vars "timezone=America/New_York"`
- Creating variable files and including them

### Example Variable Overrides

```bash
# Use different NTP servers
ansible-playbook -i ../inventory/hosts.yml baseline-hardening.yml \
  --extra-vars "ntp_servers=['time.nist.gov','time.google.com']"

# Use different timezone
ansible-playbook -i ../inventory/hosts.yml baseline-hardening.yml \
  --extra-vars "timezone=America/Los_Angeles"

# Configure NFS mounts
ansible-playbook -i ../inventory/hosts.yml infrastructure-services.yml \
  --extra-vars "nfs_mounts=[{path: '/mnt/storage', src: '192.168.1.100:/export/data', opts: 'defaults,noatime'}]"
```

## Requirements

### Ansible Control Node
- Ansible 2.9 or later
- Python 3.8+
- SSH access to all cluster nodes

### Target Nodes
- Ubuntu 22.04/24.04 or Rocky Linux 8/9
- SSH service running
- sudo privileges for the Ansible user
- Python 3 installed

### Ansible Collections
Some playbooks require additional Ansible collections:
```bash
ansible-galaxy collection install ansible.posix
ansible-galaxy collection install community.general
```

## Safety Features

- **Idempotent:** All playbooks are safe to run multiple times
- **Check Mode:** Use `--check` flag for dry-run validation
- **Handlers:** Services only restart when configuration changes
- **No Destructive Operations:** Playbooks never suspend, power off, or reboot nodes without explicit user action
- **Privilege Escalation:** Uses `become: yes` for privileged operations, never requires direct root SSH

## Troubleshooting

### SSH Connection Issues
```bash
# Test SSH manually
ssh -i ~/.ssh/id_ed25519 user@node-hostname

# Verify Ansible can connect
ansible -i ../inventory/hosts.yml all -m ping
```

### Syntax Check
```bash
ansible-playbook --syntax-check playbooks/baseline-hardening.yml
```

### Verbose Output
```bash
ansible-playbook -i ../inventory/hosts.yml baseline-hardening.yml -v
ansible-playbook -i ../inventory/hosts.yml baseline-hardening.yml -vvv  # More verbose
```

### View Facts
```bash
ansible -i ../inventory/hosts.yml all -m setup
```

## Integration with VMStation

These playbooks are designed to work seamlessly with:
- **Kubespray:** Kubernetes deployment via [cluster-infra](https://github.com/jjbly-vmstation/cluster-infra)
- **Monitoring Stack:** Prometheus/Grafana deployment via [cluster-monitor-stack](https://github.com/jjbly-vmstation/cluster-monitor-stack)
- **Application Stack:** Jellyfin and other apps via [cluster-application-stack](https://github.com/jjbly-vmstation/cluster-application-stack)
- **Orchestration:** Main deployment orchestrator at `orchestration/deploy.sh`

## Contributing

When modifying or adding playbooks:
1. Follow Ansible best practices
2. Use FQCN for modules (e.g., `ansible.builtin.copy`)
3. Include comprehensive comments
4. Add appropriate tags for selective execution
5. Support both Debian and RHEL families where applicable
6. Test with `--syntax-check` and `--check` before committing
7. Update this README with any new playbooks or significant changes

## References

- [Ansible Documentation](https://docs.ansible.com/)
- [VMStation Standards](../../IMPROVEMENTS_AND_STANDARDS.md)
- [Cluster Setup README](../../README.md)
