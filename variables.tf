variable "project" {
  type    = string
  default = "s3-router"
}

variable "region" {
  type    = string
  default = "us-east-2"
}

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

#api key upload
variable "upload_api_key" {
  description = "Shared secret sent in x-api-key for presign endpoints"
  type        = string
  sensitive   = true
  default     = "-------"
}
