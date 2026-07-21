# ──────────────────────────────────────────────────────────────────
# EventBridge — dispara as duas Lambdas periodicamente. Mesmo padrão
# já usado no coingecko-ingestion (schedule -> Lambda).
# ──────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "trades_transform_schedule" {
  name                = "${var.project_name}-silver-trades-transform-schedule"
  schedule_expression = var.transform_schedule_expression
}

resource "aws_cloudwatch_event_target" "trades_transform" {
  rule = aws_cloudwatch_event_rule.trades_transform_schedule.name
  arn  = aws_lambda_function.trades_transform.arn
}

resource "aws_lambda_permission" "trades_transform_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.trades_transform.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.trades_transform_schedule.arn
}

resource "aws_cloudwatch_event_rule" "market_snapshot_transform_schedule" {
  name                = "${var.project_name}-silver-market-snapshot-transform-schedule"
  schedule_expression = var.transform_schedule_expression
}

resource "aws_cloudwatch_event_target" "market_snapshot_transform" {
  rule = aws_cloudwatch_event_rule.market_snapshot_transform_schedule.name
  arn  = aws_lambda_function.market_snapshot_transform.arn
}

resource "aws_lambda_permission" "market_snapshot_transform_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.market_snapshot_transform.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.market_snapshot_transform_schedule.arn
}

resource "aws_cloudwatch_event_rule" "anomalias_transform_schedule" {
  name                = "${var.project_name}-gold-anomalias-transform-schedule"
  schedule_expression = var.gold_schedule_expression
}

resource "aws_cloudwatch_event_target" "anomalias_transform" {
  rule = aws_cloudwatch_event_rule.anomalias_transform_schedule.name
  arn  = aws_lambda_function.anomalias_transform.arn
}

resource "aws_lambda_permission" "anomalias_transform_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.anomalias_transform.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.anomalias_transform_schedule.arn
}
