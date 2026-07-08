# ──────────────────────────────────────────────────────────────────
# Consumer Lambda + Event Source Mapping (ESM)
# O ESM faz polling do Kinesis e invoca a Lambda com batches.
# As configs de confiabilidade ficam no ESM
# ──────────────────────────────────────────────────────────────────

data "archive_file" "consumer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/consumer/trades"
  output_path = "${path.module}/build/trades_consumer.zip"
}

resource "aws_lambda_function" "consumer" {
  function_name = "${var.project_name}-trades-consumer"
  role          = aws_iam_role.consumer.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.consumer_zip.output_path
  source_code_hash = data.archive_file.consumer_zip.output_base64sha256

  environment {
    variables = {
      RAW_BUCKET      = var.data_lake_bucket
      DEDUP_TABLE     = aws_dynamodb_table.dedup.name
      DEDUP_TTL_HOURS = tostring(var.dedup_ttl_hours)
    }
  }
}

# Event Source Mapping
resource "aws_lambda_event_source_mapping" "kinesis_to_consumer" {
  event_source_arn  = aws_kinesis_stream.trades.arn
  function_name     = aws_lambda_function.consumer.arn
  starting_position = "LATEST"

  batch_size                         = 500
  maximum_batching_window_in_seconds = 10

  # worker por shard preserva a ordem dos trades
  parallelization_factor = 1

  # reprocessa os registros que falharam
  function_response_types = ["ReportBatchItemFailures"]

  # divide o batch ao dar erro
  bisect_batch_on_function_error = true

  maximum_retry_attempts        = 3
  maximum_record_age_in_seconds = 3600

  # DLQ — armazena batches que esgotaram os retries
  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.consumer_dlq.arn
    }
  }
}
