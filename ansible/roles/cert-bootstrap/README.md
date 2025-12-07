# cert-bootstrap role

This role is a placeholder for distributing pre-generated certificates to control-plane hosts or uploading them to a secret storage backend (Vault, S3, Kubernetes Secret) once those services are available.

Planned responsibilities:
- Validate and import artifacts produced by `cluster-setup/scripts/generate_certs.sh`.
- Upload to secret store (Vault / S3) or create temporary files on control-plane hosts.
- Rotate or revoke certificates if requested.

For now this role is a stub. Implementation will follow once an operator has chosen a secret backend.
