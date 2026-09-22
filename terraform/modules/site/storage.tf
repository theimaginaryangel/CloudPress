# S3 Policy for EC2 to access its specific prefix
resource "aws_iam_policy" "s3_media_policy" {
  name        = "cloudpress-s3-policy-${var.site_id}"
  description = "Allow EC2 to access its S3 prefix for media uploads"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${var.media_bucket_name}",
          "arn:aws:s3:::${var.media_bucket_name}/${var.site_id}/*"
        ]
        Condition = {
          StringLike = {
            "s3:prefix" = [
              "${var.site_id}/*"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_media_policy.arn
}

# Optional S3 Object creation just to ensure prefix exists (Terraform handles this mostly at upload, but we can enforce it)
resource "aws_s3_object" "site_prefix" {
  bucket       = var.media_bucket_name
  key          = "${var.site_id}/"
  content_type = "application/x-directory"
}
