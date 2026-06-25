# ──────────────────────────────────────────────────────────────────
# Lambda de ingestão + agendamento via EventBridge
# ──────────────────────────────────────────────────────────────────

# Empacota o código da Lambda em zip
data "archive_file" "ingestion_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../src/ingestion/coingecko"
  output_path = "${path.module}/build/coingecko_ingestion.zip"
}

resource "aws_lambda_function" "coingecko_ingestion" {
  function_name = "${var.project_name}-coingecko-ingestion"
  role          = aws_iam_role.lambda_ingestion.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.ingestion_zip.output_path
  source_code_hash = data.archive_file.ingestion_zip.output_base64sha256

  environment {
    variables = {
      RAW_BUCKET            = aws_s3_bucket.data_lake.id
      COINGECKO_SECRET_NAME = aws_secretsmanager_secret.coingecko.name
      COINS                 = var.coins
      VS_CURRENCY           = "usd"
    }
  }
}

# Regra do EventBridge — dispara a Lambda no schedule definido
resource "aws_cloudwatch_event_rule" "ingestion_schedule" {
  name                = "${var.project_name}-ingestion-schedule"
  description         = "Aciona a ingestão CoinGecko periodicamente"
  schedule_expression = var.ingestion_schedule
}

resource "aws_cloudwatch_event_target" "ingestion_lambda" {
  rule      = aws_cloudwatch_event_rule.ingestion_schedule.name
  target_id = "coingecko-ingestion"
  arn       = aws_lambda_function.coingecko_ingestion.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.coingecko_ingestion.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ingestion_schedule.arn
}
