#Terraform
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.2"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.2"
    }
  }
}

#reference to variables.tf line 7
provider "aws" {
  region = var.region
}

#for s3 naming convention ref below in locals
resource "random_pet" "suffix" {
  length = 2
}

#defining named values // var.project reference > variables.tf line 1
locals {
  #ex curious-dolphin
  name_suffix = random_pet.suffix.id

  #ex s3-router-intake-curious-dolphin
  intake_bucket = "${var.project}-intake-${local.name_suffix}"

  #ex s3-router-processed-curious-dolphin
  processed_bucket = "${var.project}-processed-${local.name_suffix}"

  #ex s3-router-archive-curious-dolphin
  archive_bucket = "${var.project}-archive-${local.name_suffix}"
}

#intake files s3 bucket
resource "aws_s3_bucket" "intake" {
  bucket = local.intake_bucket
}

#processed files s3 bucket
resource "aws_s3_bucket" "processed" {
  bucket = local.processed_bucket
}

#archived files s3 bucket
resource "aws_s3_bucket" "archive" {
  bucket = local.archive_bucket
}

#blocking all public access - later uploads will be assigned with CloudFront
#pab for intake bucket
resource "aws_s3_bucket_public_access_block" "pab_intake" {
  bucket                  = aws_s3_bucket.intake.id
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

#pab for processed bucket
resource "aws_s3_bucket_public_access_block" "pab_processed" {
  bucket                  = aws_s3_bucket.processed.id
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

#pab for archive bucket
resource "aws_s3_bucket_public_access_block" "pab_archive" {
  bucket                  = aws_s3_bucket.archive.id
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

#default encryption (SSE-S3 for now) -- KMS later when var.kms = true
resource "aws_s3_bucket_server_side_encryption_configuration" "sse_intake" {
  bucket = aws_s3_bucket.intake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.kms_sse ? "aws:kms" : "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse_processed" {
  bucket = aws_s3_bucket.processed.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.kms_sse ? "aws:kms" : "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse_archive" {
  bucket = aws_s3_bucket.archive.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.kms_sse ? "aws:kms" : "AES256"
    }
  }
}

#possible option to expire raw uploads after 30 days
resource "aws_s3_bucket_lifecycle_configuration" "lc_intake" {
  bucket = aws_s3_bucket.intake.id
  rule {
    id     = "expire-uploads-30d"
    status = "Enabled"
    filter {
      prefix = "uploads/"
    }
    expiration {
      days = 30
    }
  }
}


#sqs (events + DLQ)
resource "aws_sqs_queue" "dlq" {
  name = "${var.project}-dlq-${local.name_suffix}"
}

resource "aws_sqs_queue" "queue" {
  name = "${var.project}-queue-${local.name_suffix}"
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
  visibility_timeout_seconds = 120
}

#enabling S3 to send messages to SQS
data "aws_iam_policy_document" "s3_to_aqs" {
  statement {
    actions = ["sqs:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    resources = [aws_sqs_queue.queue.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.intake.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "queue_policy" {
  queue_url = aws_sqs_queue.queue.id
  policy    = data.aws_iam_policy_document.s3_to_aqs.json
}

#notifying SQS on the object created under uploads/
resource "aws_s3_bucket_notification" "intake_events" {
  bucket = aws_s3_bucket.intake.id
  queue {
    queue_arn     = aws_sqs_queue.queue.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "uploads/"
  }
  depends_on = [aws_sqs_queue_policy.queue_policy]

}

#lamda (router)
resource "aws_iam_role" "lambda_role" {
  name = "${var.project}-lambda-${local.name_suffix}"
  assume_role_policy = jsonencode({
    version = "2012-10-17",
    statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      action = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid       = "logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
  statement {
    sid     = "S3RW"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:CopyObject", "s3:ListBucket", "s3:GetObjectVersion"]
    resources = [
      aws_s3_bucket.intake.arn, "${aws_s3_bucket.intake.arn}/*",
      aws_s3_bucket.processed.arn, "${aws_s3_bucket.processed.arn}/*",
      aws_s3_bucket.archive.arn, "${aws_s3_bucket.archive.arn}/*"
    ]
  }
  statement {
    sid       = "SQSRW"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAtrributes"]
    resources = [aws_sqs_queue.queue.arn]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.project}-lambda-${local.name_suffix}"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

#packaging everything in /lambda as a zip
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

#lambda function 
resource "aws_lambda_function" "router" {
  function_name    = "${var.project}-router-${local.name_suffix}"
  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "handler.main"
  runtime          = "pythin3.11"
  timeout          = 60
  memory_size      = 512
  environment {
    variables = {
      PROCESSED_BUCKET = aws_s3_bucket.processed.bucket
      ARCHIVE_BUCKET   = aws_s3_bucket.archive.bucket
    }
  }
  tags = var.tags
}

resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn                   = aws_sqs_queue.queue.arn
  function_name                      = aws_lambda_function.router.arn
  batch_size                         = 5
  maximum_batching_window_in_seconds = 10
}

