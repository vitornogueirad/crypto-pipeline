# ──────────────────────────────────────────────────────────────────
# Usuário IAM dedicado, read-only, para o Power BI conectar no Athena
# via ODBC. Criado separado das Lambdas porque:
#   - o driver ODBC v2 do Athena não resolve profile SSO de forma
#     confiável, então precisa de Access Key/Secret Key permanentes;
#   - o escopo é estritamente leitura dos dados (só o staging do
#     Athena recebe escrita, porque o Athena exige gravar o resultado
#     da query lá antes de devolver ao cliente).
#
# A ACCESS KEY em si não é criada aqui de propósito: chave permanente
# não deve ir para o state do Terraform (o state guardaria o secret em
# texto). Depois do apply, gere a chave manualmente:
#
#   Console IAM > Users > crypto-pipeline-powerbi-reader >
#   Security credentials > Create access key > "Application outside AWS"
#
# ou via CLI:
#   aws iam create-access-key --user-name crypto-pipeline-powerbi-reader --profile portfolio-dev
#
# A Secret Key aparece uma única vez — copie na hora e cole só no DSN
# local do Power BI (Authentication Type: IAM Credentials). Nunca
# versione essa chave.
# ──────────────────────────────────────────────────────────────────

resource "aws_iam_user" "powerbi_reader" {
  name = "${var.project_name}-powerbi-reader"
  tags = {
    Purpose = "Power BI read-only access to Athena"
    Project = var.project_name
  }
}

resource "aws_iam_user_policy" "powerbi_reader" {
  name = "athena-read-only"
  user = aws_iam_user.powerbi_reader.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AthenaRead"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution",
          "athena:GetWorkGroup"
        ]
        Resource = aws_athena_workgroup.crypto_pipeline.arn
      },
      {
        # Ações de navegação do catálogo que o Power BI usa no Navigator.
        # Não aceitam ARN granular de workgroup — exigem Resource "*".
        Sid    = "AthenaListMetadata"
        Effect = "Allow"
        Action = [
          "athena:ListDataCatalogs",
          "athena:ListDatabases",
          "athena:ListTableMetadata",
          "athena:GetDataCatalog",
          "athena:GetDatabase",
          "athena:GetTableMetadata"
        ]
        Resource = "*"
      },
      {
        Sid    = "GlueCatalogRead"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadDataLake"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.data_lake_bucket}",
          "arn:aws:s3:::${var.data_lake_bucket}/*"
        ]
      },
      {
        # Athena exige escrever o resultado da query no staging antes
        # de devolver ao Power BI — por isso este é o único ponto com
        # permissão de escrita, e restrito ao bucket de staging.
        Sid    = "AthenaStagingReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.athena_staging.arn,
          "${aws_s3_bucket.athena_staging.arn}/*"
        ]
      }
    ]
  })
}
