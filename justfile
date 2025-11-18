# Terraform + Talos cluster commands

# Initialize terraform
init:
    terraform -chdir=terraform init

# Create VMs
apply:
    terraform -chdir=terraform apply -auto-approve -var-file="secrets.tfvars"

refresh:
    terraform -chdir=terraform refresh -var-file="secrets.tfvars"

# Show plan
plan:
    terraform -chdir=terraform plan -var-file="secrets.tfvars"

# Run Talos setup (after VMs are created)
talos:
    ./talos-setup.sh

# Destroy infrastructure
nuke:
    terraform -chdir=terraform destroy -auto-approve -var-file="secrets.tfvars" -var="force_stop=true"
    rm -rf _out

# Export environment variables (run with: eval "$(just env)")
export:
    @echo 'export TALOSCONFIG=/Users/alex/git/ib/talos-lab-terraform/_out/talosconfig'
    @echo 'export KUBECONFIG=/Users/alex/git/ib/talos-lab-terraform/_out/kubeconfig'
    kubectl get nodes

# Full workflow hint
cluster:
    @echo "Workflow:"
    @echo "  1. just apply     - Create VMs"
    @echo "  2. just talos     - Configure Talos & bootstrap"