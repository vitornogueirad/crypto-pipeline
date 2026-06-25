# ──────────────────────────────────────────────────────────────────
# IAM — Role da Lambda com least privilege
# Escreve no prefixo bronze/, ler o secret, logar no CloudWatch
# ──────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_ingestion" {
  name = "${var.project_name}-lambda-ingestion"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_s3_write" {
  name = "s3-bronze-write"
  role = aws_iam_role.lambda_ingestion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.data_lake.arn}/bronze/*"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_secret_read" {
  name = "secret-read"
  role = aws_iam_role.lambda_ingestion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.coingecko.arn
    }]
  })
}

# Logs no CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_ingestion.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
