output "athena_workgroup_name" {
  value = aws_athena_workgroup.crypto_pipeline.name
}

output "athena_staging_bucket" {
  value = aws_s3_bucket.athena_staging.bucket
}

output "lambda_athena_transform_role_arn" {
  value = aws_iam_role.lambda_athena_transform.arn
}

output "glue_databases" {
  value = {
    bronze = aws_glue_catalog_database.bronze.name
    silver = aws_glue_catalog_database.silver.name
    gold   = aws_glue_catalog_database.gold.name
  }
}

output "trades_transform_lambda_name" {
  value = aws_lambda_function.trades_transform.function_name
}

output "market_snapshot_transform_lambda_name" {
  value = aws_lambda_function.market_snapshot_transform.function_name
}

output "anomalias_transform_lambda_name" {
  value = aws_lambda_function.anomalias_transform.function_name
}
