output "data_lake_bucket" {
  description = "Nome do bucket do data lake"
  value       = aws_s3_bucket.data_lake.id
}

output "lambda_function_name" {
  description = "Nome da Lambda de ingestão"
  value       = aws_lambda_function.coingecko_ingestion.function_name
}

output "secret_name" {
  description = "Nome do secret da CoinGecko (setar o valor via CLI)"
  value       = aws_secretsmanager_secret.coingecko.name
}
