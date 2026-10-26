# PostgreSQL for the notes API.

resource "aws_db_subnet_group" "main" {
  name       = "dev-secops"
  subnet_ids = var.private_subnet_ids
}

# Only the app can reach the database, and only on the Postgres port.
resource "aws_security_group" "database" {
  name        = "dev-secops-database"
  description = "PostgreSQL, reachable only from the app"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "database_from_app" {
  security_group_id            = aws_security_group.database.id
  description                  = "PostgreSQL from the app containers"
  referenced_security_group_id = var.app_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_db_instance" "main" {
  identifier     = "dev-secops"
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_encrypted = true
  kms_key_id        = aws_kms_key.main.arn

  db_name  = "notes"
  username = "notes_admin"
  # No password in Terraform code or state: RDS generates it and keeps it
  # in AWS Secrets Manager, rotating it automatically.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.main.arn

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false

  multi_az                   = true
  backup_retention_period    = 7
  deletion_protection        = true
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  skip_final_snapshot        = false
  final_snapshot_identifier  = "dev-secops-final"

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.main.arn

  # OS-level metrics every 60 s (CPU, memory, I/O per process).
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  parameter_group_name = aws_db_parameter_group.main.name
}

# - Rejects unencrypted connections (TLS only).
# - Logs every schema change (DDL) and every query slower than 1 s:
#   enough to investigate an incident without logging user data.
resource "aws_db_parameter_group" "main" {
  name   = "dev-secops-postgres17"
  family = "postgres17"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }
}

# Role that lets RDS publish enhanced monitoring metrics to CloudWatch.
resource "aws_iam_role" "rds_monitoring" {
  name               = "dev-secops-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
}

data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
