# Our own encryption key (customer-managed) instead of the AWS default
# key: we control who can use it, and every use is logged in CloudTrail.
resource "aws_kms_key" "main" {
  description             = "dev-secops data encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "main" {
  name          = "alias/dev-secops"
  target_key_id = aws_kms_key.main.key_id
}

data "aws_caller_identity" "current" {}

# Only the account itself may administer and use the key. Services such
# as RDS and S3 use it on behalf of principals in this account.
data "aws_iam_policy_document" "kms" {
  # False positives: inside a KMS *key policy*, resources = ["*"] means
  # "this key" and nothing else. Checkov evaluates it like an IAM policy.
  #checkov:skip=CKV_AWS_109:Key policy, "*" refers only to this key
  #checkov:skip=CKV_AWS_111:Key policy, "*" refers only to this key
  #checkov:skip=CKV_AWS_356:Key policy, "*" refers only to this key
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}
