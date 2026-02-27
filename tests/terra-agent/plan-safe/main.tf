terraform {
  required_version = ">= 1.5.0"
}

locals {
  name = "plan-safe"
}

output "name" {
  value = local.name
}

