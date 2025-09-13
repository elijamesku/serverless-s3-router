#proj name var
variable "project" {
  type    = string
  default = "s3-router"
}

#setting default region var
variable "region" {
  type    = string
  default = "us-east-2"
}

#will be changing default to true to run kms later
variable "kms_sse" {
  type    = bool
  default = false
}

#indication tags
variable "tags" {
  type = map(string)
  default = {
    Owner   = "eli"
    Purpose = "serverless-s3-router"
  }
}

variable "upload_api_key" {
  description = "Shared secret sent in x-api-key for presign endpoints"
  type        = string
  sensitive   = true
  default     = "REPLACE_ME"
}