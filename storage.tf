resource "aws_s3_bucket" "main" {
  bucket = "my-s3-bucket"
  tags = {
    Name = "my-s3-bucket"
  }
}


