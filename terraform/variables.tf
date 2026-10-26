variable "region" {
  description = "AWS region. Restricted by policy/terraform/region.rego."
  type        = string
  default     = "eu-west-1"
}

variable "owner" {
  description = "Team or person responsible for these resources."
  type        = string
  default     = "platform-team"
}

variable "vpc_id" {
  description = "VPC where the app and the database live."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the database (no route to the internet)."
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security group of the app containers; the only one allowed to reach the database."
  type        = string
}
