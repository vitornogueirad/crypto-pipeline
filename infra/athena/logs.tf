# ──────────────────────────────────────────────────────────────────
# CloudWatch Log Groups — declarados explicitamente com retenção.
# Sem isso, o Lambda cria o log group sozinho na primeira invocação,
# mas SEM expiração — logs acumulam pra sempre e geram custo crescente.
# ──────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "trades_transform" {
  name              = "/aws/lambda/${var.project_name}-silver-trades-transform"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "market_snapshot_transform" {
  name              = "/aws/lambda/${var.project_name}-silver-market-snapshot-transform"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "anomalias_transform" {
  name              = "/aws/lambda/${var.project_name}-gold-anomalias-transform"
  retention_in_days = var.log_retention_days
}
