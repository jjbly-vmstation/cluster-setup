#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="./certs"
CA_KEY="ca.key.pem"
CA_CERT="ca.cert.pem"

usage() {
  cat <<EOF
Usage: $0 [-o output_dir]

Generates a minimal CA and a few example certs for Kubernetes bootstrap:
 - CA (ca.key.pem, ca.cert.pem)
 - kube-apiserver server cert (kube-apiserver.key.pem, kube-apiserver.crt.pem)
 - admin client cert (admin.key.pem, admin.crt.pem)
 - kubelet client cert (kubelet.key.pem, kubelet.crt.pem)

Defaults to output under ./certs
EOF
}

while getopts ":o:h" opt; do
  case ${opt} in
    o ) OUT_DIR="$OPTARG" ;;
    h ) usage; exit 0 ;;
    \? ) echo "Invalid Option: -$OPTARG" 1>&2; usage; exit 1 ;;
  esac
done

mkdir -p "$OUT_DIR"
pushd "$OUT_DIR" >/dev/null

echo "Generating CA..."
if [ ! -f "$CA_KEY" ]; then
  openssl genrsa -out "$CA_KEY" 4096
fi

if [ ! -f "$CA_CERT" ]; then
  openssl req -x509 -new -nodes -key "$CA_KEY" -days 3650 -subj "/CN=vmstation-bootstrap-ca" -out "$CA_CERT"
fi

echo "Generating kube-apiserver key and CSR..."
KUBE_SRV_KEY="kube-apiserver.key.pem"
KUBE_SRV_CSR="kube-apiserver.csr.pem"
KUBE_SRV_CERT="kube-apiserver.crt.pem"

openssl genrsa -out "$KUBE_SRV_KEY" 2048

# Create a small openssl config for SANs
cat > kube-apiserver-openssl.cnf <<EOF
[ req ]
distinguished_name = req_distinguished_name
req_extensions = v3_req

[ req_distinguished_name ]

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kube-apiserver
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

openssl req -new -key "$KUBE_SRV_KEY" -subj "/CN=kube-apiserver" -out "$KUBE_SRV_CSR" -config kube-apiserver-openssl.cnf

echo "Signing kube-apiserver cert with CA..."
openssl x509 -req -in "$KUBE_SRV_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial -out "$KUBE_SRV_CERT" -days 365 -extensions v3_req -extfile kube-apiserver-openssl.cnf

echo "Generating admin client cert..."
ADMIN_KEY="admin.key.pem"
ADMIN_CSR="admin.csr.pem"
ADMIN_CERT="admin.crt.pem"
openssl genrsa -out "$ADMIN_KEY" 2048
openssl req -new -key "$ADMIN_KEY" -subj "/CN=admin/O=system:masters" -out "$ADMIN_CSR"
openssl x509 -req -in "$ADMIN_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial -out "$ADMIN_CERT" -days 365

echo "Generating kubelet client cert..."
KUBELET_KEY="kubelet.key.pem"
KUBELET_CSR="kubelet.csr.pem"
KUBELET_CERT="kubelet.crt.pem"
openssl genrsa -out "$KUBELET_KEY" 2048
openssl req -new -key "$KUBELET_KEY" -subj "/CN=system:node:example-node/O=system:nodes" -out "$KUBELET_CSR"
openssl x509 -req -in "$KUBELET_CSR" -CA "$CA_CERT" -CAkey "$CA_KEY" -CAcreateserial -out "$KUBELET_CERT" -days 365

echo "Cleaning temporary files..."
rm -f *.csr kube-apiserver-openssl.cnf *.srl

echo "Certificates created in: $(pwd)"
ls -l

popd >/dev/null

echo "Done. Upload certs to your secret store when ready."
