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
  processed_bucket = "${var.project}-processed-${local.processed_bucket}"

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
      sse_algorithm = var.kms_sse ? "aws:kms" : AES256
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse_processed" {
  bucket = aws_s3_bucket.processed.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.kms_sse ? "aws:kms" : AES256
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse_archive" {
  bucket = aws_s3_bucket.archive.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.kms_sse ? "aws:kms" : AES256
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
