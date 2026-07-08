# ──────────────────────────────────────────────────────────────────
# Observabilidade — alarmes CloudWatch
# IteratorAge (consumer atrasado), erros da Lambda, mensagens na DLQ.
# ──────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "streaming_alerts" {
  name = "${var.project_name}-streaming-alerts"
}

resource "aws_sns_topic_subscription" "streaming_email" {
  topic_arn = aws_sns_topic.streaming_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "iterator_age" {
  alarm_name          = "${var.project_name}-consumer-iterator-age-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "IteratorAge"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.iterator_age_alarm_ms
  alarm_description   = "Consumer atrasado: IteratorAge acima do limite (consumer não acompanha o stream)"
  alarm_actions       = [aws_sns_topic.streaming_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.consumer.function_name
  }
}

# Erros da Lambda consumer
resource "aws_cloudwatch_metric_alarm" "consumer_errors" {
  alarm_name          = "${var.project_name}-consumer-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Consumer com erros acima do esperado"
  alarm_actions       = [aws_sns_topic.streaming_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.consumer.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.project_name}-consumer-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Há mensagens na DLQ do consumer — investigar falhas"
  alarm_actions       = [aws_sns_topic.streaming_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.consumer_dlq.name
  }
}
