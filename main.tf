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

#s3 buckets
resource "aws_s3_bucket" "intake" {
    bucket = local.intake_bucket
}

resource "aws_s3_bucket" "processed" {
    bucket = local.processed_bucket
}

resource "aws_s3_bucket" "archive" {
    bucket = local.archive_bucket
}

#blocking all public access - later uploads will be assigned with CloudFront
resource "aws_s3_bucket_public_access_block" "pab_intake" {
    bucket = aws_s3_bucket.intake.id
    block_public_acls = true
    block_public_policy = true
    restrict_public_buckets = true
    ignore_public_acls = true
}

resource "aws_s3_bucket_public_access_block" "pab_processed" {
    bucket = aws_s3_bucket.processed.id
    block_public_acls = true
    block_public_policy = true
    restrict_public_buckets = true
    ignore_public_acls = true
}

resource "aws_s3_bucket_public_access_block" "pab_archive" {
    bucket = aws_s3_bucket.archive.id
    block_public_acls = true
    block_public_policy = true
    restrict_public_buckets = true
    ignore_public_acls = true
}