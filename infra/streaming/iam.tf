# ──────────────────────────────────────────────────────────────────
# IAM — Role do consumer Lambda (least privilege)
# Ler o Kinesis, ler/escrever a tabela de dedup, escrever no S3
# (prefixo trades/), enviar para a DLQ, logar no CloudWatch.
# ──────────────────────────────────────────────────────────────────

resource "aws_iam_role" "consumer" {
  name = "${var.project_name}-trades-consumer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Leitura do Kinesis (o Event Source Mapping precisa disso)
resource "aws_iam_role_policy" "consumer_kinesis" {
  name = "kinesis-read"
  role = aws_iam_role.consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kinesis:GetRecords",
        "kinesis:GetShardIterator",
        "kinesis:DescribeStream",
        "kinesis:DescribeStreamSummary",
        "kinesis:ListShards",
      ]
      Resource = aws_kinesis_stream.trades.arn
    }]
  })
}

# Dedup no DynamoDB
resource "aws_iam_role_policy" "consumer_dynamodb" {
  name = "dynamodb-dedup"
  role = aws_iam_role.consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:GetItem"]
      Resource = aws_dynamodb_table.dedup.arn
    }]
  })
}

# Escrita no S3 (só prefixo trades/)
resource "aws_iam_role_policy" "consumer_s3" {
  name = "s3-trades-write"
  role = aws_iam_role.consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "arn:aws:s3:::${var.data_lake_bucket}/bronze/trades/*"
    }]
  })
}

# Envio para a DLQ (on-failure destination)
resource "aws_iam_role_policy" "consumer_dlq" {
  name = "sqs-dlq-send"
  role = aws_iam_role.consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = aws_sqs_queue.consumer_dlq.arn
    }]
  })
}

# Logs no CloudWatch
resource "aws_iam_role_policy_attachment" "consumer_logs" {
  role       = aws_iam_role.consumer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
