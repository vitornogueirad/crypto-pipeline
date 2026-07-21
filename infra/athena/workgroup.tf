# ──────────────────────────────────────────────────────────────────
# Athena Workgroup — isola configuração e custo do que roda neste
# projeto (não usa o workgroup "primary" compartilhado da conta).
# bytes_scanned_cutoff_per_query é o equivalente, em nível de query,
# do AWS Budgets já usado na Etapa 1 — aborta a query antes de
# escanear além do limite, em vez de só alertar depois do fato.
# ──────────────────────────────────────────────────────────────────

resource "aws_athena_workgroup" "crypto_pipeline" {
  name = "${var.project_name}-silver-gold"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.athena_bytes_scanned_cutoff

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_staging.bucket}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}
