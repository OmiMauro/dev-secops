# DO NOT USE. Counter-example for docs/07-iac.md.
# Run: scripts/security/iac.sh docs/examples/terraform-insecure

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }
}

# No default_tags: nobody knows who owns this.
provider "aws" {
  region = "eu-west-1"
}

# No encryption, no versioning, no public access block.
resource "aws_s3_bucket" "backups" {
  bucket = "my-company-backups"
}

resource "aws_s3_bucket_acl" "backups" {
  bucket = aws_s3_bucket.backups.id
  acl    = "public-read"
}

# SSH and Postgres open to the whole internet.
resource "aws_security_group" "database" {
  name        = "database"
  description = "database"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Public, unencrypted, password in the code (and in the state file).
resource "aws_db_instance" "main" {
  identifier          = "main"
  engine              = "mysql"
  instance_class      = "db.r6g.16xlarge"
  allocated_storage   = 20
  username            = "admin"
  password            = "SuperSecret123!" # gitleaks:allow (intentional bad example)
  publicly_accessible = true
  skip_final_snapshot = true

  vpc_security_group_ids = [aws_security_group.database.id]
}
