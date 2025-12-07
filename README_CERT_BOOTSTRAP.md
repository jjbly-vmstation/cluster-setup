# Pre-generate Kubernetes Bootstrap Certificates

This folder contains tooling to pre-generate the certificates required to bootstrap Kubernetes control-plane components prior to bringing up a secret store.

What it does:
- `ansible/playbooks/pre-generate-certs.yml` — runs the local script and bundles output.
- `scripts/generate_certs.sh` — OpenSSL-based CA + example kube server/client certs.
- `ansible/roles/cert-bootstrap` — role stub for future distribution or secret-store handoff.

Recommended workflow:
1. From your deployment host run:
   ```bash
   cd /opt/vmstation-org/cluster-setup
   ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/pre-generate-certs.yml
   ```
2. Inspect `cluster-setup/scripts/certs` (or the tarball) and upload the artifacts into your chosen secret store (Vault, S3, etc.).
3. After secret-store is available, implement `ansible/roles/cert-bootstrap` to automate the handoff and distribution.

Notes:
- The generated certs are minimal examples intended to unblock bootstrap and may require customization for production SANs and lifetimes.
