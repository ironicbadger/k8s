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
      --personal

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
