output "intake_bucket" {
  value = aws_s3_bucket.intake.bucket
}

output "processed_bucket" {
  value = aws_s3_bucket.processed.bucket
}

output "archive_bucket" {
  value = aws_s3_bucket.archive.bucket
}