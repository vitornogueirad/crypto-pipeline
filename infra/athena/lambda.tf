# ──────────────────────────────────────────────────────────────────
# Lambdas de transformação: bronze -> silver, via MERGE INTO no Athena.
#
# Cada zip empacota o handler + os 3 módulos comuns (src/transform/common)
# + a query .sql específica, todos ACHATADOS no mesmo diretório dentro
# do zip — é assim que os imports dos handlers foram desenhados pra
# funcionar (ver sys.path.append em cada handler.py).
#
# boto3 já vem embutido no runtime gerenciado do Lambda (Python 3.12),
# não precisa empacotar — diferente do producer, que precisa de Docker
# por causa do pacote websockets.
# ──────────────────────────────────────────────────────────────────

data "archive_file" "trades_transform" {
  type        = "zip"
  output_path = "${path.module}/build/trades_transform.zip"

  source {
    content  = file("${path.module}/../../src/transform/silver/trades_handler.py")
    filename = "trades_handler.py"
  }
  source {
    content  = file("${path.module}/../../src/transform/silver/silver_trades_merge.sql")
    filename = "silver_trades_merge.sql"
  }
  source {
    content  = file("${path.module}/../../src/transform/common/athena_executor.py")
    filename = "athena_executor.py"
  }
  source {
    content  = file("${path.module}/../../src/transform/common/partitions.py")
    filename = "partitions.py"
  }
  source {
    content  = file("${path.module}/../../src/transform/common/transform_runner.py")
    filename = "transform_runner.py"
  }
}

resource "aws_lambda_function" "trades_transform" {
  function_name = "${var.project_name}-silver-trades-transform"
  role          = aws_iam_role.lambda_athena_transform.arn
  handler       = "trades_handler.handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout_seconds
  memory_size   = 128

  filename         = data.archive_file.trades_transform.output_path
  source_code_hash = data.archive_file.trades_transform.output_base64sha256

  environment {
    variables = {
      ATHENA_WORKGROUP = aws_athena_workgroup.crypto_pipeline.name
      SILVER_DATABASE  = "silver"
    }
  }

  depends_on = [aws_cloudwatch_log_group.trades_transform]
}

data "archive_file" "market_snapshot_transform" {
  type        = "zip"
  output_path = "${path.module}/build/market_snapshot_transform.zip"

  source {
    content  = file("${path.module}/../../src/transform/silver/market_snapshot_handler.py")
    filename = "market_snapshot_handler.py"
  }
  source {
    content  = file("${path.module}/../../src/transform/silver/silver_market_snapshot_merge.sql")
    filename = "silver_market_snapshot_merge.sql"
  }
  source {
    content  = file("${path.module}/../../src/transform/common/athena_executor.py")
    filename = "athena_executor.py"
  }
  source {
    content  = file("${path.module}/../../src/transform/common/partitions.py")
    filename = "partitions.py"
  }
  source {
    content  = file("${path.module}/../../src/transform/common/transform_runner.py")
    filename = "transform_runner.py"
  }
}

resource "aws_lambda_function" "market_snapshot_transform" {
  function_name = "${var.project_name}-silver-market-snapshot-transform"
  role          = aws_iam_role.lambda_athena_transform.arn
  handler       = "market_snapshot_handler.handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout_seconds
  memory_size   = 128

  filename         = data.archive_file.market_snapshot_transform.output_path
  source_code_hash = data.archive_file.market_snapshot_transform.output_base64sha256

  environment {
    variables = {
      ATHENA_WORKGROUP = aws_athena_workgroup.crypto_pipeline.name
      SILVER_DATABASE  = "silver"
    }
  }

  depends_on = [aws_cloudwatch_log_group.market_snapshot_transform]
}

# ──────────────────────────────────────────────────────────────────
# Lambda de gold: recalcula gold.anomalias (upsert). Não recebe
# partição — o zip inclui só athena_executor.py, não partitions.py
# nem transform_runner.py, já que essa Lambda não usa nenhum dos dois.
# ──────────────────────────────────────────────────────────────────

data "archive_file" "anomalias_transform" {
  type        = "zip"
  output_path = "${path.module}/build/anomalias_transform.zip"

  source {
    content  = file("${path.module}/../../src/transform/gold/anomalias_handler.py")
    filename = "anomalias_handler.py"
  }
  source {
    content  = file("${path.module}/../../src/transform/gold/gold_anomalias_merge.sql")
    filename = "gold_anomalias_merge.sql"
  }
  source {
    content  = file("${path.module}/../../src/transform/common/athena_executor.py")
    filename = "athena_executor.py"
  }
}

resource "aws_lambda_function" "anomalias_transform" {
  function_name = "${var.project_name}-gold-anomalias-transform"
  role          = aws_iam_role.lambda_athena_transform.arn
  handler       = "anomalias_handler.handler"
  runtime       = "python3.12"
  timeout       = var.lambda_timeout_seconds
  memory_size   = 128

  filename         = data.archive_file.anomalias_transform.output_path
  source_code_hash = data.archive_file.anomalias_transform.output_base64sha256

  environment {
    variables = {
      ATHENA_WORKGROUP = aws_athena_workgroup.crypto_pipeline.name
      GOLD_DATABASE    = "gold"
    }
  }

  depends_on = [aws_cloudwatch_log_group.anomalias_transform]
}
