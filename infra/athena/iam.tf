# ──────────────────────────────────────────────────────────────────
# IAM — Role compartilhada pelas Lambdas de transformação.
# Hoje: trades_transform e market_snapshot_transform (silver).
# Reaproveitável pela transformação da gold quando for implementada.
# Permissões: executar query no workgroup específico, ler/escrever
# no Glue Catalog, ler bronze (read-only), escrever silver/gold,
# ler/escrever no bucket de staging do Athena.
# ──────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_athena_transform" {
  name = "${var.project_name}-lambda-athena-transform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "athena_query_execution" {
  name = "athena-query-execution"
  role = aws_iam_role.lambda_athena_transform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AthenaQuery"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution"
        ]
        Resource = aws_athena_workgroup.crypto_pipeline.arn
      },
      {
        # Glue Catalog não tem ARN granular por tabela pra este
        # conjunto de ações (GetTable/CreateTable/UpdateTable exigem
        # Resource "*" mesmo com o database já restrito por nome).
        Sid    = "GlueCatalogAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartitions",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:BatchCreatePartition"
        ]
        Resource = "*"
      },
      {
        Sid      = "ReadBronze"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.data_lake_bucket}/bronze/*"
      },
      {
        Sid      = "WriteSilverGold"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [
          "arn:aws:s3:::${var.data_lake_bucket}/silver/*",
          "arn:aws:s3:::${var.data_lake_bucket}/gold/*"
        ]
      },
      {
        Sid      = "ListDataLakeBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.data_lake_bucket}"
      },
      {
        Sid    = "AthenaStagingBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.athena_staging.arn,
          "${aws_s3_bucket.athena_staging.arn}/*"
        ]
      },
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
