# Step 7 — Infrastructure as Code (Checkov, Policy as Code)

## The problem

Most cloud breaches are not clever exploits but **misconfigurations**: a
public bucket, a database open to the internet, an unencrypted disk.
When infrastructure is code (Terraform), those mistakes can be caught in
a pull request, before anything exists in the cloud.

## What was added

| Path | Purpose |
|------|---------|
| `terraform/` | How the API would run on AWS: RDS PostgreSQL, S3 backups, KMS key |
| `policy/terraform/*.rego` | Our organization rules (Policy as Code, OPA/Rego) |
| `policy/terraform/*_test.rego` | Unit tests for those rules |
| `scripts/security/iac.sh` | fmt + validate → Checkov → Conftest |
| `docs/examples/terraform-insecure/` | Counter-example with the classic mistakes |
| `.gitleaks.toml` | New rule `terraform-hardcoded-password` |
| `ci.yml` → `iac` job | Runs everything, uploads Checkov SARIF |
| `.github/dependabot.yml` → `terraform` | Bumps the AWS provider |

**Nothing is ever deployed.** Every tool here reads the `.tf` files;
`terraform init -backend=false` needs no AWS account.

## Two kinds of rules

| | Checkov | Conftest (OPA/Rego) |
|-|---------|---------------------|
| Rules | ~1,000 built-in cloud best practices | Written by us |
| Knows | "RDS should be encrypted" | "We only use PostgreSQL", "every resource has an Owner" |
| Example | `CKV_AWS_17`: RDS must not be public | `instance_class must be db.t4g.*` |

Checkov knows the cloud; it cannot know your company. Policy as Code
fills that gap with rules that are versioned, reviewed and tested like
any other code.

## Running it

```bash
scripts/security/iac.sh
```

```
==> terraform fmt / validate
Success! The configuration is valid.
==> Checkov
Passed checks: 84, Failed checks: 0, Skipped checks: 6
==> Conftest: testing the policies themselves
10 tests, 10 passed
==> Conftest: applying the policies
30 tests, 30 passed
```

## How we got to 0 failures

The first Checkov run on `terraform/` returned **8 failures**. Each
one was handled in one of two ways:

**Fixed** (real improvements):

| Check | Fix |
|-------|-----|
| `CKV_AWS_118` enhanced monitoring | `monitoring_interval = 60` + IAM role |
| `CKV2_AWS_30` query logging | Parameter group: `log_statement = ddl`, slow queries |
| `CKV2_AWS_69` encryption in transit | `rds.force_ssl = 1` (appeared once the parameter group existed) |

**Skipped with a written reason** (accepted risk or false positive):

```hcl
resource "aws_s3_bucket" "backups" {
  #checkov:skip=CKV_AWS_144:Backups stay in one region on purpose (data residency); versioning covers deletion
  ...
}
```

```hcl
data "aws_iam_policy_document" "kms" {
  # False positives: inside a KMS *key policy*, resources = ["*"] means
  # "this key" and nothing else.
  #checkov:skip=CKV_AWS_109:Key policy, "*" refers only to this key
```

A skip without a reason is a hidden vulnerability. A skip with a reason
is a decision someone can review and challenge.

## Exercise: break it

```bash
scripts/security/iac.sh docs/examples/terraform-insecure
```

Checkov: **20 failures**, among them:

```
CKV_AWS_17:  Ensure all data stored in RDS is not publicly accessible
CKV_AWS_16:  Ensure all data stored in the RDS is securely encrypted at rest
CKV_AWS_24:  Ensure no security groups allow ingress from 0.0.0.0:0 to port 22
CKV_AWS_20:  S3 Bucket has an ACL defined which allows public READ access.
CKV2_AWS_6:  Ensure that S3 bucket has a Public Access block
...
```

Conftest: **4 organization rules broken**, which Checkov had no way to
know about:

```
FAIL - aws provider: default_tags is missing required tags {"Owner", "Project"}
FAIL - aws_db_instance.main: engine "mysql" is not allowed, use one of {"postgres"}
FAIL - aws_db_instance.main: instance_class "db.r6g.16xlarge" is not approved, ...
FAIL - aws_security_group.database: only port 443 may be open to the internet
```

### What nobody caught

The insecure example also has `password = "SuperSecret123!"`. Checkov
(terraform and secrets frameworks) and gitleaks' default rules **all
missed it**: a human-chosen password has no known format and low
entropy. So `.gitleaks.toml` got a new rule:

```toml
[[rules]]
id = "terraform-hardcoded-password"
path = '''\.tf$'''
regex = '''(?i)\bpassword\s*=\s*"([^"$]{6,})"'''
```

The example line is marked `# gitleaks:allow`, the per-line exception
mechanism from step 2. Remove that comment and the CI `secrets` job fails.

The secure version never has a password: `manage_master_user_password =
true` lets RDS generate it and store it in AWS Secrets Manager.

## Writing a policy

`policy/terraform/database.rego`:

```rego
package main

allowed_instance_classes := {"db.t4g.micro", "db.t4g.small", "db.t4g.medium"}

deny contains msg if {
	some name, instances in input.resource.aws_db_instance
	some db in instances
	not db.instance_class in allowed_instance_classes
	msg := sprintf("aws_db_instance.%s: instance_class %q is not approved", [name, db.instance_class])
}
```

Read it as: *"deny with message `msg` if there is some `aws_db_instance`
whose `instance_class` is not in the allowed set"*. Every condition in
the body must be true for the rule to fire.

To see the `input` that Conftest gives to your policies:

```bash
source scripts/security/lib.sh
run_tool "$CONFTEST_IMAGE" parse --parser hcl2 terraform/database.tf
```

And the tests (`database_test.rego`) feed a fake input:

```rego
test_huge_instance_is_denied if {
	count(deny) == 1 with input as {"resource": {"aws_db_instance": {"main": [
		{"engine": "postgres", "instance_class": "db.r6g.16xlarge"}]}}}
}
```

### Limitation: static HCL

Conftest reads the `.tf` files as text, so `region = var.region` arrives
as the string `"${var.region}"`, not `eu-west-1`. Rules about values that
come from variables need the **plan**:

```bash
terraform plan -out plan.bin && terraform show -json plan.bin > plan.json
conftest test plan.json
```

The plan needs real cloud credentials, so this repo sticks to static
rules.

## tfsec?

The table in the course mentions tfsec. tfsec was merged into Trivy:
`trivy config terraform/` runs the same checks. Checkov covers it here.
