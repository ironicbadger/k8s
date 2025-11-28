# Flux/GitOps recipes
# Usage: just flux <command>
#
# For bare metal: export JUST_BM_CLUSTER=m720q
# For Proxmox: uses $cluster variable (default: homelab)

set shell := ["bash", "-euo", "pipefail", "-c"]

# Resolve cluster: JUST_BM_CLUSTER takes precedence, then $cluster
_cluster := env_var_or_default("JUST_BM_CLUSTER", env_var_or_default("cluster", "homelab"))

# Bootstrap Flux GitOps (optionally specify branch, defaults to main)
[no-cd]
bootstrap branch="main":
    #!/usr/bin/env bash
    set -euo pipefail
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    export KUBECONFIG

    # Wait for API server
    echo "Waiting for Kubernetes API..."
    until kubectl get nodes &>/dev/null; do
        sleep 2
    done

    # Wait for kube-system pods
    echo "Waiting for kube-system pods..."
    kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=120s

    # Create flux-system namespace if it doesn't exist (for sops-age secret)
    kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

    # Create SOPS Age secret for decryption (before bootstrap so Flux can decrypt immediately)
    if ! kubectl get secret sops-age -n flux-system &>/dev/null; then
        AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
        if [[ -f "${AGE_KEY_FILE}" ]]; then
            echo "Creating sops-age secret from ${AGE_KEY_FILE}..."
            kubectl create secret generic sops-age \
                --namespace=flux-system \
                --from-file=age.agekey="${AGE_KEY_FILE}"
        else
            echo ""
            echo "Warning: Age key not found at ${AGE_KEY_FILE}"
            echo "Set SOPS_AGE_KEY_FILE or create the secret manually:"
            echo "  kubectl create secret generic sops-age -n flux-system --from-file=age.agekey=<path>"
        fi
    else
        echo "sops-age secret already exists"
    fi

    if ! gh auth status &>/dev/null; then
        echo "Error: gh CLI not authenticated. Run: gh auth login"
        exit 1
    fi
    export GITHUB_TOKEN=$(gh auth token)
    echo "Bootstrapping Flux on branch: {{branch}}"
    flux bootstrap github \
      --owner=ironicbadger \
      --repository=k8s \
      --branch={{branch}} \
      --path=clusters/${CLUSTER} \
      --personal \
      --timeout=2m

# Show Flux status
[no-cd]
status:
    #!/usr/bin/env bash
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    KUBECONFIG="${KUBECONFIG}" flux get all -A

# Uninstall Flux
[no-cd]
uninstall:
    #!/usr/bin/env bash
    CLUSTER="{{_cluster}}"
    KUBECONFIG="clusters/${CLUSTER}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found for cluster '${CLUSTER}'"
        exit 1
    fi
    KUBECONFIG="${KUBECONFIG}" flux uninstall
