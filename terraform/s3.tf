##############################################################################
# S3 Bucket — Data (electrify-data)
##############################################################################

resource "aws_s3_bucket" "data" {
  bucket        = "electrify-data-${local.region}-${local.suffix}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "electrify-data-${local.region}-${local.suffix}"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

##############################################################################
# S3 Bucket — Lab Data (electrify-data short name / bucketLabData)
##############################################################################

resource "aws_s3_bucket" "lab_data" {
  bucket        = "electrify-data-${local.suffix}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "electrify-data-${local.suffix}"
  })
}

resource "aws_s3_bucket_public_access_block" "lab_data" {
  bucket                  = aws_s3_bucket.lab_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

##############################################################################
# S3 Bucket — Website (electrify-site)
##############################################################################

resource "aws_s3_bucket" "website" {
  bucket        = "electrify-site-${local.region}-${local.suffix}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "electrify-site-${local.region}-${local.suffix}"
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket                  = aws_s3_bucket.website.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Bucket policy allowing CloudFront OAC to read objects
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Statement = [{
      Effect    = "Allow"
      Resource  = "${aws_s3_bucket.website.arn}/*"
      Action    = ["s3:GetObject"]
      Principal = { Service = "cloudfront.amazonaws.com" }
      Condition = {
        StringLike = {
          "AWS:SourceArn" = "arn:aws:cloudfront::${local.account_id}:distribution/*"
        }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.website]
}
