output "bucket_name" {
  value = aws_s3_bucket.dados.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.dados.arn
}
