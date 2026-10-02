
# Create namespace
```
kubectl create namespace argocd
```
# Install ArgoCD
```
kubectl apply --server-side -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

# Enable SSO 
```
https://console.cloud.google.com/projectselector2/apis/credentials?pli=1&supportedpurview=project -> Create a Project -> Create Credentails -> Oauth Client ID -> Create Consent 

Create Oauth Client ID -> Web application -> Java Script Origin: http://localhost:8080 ->  Authorized Redirect URL. http://localhost:8080/api/dex/callback


kubectl edit configmap argocd-cm -n argocd 

data:
  url: http://localhost:8080

  dex.config: |
    connectors:
    - type: oidc
      id: google
      name: Google
      config:
        issuer: https://accounts.google.com
        clientID: <YOUR_CLIENT_ID>
        clientSecret: <YOUR_CLIENT_SECRET>
        redirectURI: http://localhost:8080/api/dex/callback
        scopes:
        - openid
        - profile
        - email
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart deployment argocd-dex-server -n argocd
```
# Allow Insecure argo url to allow http login 
```
 kubectl patch deployment argocd-server -n argocd \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"argocd-server","args":["argocd-server","--insecure"]}]}}}}'

kubectl port-forward svc/argocd-server -n argocd 8080:443


kubectl create secret generic argocd-repo-argocd \
  -n argocd \
  --from-literal=type=git \
  --from-literal=url=https://github.com/patilaniruddha1998/argocd.git \
  --from-literal=username=patilaniruddha1998 \
  --from-literal=password=''


  kubectl label secret argocd-repo-argocd \
  -n argocd \
  argocd.argoproj.io/secret-type=repository
```
#  kubectl edit configmap argocd-cm -n argocd
```
   policy.csv: |
    g, your-email@gmail.com, role:admin 
```
# Expose ArgoCD server (for testing)
```
kubectl port-forward svc/argocd-server -n argocd 8080:443

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

## Create Git Repo 
```

Argo UI -> Settings -> Repositories ->  Connect Repo -> type: git , Repo: https://github.com/Lavanya-Balaji/k8s_terraform_mc, User Name and Password PAT Token -> Success 


https://github.com/Lavanya-Balaji/k8s_terraform_mc
```

## HELM Repo:
```
Repo: https://charts.bitnami.com/bitnami

chart: nginx-ingress-controller

```

### OCI Repo: 


# Install cert Manager, Ingress , MetaLB

```
kubectl apply -f cert-manager.yaml 
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

kubectl apply -f metalb.yaml

kubectl apply -f clusterissuer.yaml
kubectl apply -f ingress-with-tls.yaml
kubectl apply -f ingress-test-app.yaml
docker exec -it argo-control-plane /bin/sh
curl -k https://myapp.172.18.255.200.nip.io -> Accessing an application with https 

```

## Deploy kyverno App 

```
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  --set replicaCount=2
```

## Validate Kyverno policy 

```
kubectl apply -f validate-kyverno-policy.yaml

```# argocd
