provider "aws" {
  region = var.region

  # Applied to every resource. Our Policy as Code rules require these
  # tags: without an owner nobody knows who to call when it breaks.
  default_tags {
    tags = {
      Project   = "dev-secops"
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
