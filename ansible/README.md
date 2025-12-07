# Cluster-setup Ansible quick run

Run the pre-kubernetes bootstrap tasks from this directory to ensure `ansible.cfg` and relative paths resolve correctly.

Recommended commands (run from `cluster-setup/ansible`):

```bash
# Generate certs locally (bundled as a tarball)
ansible-playbook -i ./inventory/hosts.yml playbooks/pre-generate-certs.yml

# Copy pre-generated certs to control-plane and optionally run kubeadm init
ansible-playbook -i ./inventory/hosts.yml playbooks/bootstrap-control-plane.yml -e run_kubeadm_init=false
```

Validation and dry-run tips:

```bash
# Check syntax for playbooks
ansible-playbook --syntax-check -i ./inventory/hosts.yml playbooks/pre-generate-certs.yml
ansible-playbook --syntax-check -i ./inventory/hosts.yml playbooks/bootstrap-control-plane.yml

# Ensure kubectl/helm are on PATH before running identity handover (cluster-infra playbook)
command -v kubectl || echo "kubectl not found; ensure kubeconfig is present and kubectl installed"
command -v helm || echo "helm not found; install helm to manage in-cluster charts"
```

Notes:
- Always `cd` into this repo's `ansible/` directory before running these playbooks so `ansible.cfg` roles_path and inventory resolve correctly.
- The pre-generated certs are bootstrap-only. After the identity stack is up, import the CA into your identity provider and configure `cert-manager` to manage rotation.
