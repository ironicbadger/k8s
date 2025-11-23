# Configuration Templates

This directory contains templates used by scripts in the parent directory to generate cluster-specific configurations.

## Terraform Templates

Located in `terraform/`, these templates are used to generate the Terraform configuration files for each cluster:

- **versions.tf.tmpl** - Terraform version requirements and S3 backend configuration
- **main.tf.tmpl** - Provider configuration and module invocation
- **variables.tf.tmpl** - Variable definitions
- **outputs.tf.tmpl** - Output definitions

### Template Variables

Templates use `__VARIABLE_NAME__` placeholders that are substituted by `confgen.sh`:

- `__CLUSTER_NAME__` - Cluster name from cluster.yaml metadata.name
- `__PROJECT_ROOT__` - Absolute path to the project root
- `__TERRAFORM_BACKEND_BUCKET__` - S3 bucket name from terraform-backend.yaml
- `__TERRAFORM_BACKEND_ENDPOINT__` - S3 endpoint URL from terraform-backend.yaml
- `__TERRAFORM_BACKEND_REGION__` - S3 region from terraform-backend.yaml

### Usage

Templates are automatically processed when running:
```bash
just confgen
```

The script reads values from:
1. `clusters/<name>/cluster.yaml` - Cluster-specific configuration
2. `terraform-backend.yaml` - Terraform backend settings (optional, uses defaults if missing)

Generated files are placed in `clusters/<name>/terraform/` and should not be committed to version control.
