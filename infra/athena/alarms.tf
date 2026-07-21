# ──────────────────────────────────────────────────────────────────
# Alarme dispara com QUALQUER erro (threshold = 0) — cada partição
# falhada já é logada individualmente pelo transform_runner, então
# um Errors > 0 aqui significa que pelo menos uma partição não foi
# processada nesta janela de 5 min, mesmo que as demais tenham ido bem.
# ──────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "trades_transform_errors" {
  alarm_name          = "${var.project_name}-silver-trades-transform-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Lambda de transformação silver.trades falhou pelo menos uma vez"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.trades_transform.function_name
  }

  alarm_actions = [aws_sns_topic.silver_transform_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "market_snapshot_transform_errors" {
  alarm_name          = "${var.project_name}-silver-market-snapshot-transform-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Lambda de transformação silver.market_snapshot falhou pelo menos uma vez"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.market_snapshot_transform.function_name
  }

  alarm_actions = [aws_sns_topic.silver_transform_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "anomalias_transform_errors" {
  alarm_name          = "${var.project_name}-gold-anomalias-transform-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Lambda de transformação gold.anomalias falhou"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.anomalias_transform.function_name
  }

  alarm_actions = [aws_sns_topic.silver_transform_alerts.arn]
}
