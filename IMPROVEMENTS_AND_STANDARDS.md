# Improvements and Standards

This document outlines the best practices, improvements implemented during migration, and recommendations for future enhancements of the VMStation cluster setup and power management system.

## Already Implemented Improvements

### Ansible Best Practices

#### Fully Qualified Collection Names (FQCN)
All playbooks use FQCN for modules to ensure compatibility and avoid ambiguity:

```yaml
# Before (legacy)
- name: Install packages
  apt:
    name: package

# After (implemented)
- name: Install packages
  ansible.builtin.apt:
    name: package
```

#### Proper Module Usage
- `ansible.builtin.apt` for Debian/Ubuntu packages
- `ansible.builtin.yum` for RedHat/CentOS packages
- `ansible.posix.sysctl` for kernel parameters
- `community.general.timezone` for timezone configuration
- `ansible.builtin.systemd` for service management

#### Error Handling
- Implemented `failed_when` conditions
- Added `changed_when` for command modules
- Used `ignore_errors` sparingly with logging

#### Check Mode Support
All playbooks support `--check` for dry-run execution:
```bash
ansible-playbook playbook.yml --check
```

### Bootstrap Scripts

#### Idempotent Operations
All bootstrap scripts are idempotent:
- Check before installation
- Skip already-completed steps
- State tracking in files

```bash
# Example from install-dependencies.sh
if step_completed "cache_updated" || [[ "$FORCE_INSTALL" == "true" ]]; then
    update_package_cache
    save_state "cache_updated"
fi
```

#### Multi-Package Manager Support
Scripts detect and use the appropriate package manager:
- apt (Debian/Ubuntu)
- dnf (Fedora, RHEL 8+)
- yum (CentOS, RHEL 7)

#### Version Checking
Critical tools are version-checked:
```bash
MIN_VERSIONS=(
    ["ansible"]="2.9.0"
    ["python3"]="3.8.0"
)
```

#### Rollback Capability
Installation can be reversed:
```bash
./install-dependencies.sh --rollback
```

### Power Management

#### Comprehensive Activity Detection
Auto-sleep monitors multiple indicators:
1. Kubernetes pod activity
2. CPU utilization
3. Network traffic
4. SSH sessions

#### Grace Periods
Configurable grace period before sleep to:
- Allow notification
- Handle transient activity
- Prevent premature sleep

#### Pre-Sleep Hooks
Custom scripts can run before sleep:
```bash
/opt/vmstation/autosleep/pre-sleep.d/01-custom.sh
```

#### Wake Verification
WoL includes retry and verification:
```bash
vmstation-wake.sh --verify worker-01
```

### Systemd Integration

#### Proper Service Configuration
- Type: simple/oneshot as appropriate
- Restart policies configured
- Dependencies declared (After=, Wants=)
- Resource limits (MemoryMax, CPUQuota)

#### Security Hardening
```ini
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
```

#### Logging Integration
- Journal output (StandardOutput=journal)
- Syslog identifiers
- Log rotation via journal

### Configuration Management

#### Externalized Configuration
All configuration in external files:
- `/etc/vmstation/autosleep/autosleep.conf`
- `/etc/vmstation/power/power.conf`
- Environment variable overrides

#### Templates
Jinja2 templates for flexibility:
```yaml
- name: Deploy configuration
  ansible.builtin.template:
    src: autosleep.conf.j2
    dest: /etc/vmstation/autosleep/autosleep.conf
```

## Coding Standards

### Bash Scripts

```bash
#!/bin/bash
set -euo pipefail  # Strict error handling

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Always include usage/help
print_usage() { ... }

# Proper argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_usage; exit 0 ;;
        *) log_error "Unknown option"; exit 1 ;;
    esac
done
```

### Ansible Playbooks

```yaml
---
# playbook.yml - Description
# Part of VMStation Cluster Setup
#
# Usage:
#   ansible-playbook playbook.yml

- name: Descriptive Play Name
  hosts: target_group
  become: true
  gather_facts: true
  
  vars:
    config_option: "{{ variable | default('default_value') }}"
    
  handlers:
    - name: Restart service
      ansible.builtin.systemd:
        name: myservice
        state: restarted
        
  tasks:
    - name: Clear task description
      ansible.builtin.module:
        param: value
      tags:
        - tag_name
```

### Directory Structure

```
project/
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/
│   └── playbooks/
├── bootstrap/
├── docs/
├── orchestration/
├── power-management/
│   ├── playbooks/
│   ├── scripts/
│   └── templates/
└── systemd/
```

## Recommended Future Enhancements

### High Priority

#### 1. Auto-Scaling Based on Demand
Implement automatic node wake/sleep based on workload:
```yaml
# Concept
when: pending_pods > 0 and sleeping_nodes > 0
action: wake_node
```

#### 2. Scheduled Cluster Scaling
Support time-based scaling:
- Wake all nodes at 8 AM
- Allow sleep after 6 PM
- Weekend configurations

#### 3. Power Consumption Monitoring
Track and report power usage:
- Per-node metrics
- Total cluster consumption
- Cost estimation

### Medium Priority

#### 4. Cloud Provider Integration
Support hybrid deployments:
- AWS instance start/stop
- Azure VM power management
- GCP instance scheduling

#### 5. Predictive Wake Scheduling
Use historical data to:
- Pre-wake nodes before typical usage
- Predict workload patterns
- Optimize wake timing

#### 6. Progressive Shutdown (Tiers)
Implement tiered shutdown:
1. Development nodes first
2. Then staging
3. Production last
4. Critical nodes never

#### 7. Wake Verification Tests
Automated periodic testing:
- Test WoL weekly
- Verify all nodes can wake
- Alert on failures

### Low Priority

#### 8. UPS Integration
Connect with UPS systems for:
- Power failure handling
- Battery-aware decisions
- Graceful shutdown triggers

#### 9. Climate Control Integration
For data center environments:
- Temperature-aware scheduling
- Cooling optimization
- Heat-based node distribution

#### 10. Intelligent Workload Migration
Before sleep:
- Migrate pods to active nodes
- Preserve stateful workloads
- Minimize disruption

### Future Architecture Improvements

#### Centralized Power Controller
```
┌───────────────────┐
│  Power Controller │
│  (Central API)    │
├───────────────────┤
│ - Node registry   │
│ - Wake scheduling │
│ - State tracking  │
│ - Analytics       │
└───────────────────┘
        │
        ├── Wake-on-LAN
        ├── IPMI/BMC
        └── Cloud APIs
```

#### Event-Driven Wake
```yaml
# Kubernetes-aware wake triggers
on:
  - pending_pods_increase
  - scheduled_job_start
  - external_webhook
  - api_request
```

## Security Recommendations

### Authentication
- Always enable auth token for wake API
- Rotate tokens periodically
- Use TLS for API endpoints

### Network Segmentation
- Isolate management network
- Restrict WoL to specific subnets
- Monitor wake events

### Audit Logging
- Log all wake/sleep events
- Track who triggered actions
- Retain logs for compliance

## Performance Considerations

### Wake Latency
- Optimize BIOS boot settings
- Consider fast boot options
- Pre-configure network during boot

### Check Interval Tuning
- Balance responsiveness vs overhead
- 5-minute default is reasonable
- Adjust based on workload patterns

### Network Efficiency
- Batch wake operations
- Use broadcast wisely
- Consider directed wake for large clusters

## Documentation Standards

### Playbook Documentation
Each playbook should include:
1. Purpose description
2. Usage examples
3. Variable reference
4. Prerequisites

### Script Documentation
Each script should include:
1. Header with description
2. Usage/help function
3. Example commands
4. Exit codes

### README Files
Each directory should have README with:
1. Purpose of the directory
2. File descriptions
3. Usage instructions
4. Related documentation links

## Testing Requirements

### Playbook Testing
- Syntax check: `ansible-playbook --syntax-check`
- Dry run: `ansible-playbook --check`
- Molecule tests (recommended)

### Script Testing
- ShellCheck validation
- Unit tests for functions
- Integration tests

### End-to-End Testing
- Full deployment in test environment
- Power cycle testing
- Failure scenario testing

## Version Compatibility

### Supported Platforms
- Ubuntu 20.04, 22.04
- Debian 11, 12
- CentOS 8, 9
- Rocky Linux 8, 9
- RHEL 8, 9

### Required Versions
- Ansible 2.9+
- Python 3.8+
- Kubernetes 1.24+

## Contributing Guidelines

### Code Review Checklist
- [ ] FQCN for all Ansible modules
- [ ] Idempotent operations
- [ ] Error handling
- [ ] Documentation updated
- [ ] Tests added/updated
- [ ] ShellCheck passes
- [ ] ansible-lint passes

### Commit Messages
```
type(scope): description

- Detail 1
- Detail 2

Closes #issue
```

Types: feat, fix, docs, style, refactor, test, chore
