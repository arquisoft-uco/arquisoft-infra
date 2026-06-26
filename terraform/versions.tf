# =============================================================================
# Terraform y providers requeridos
# =============================================================================
terraform {
  required_version = ">= 1.6"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # ---------------------------------------------------------------------------
  # Estado remoto (cloud-ready). Local por defecto; al migrar a cloud, activar
  # uno de estos bloques (requiere el bucket/cuenta correspondiente) y re-init.
  # ---------------------------------------------------------------------------
  # backend "s3" {
  #   bucket         = "arquisoft-tfstate"
  #   key            = "infra/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "arquisoft-tflock"   # state locking
  #   encrypt        = true
  # }
  # backend "gcs"     { bucket = "arquisoft-tfstate"  prefix = "infra" }
  # backend "azurerm" { resource_group_name = "..."  storage_account_name = "..."  container_name = "tfstate"  key = "infra.tfstate" }
}
