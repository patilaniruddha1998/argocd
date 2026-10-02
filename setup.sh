#!/usr/bin/env bash
set -euo pipefail

CLUSTER="my-kubernetes-cluster"

fail() { echo; echo "  SETUP STOPPED: $1"; echo; [ -n "${2:-}" ] && echo "  $2" && echo; exit 1; }

echo "==> 0/2  Preflight"

for c in docker kind kubectl; do
  command -v "$c" >/dev/null 2>&1 || fail "$c is not installed or not on PATH." \
    "Make sure Docker, Kind, and kubectl are installed and available on PATH."
done

if [ "$(type -a docker 2>/dev/null | wc -l)" -gt 1 ]; then
  echo "    NOTE: more than one docker binary is on your PATH -"
  type -a docker | sed 's/^/      /'
  echo "      The FIRST one wins. If the version check below fails, this may be why."
fi

DV="$(docker version --format '{{.Client.Version}}' 2>/dev/null)" \
  || fail "Docker is not running." \
  "Start Docker Desktop, wait for Docker to be ready, then re-run."

if [ "$(printf '%s\n20.10\n' "$DV" | sort -V | head -1)" != "20.10" ]; then
  fail "Your Docker CLI is $DV - Kind needs 20.10 or newer."
fi

MEM="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)"

if [ "$MEM" -lt 5500000000 ]; then
  echo "    WARNING: Docker has only $((MEM/1000000000)) GB of memory."
  echo "      Give Docker Desktop at least 6 GB of memory."
fi

echo "    preflight ok: docker $DV, kind $(kind version | awk '{print $2}')"

echo
echo "==> 1/2  Creating the 3-node kind cluster"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "    cluster '$CLUSTER' already exists, reusing it"
else
  kind create cluster --config kind-cluster.yaml
fi

kubectl cluster-info --context "kind-$CLUSTER" >/dev/null \
  || fail "The cluster exists but is not responding." \
  "Try: kind delete cluster --name $CLUSTER and then re-run this script."

echo
echo "==> 2/2  Verifying cluster"

echo
echo "    Nodes:"
kubectl get nodes --context "kind-$CLUSTER"

echo
echo "    Cluster:"
kubectl cluster-info --context "kind-$CLUSTER"

echo
echo "Done."
echo
echo "-------------------------------------------------------------"
echo "  Kind cluster: $CLUSTER"
echo "  Context:      kind-$CLUSTER"
echo "-------------------------------------------------------------"