# ──────────────────────────────────────────────────────────────────
# S3 — bucket de staging do Athena (resultado de cada query execution)
# Separado do data lake de propósito: ciclo de vida diferente (dado
# efêmero, expira em dias) e não deve conviver no mesmo bucket que
# guarda bronze/silver/gold (dado que a gente quer reter).
# ──────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "athena_staging" {
  bucket = "${var.project_name}-athena-staging-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "athena_staging" {
  bucket = aws_s3_bucket.athena_staging.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_staging" {
  bucket = aws_s3_bucket.athena_staging.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_staging" {
  bucket = aws_s3_bucket.athena_staging.id

  rule {
    id     = "expire-query-results"
    status = "Enabled"

    filter {}

    expiration {
      days = var.query_results_retention_days
    }
  }
}
