# Flux/GitOps recipes

set shell := ["bash", "-euo", "pipefail", "-c"]

# Bootstrap Flux GitOps
[no-cd]
bootstrap:
    #!/usr/bin/env bash
    set -euo pipefail
    KUBECONFIG="clusters/${cluster}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found. Run: just c bootstrap"
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

    if ! gh auth status &>/dev/null; then
        echo "Error: gh CLI not authenticated. Run: gh auth login"
        exit 1
    fi
    export GITHUB_TOKEN=$(gh auth token)
    flux bootstrap github \
      --owner=ironicbadger \
      --repository=k8s \
      --branch=main \
      --path=clusters/${cluster} \
      --personal \
      --timeout=2m

    # Create SOPS Age secret for decryption
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

# Show Flux status
[no-cd]
status:
    #!/usr/bin/env bash
    KUBECONFIG="clusters/${cluster}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found. Run: just c bootstrap"
        exit 1
    fi
    KUBECONFIG="${KUBECONFIG}" flux get all -A

# Uninstall Flux
[no-cd]
uninstall:
    #!/usr/bin/env bash
    KUBECONFIG="clusters/${cluster}/talos/clusterconfig/kubeconfig"
    if [[ ! -f "${KUBECONFIG}" ]]; then
        echo "Error: kubeconfig not found"
        exit 1
    fi
    KUBECONFIG="${KUBECONFIG}" flux uninstall
