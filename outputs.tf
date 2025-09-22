#outputs
output "intake_bucket" {
  value = aws_s3_bucket.intake.bucket
}

output "processed_bucket" {
  value = aws_s3_bucket.processed.bucket
}

output "archive_bucket" {
  value = aws_s3_bucket.archive.bucket
}

output "api_base_url" {
  value = "${aws_apigatewayv2_api.api.api_endpoint}/${aws_apigatewayv2_stage.api_stage.name}"
}

output "cdn_domain_name" {
  value = aws_cloudfront_distribution.processed_cdn.domain_name
}
