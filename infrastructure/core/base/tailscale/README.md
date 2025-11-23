# Tailscale Operator

The Tailscale Kubernetes operator enables secure service exposure and networking integration with your Tailscale network.

## Features Enabled

- **Cluster Ingress**: Expose Kubernetes services to your Tailscale network
- **Cluster Egress**: Access Tailscale services from within the cluster
- **API Server Proxy**: Secure kubectl access via Tailscale
- **Subnet Router**: Route cluster network traffic through Tailscale

## Prerequisites

- Tailscale OAuth client created with:
  - Scopes: `devices:core` (write), `auth_keys` (write)
  - Tags: `tag:k8s-operator`
- OAuth credentials stored in encrypted secret (see overlays)

## Usage Examples

### 1. Expose Service via LoadBalancer

Use the `tailscale` LoadBalancer class to expose a service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: default
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  selector:
    app: my-app
```

The service will be accessible at `https://my-app.tail-scale.ts.net` (MagicDNS).

### 2. Expose Service via Annotation

For simpler exposure without changing the service type:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: default
  annotations:
    tailscale.com/expose: "true"
spec:
  ports:
    - port: 80
      targetPort: 8080
  selector:
    app: my-app
```

### 3. Expose Service via Ingress

Use Tailscale as an ingress controller:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
spec:
  ingressClassName: tailscale
  defaultBackend:
    service:
      name: my-app
      port:
        number: 80
  tls:
    - hosts:
        - my-app
```

**Note**: When using Tailscale Ingress, the operator handles TLS termination automatically using Let's Encrypt. Traditional ingress controllers like ingress-nginx are bypassed.

### 4. Access Tailnet Services from Cluster (Egress)

Create a service that points to an external Tailscale device:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-database
  namespace: default
  annotations:
    tailscale.com/tailnet-fqdn: "database.tail-scale.ts.net"
spec:
  externalName: placeholder
  type: ExternalName
  ports:
    - port: 5432
      targetPort: 5432
      protocol: TCP
```

Pods can now access `external-database:5432` to reach the Tailscale device.

### 5. Deploy Subnet Router

Route cluster network traffic through Tailscale:

```yaml
apiVersion: tailscale.com/v1alpha1
kind: Connector
metadata:
  name: subnet-router
  namespace: default
spec:
  subnetRouter:
    advertiseRoutes:
      - "10.96.0.0/12"   # Kubernetes service CIDR
      - "10.244.0.0/16"  # Pod CIDR (adjust for your cluster)
```

After deployment, approve the routes in the Tailscale admin console.

### 6. API Server Proxy

Enable secure kubectl access via Tailscale (already configured in HelmRelease):

The operator is configured with `apiServerProxyConfig.mode: "noauth"`, which creates a proxy to the Kubernetes API server.

To use:

1. Find the Tailscale hostname for the proxy:
   ```bash
   kubectl get svc -n tailscale
   ```

2. Update your kubeconfig to use the Tailscale proxy:
   ```bash
   kubectl config set-cluster homelab-tailscale \
     --server=https://<tailscale-hostname>:443 \
     --insecure-skip-tls-verify=false
   ```

### 7. Customize Proxy Pods with ProxyClass

Create a ProxyClass to customize operator-created proxy pods:

```yaml
apiVersion: tailscale.com/v1alpha1
kind: ProxyClass
metadata:
  name: custom-proxy
spec:
  statefulSet:
    labels:
      monitoring: enabled
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "9001"

  # Enable Prometheus metrics
  metrics:
    enable: true

  # TLS configuration
  tailscale:
    useLetsEncryptStagingEnvironment: false
```

Apply to a service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: monitored-app
  labels:
    tailscale.com/proxy-class: custom-proxy
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
  ports:
    - port: 80
```

## Service Exposure Strategy

### When to Use Tailscale Ingress

✅ **Good for:**
- Simple service exposure to private Tailscale network
- Services that don't need complex routing rules
- Quick secure access without public exposure
- Automatic HTTPS with Let's Encrypt

❌ **Not ideal for:**
- Complex routing, rewrite rules, or middleware
- Rate limiting, authentication plugins
- Services requiring traditional ingress controller features

### When to Use ingress-nginx + Tailscale

For complex routing needs, expose ingress-nginx to Tailscale instead:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-tailscale
  namespace: ingress-nginx
  annotations:
    tailscale.com/expose: "true"
spec:
  type: LoadBalancer
  loadBalancerClass: tailscale
  ports:
    - port: 443
      targetPort: 443
  selector:
    app.kubernetes.io/name: ingress-nginx
```

Then route all ingress traffic through the Tailscale-exposed nginx.

## Security Considerations

1. **Access Control**: Use Tailscale ACLs to control which devices can access exposed services
2. **Tags**: All operator-created devices use `tag:k8s-operator` for easy ACL management
3. **OAuth Credentials**: Stored in SOPS-encrypted secrets (see overlays)
4. **TLS**: Automatic Let's Encrypt certificates for ingress services
5. **Network Policies**: Consider Kubernetes NetworkPolicies for defense in depth

## Troubleshooting

### Check Operator Status

```bash
# Check operator pod
kubectl get pods -n tailscale

# View operator logs
kubectl logs -n tailscale -l app=tailscale-operator

# Check HelmRelease status
kubectl get helmrelease -n tailscale
flux get helmreleases -n tailscale
```

### Check Exposed Services

```bash
# List all Tailscale devices created by operator
# (Check in Tailscale admin console or via CLI)
tailscale status

# Check service in cluster
kubectl get svc <service-name> -o yaml
```

### Common Issues

**Service not appearing in Tailscale:**
- Verify OAuth credentials are correct
- Check operator logs for authentication errors
- Ensure tags are configured in OAuth client settings

**Cannot access exposed service:**
- Verify Tailscale ACLs allow access
- Check that MagicDNS is enabled in Tailscale settings
- Ensure the service selector matches running pods

**Operator pod crashlooping:**
- Check OAuth secret exists and is not corrupted
- Verify SOPS decryption is working
- Review HelmRelease status for configuration errors

## References

- [Tailscale Kubernetes Operator Documentation](https://tailscale.com/kb/1236/kubernetes-operator)
- [Cluster Ingress Guide](https://tailscale.com/kb/1439/kubernetes-operator-cluster-ingress)
- [Cluster Egress Guide](https://tailscale.com/kb/1438/kubernetes-operator-cluster-egress)
- [API Server Proxy](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy)
- [ProxyClass Customization](https://tailscale.com/kb/1445/kubernetes-operator-customization)
