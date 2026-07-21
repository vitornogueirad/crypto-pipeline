resource "aws_sns_topic" "silver_transform_alerts" {
  name = "${var.project_name}-silver-transform-alerts"
}

resource "aws_sns_topic_subscription" "silver_transform_alerts_email" {
  topic_arn = aws_sns_topic.silver_transform_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
