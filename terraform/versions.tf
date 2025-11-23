terraform {
  required_version = ">= 1.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.70.0"
    }
  }

  backend "s3" {
    bucket = "terraform-state"
    key    = "k8s/terraform.tfstate"
    region = "garage"

    endpoints = {
      s3 = "https://garage.ktz.ts.net:3900"
    }

    # S3-compatible backend workarounds (not real AWS)
    skip_credentials_validation = true  # Don't validate against AWS STS
    skip_metadata_api_check     = true  # Don't check EC2 metadata service
    skip_region_validation      = true  # Accept "garage" as a valid region
    skip_requesting_account_id  = true  # Don't request AWS account ID
    skip_s3_checksum            = true  # Don't send checksums (Garage compatibility)
    use_path_style              = true  # Use path-style URLs (garage.ktz.ts.net/bucket/key)

    # Credentials loaded via .envrc from secrets.tfvars
    # OpenTofu is used instead of Terraform (checksum bug workaround)
  }
}
