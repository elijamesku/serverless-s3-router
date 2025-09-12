variable "project" {
    type = string
    default = "s3-router"
}

variable "region" {
    type = string
    default = "us-east-2" 
}

#will be changing default to true to run kms later
variable "kms_sse" {
    type = bool
    default = false 
}

variable "tags" {
    type = map(string)
    default = {
      Owner = "eli"
      Purpose = "serverless-s3-router"
    }
}