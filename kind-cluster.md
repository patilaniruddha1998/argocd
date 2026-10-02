# Kind Kubernetes Cluster Setup

This project creates a **3-node Kubernetes cluster using Kind (Kubernetes IN Docker)**.

## Cluster Architecture

The cluster contains:

- 1 Control Plane node
- 2 Worker nodes

```text
                    Kubernetes Cluster
                 my-kubernetes-cluster
                         │
          ┌──────────────┼──────────────┐
          │              │              │
          ▼              ▼              ▼
   Control Plane      Worker 1       Worker 2
```

## Prerequisites

Make sure the following tools are installed and available in your `PATH`:

- Docker
- Kind
- kubectl

Verify them:

```bash
docker --version
kind version
kubectl version --client
```

Also make sure **Docker Desktop is running**.

## Project Structure

Your directory should look like:

```text
.
├── kind-cluster.yaml
├── setup.sh
└── README.md
```

Where:

- `setup.sh` → Creates and verifies the Kind cluster
- `kind-cluster.yaml` → Kind cluster configuration
- `README.md` → Documentation

## Kind Cluster Configuration

The `kind-cluster.yaml` file contains:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4

name: my-kubernetes-cluster

nodes:
  - role: control-plane
  - role: worker
  - role: worker
```

This creates:

```text
my-kubernetes-cluster
│
├── control-plane
├── worker
└── worker
```

## Run the Setup

### 1. Make the script executable

```bash
chmod +x setup.sh
```

### 2. Run the script

```bash
./setup.sh
```

The script will:

1. Check Docker, Kind, and kubectl.
2. Verify that Docker is running.
3. Check the Docker CLI version.
4. Check available Docker memory.
5. Create the 3-node Kind cluster.
6. Verify the Kubernetes cluster.
7. Display the cluster nodes.

## Verify the Cluster

### Check Kind clusters

```bash
kind get clusters
```

Expected:

```text
my-kubernetes-cluster
```

### Check Kubernetes context

Kind automatically creates the kubectl context:

```text
kind-my-kubernetes-cluster
```

Check it:

```bash
kubectl config get-contexts
```

### Check current context

```bash
kubectl config current-context
```

Expected:

```text
kind-my-kubernetes-cluster
```

### Check nodes

```bash
kubectl get nodes
```

Expected output will look similar to:

```text
NAME                               STATUS   ROLES           AGE
my-kubernetes-cluster-control-plane Ready    control-plane   1m
my-kubernetes-cluster-worker        Ready   <none>          1m
my-kubernetes-cluster-worker2       Ready   <none>          1m
```

The exact node names can vary slightly depending on the Kind configuration/version.

### Check cluster information

```bash
kubectl cluster-info --context kind-my-kubernetes-cluster
```

## Useful Commands

### List Kind clusters

```bash
kind get clusters
```

### Check Kubernetes nodes

```bash
kubectl get nodes -o wide
```

### Check all namespaces

```bash
kubectl get namespaces
```

### Check system pods

```bash
kubectl get pods -n kube-system
```

### Check Docker containers created by Kind

```bash
docker ps
```

You should see containers corresponding to:

```text
my-kubernetes-cluster-control-plane
my-kubernetes-cluster-worker
my-kubernetes-cluster-worker2
```

## Delete the Cluster

To delete the entire Kind cluster:

```bash
kind delete cluster --name my-kubernetes-cluster
```

Verify:

```bash
kind get clusters
```

The cluster should no longer appear.

## Recreate the Cluster

If you want to start from scratch:

```bash
kind delete cluster --name my-kubernetes-cluster
./setup.sh
```

## Troubleshooting

### Docker is not running

If you see:

```text
Docker is not running
```

Start Docker Desktop and run:

```bash
docker info
```

Then run:

```bash
./setup.sh
```

### Cluster already exists

The script detects an existing cluster:

```text
cluster 'my-kubernetes-cluster' already exists, reusing it
```

You can continue using the existing cluster.

If you want a fresh cluster:

```bash
kind delete cluster --name my-kubernetes-cluster
./setup.sh
```

### Check the cluster context

If kubectl is pointing to another cluster:

```bash
kubectl config current-context
```

Switch to the Kind cluster:

```bash
kubectl config use-context kind-my-kubernetes-cluster
```

Then:

```bash
kubectl get nodes
```

## Quick Start

For a fresh setup:

```bash
chmod +x setup.sh

./setup.sh

kubectl get nodes
```

To remove it:

```bash
kind delete cluster --name my-kubernetes-cluster
```

## Summary

| Component | Configuration |
|---|---|
| Cluster | `my-kubernetes-cluster` |
| Kubernetes | Kind |
| Control Plane | 1 |
| Workers | 2 |
| Total Nodes | 3 |
| kubectl Context | `kind-my-kubernetes-cluster` |
| Container Runtime | Docker |