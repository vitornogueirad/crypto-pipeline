output "kinesis_stream_name" {
  description = "Nome do Kinesis Data Stream (usado pelo producer)"
  value       = aws_kinesis_stream.trades.name
}

output "kinesis_stream_arn" {
  description = "ARN do stream"
  value       = aws_kinesis_stream.trades.arn
}

output "consumer_function_name" {
  description = "Nome da Lambda consumer"
  value       = aws_lambda_function.consumer.function_name
}

output "dedup_table_name" {
  description = "Tabela DynamoDB de deduplicação"
  value       = aws_dynamodb_table.dedup.name
}

output "dlq_url" {
  description = "URL da Dead-Letter Queue"
  value       = aws_sqs_queue.consumer_dlq.url
}
