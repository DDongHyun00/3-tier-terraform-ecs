# 첨부파일·정적 파일 버킷 + CloudFront (#26). 설계: docs/architecture.md 6.3절. 결정: DEC-6, DEC-12.
#
# 버킷 하나를 두 용도로 쓴다.
#   - 첨부파일: 앱이 태스크 역할로 읽고 쓴다. 다운로드는 앱이 권한을 확인한 뒤 내려준다. CloudFront를 거치지 않는다.
#   - 정적 파일(static/*): CloudFront가 OAC로 읽어 서빙한다. 버킷 직접 접근은 막혀 있다.

# ---------- 버킷 ----------
resource "aws_s3_bucket" "assets" {
  bucket        = "3tier-assets-${var.account_suffix}" # S3 이름은 전역 유일 → 계정 접미사
  force_destroy = true                                 # 반복 destroy 전제. 객체가 있어도 지운다

  tags = { Name = "${var.name_prefix}-assets" }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ACL을 끄고 버킷 소유자가 모든 객체를 소유. 요즘 기본값이고 CloudFront OAC가 전제로 한다.
resource "aws_s3_bucket_ownership_controls" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---------- CloudFront ----------
# 관리형 캐시 정책은 ID가 아니라 이름으로 찾는다. ID 하드코딩은 오타 위험이 있다.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# OAC(Origin Access Control): CloudFront만 버킷을 읽을 수 있게 하는 서명 방식. 예전 OAI의 후속.
resource "aws_cloudfront_origin_access_control" "assets" {
  name                              = "${var.name_prefix}-assets-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "assets" {
  enabled = true
  comment = "${var.name_prefix} static files"

  # 한국·일본 엣지를 포함하는 가장 싼 가격 등급. PriceClass_100은 미국·유럽만이라 서울에서 느리다.
  price_class = "PriceClass_200"

  origin {
    domain_name              = aws_s3_bucket.assets.bucket_regional_domain_name
    origin_id                = "s3-assets"
    origin_access_control_id = aws_cloudfront_origin_access_control.assets.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS 관리형 캐시 정책 CachingOptimized. 정적 파일에 맞는 기본값.
    # ID를 직접 적었다가 오타로 NoSuchCachePolicy가 났다. 이름으로 조회해서 쓴다.
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # 커스텀 도메인 없이 *.cloudfront.net 기본 인증서를 쓴다.
  # static.3tier.link를 붙이려면 us-east-1에 ACM 인증서가 따로 필요해서 범위 밖으로 둔다.
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "${var.name_prefix}-assets-cdn" }
}

# 버킷 정책: 이 배포(distribution)만, static/* 만 읽을 수 있다.
# 첨부파일은 static/ 밖에 있으므로 CloudFront URL로는 못 꺼낸다.
data "aws_iam_policy_document" "assets_bucket" {
  statement {
    sid       = "AllowCloudFrontStaticRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.assets.arn}/static/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.assets.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = data.aws_iam_policy_document.assets_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.assets]
}

# ---------- 앱(태스크 역할)용 정책 ----------
# 버킷 1개에 GetObject/PutObject만. compute 모듈이 태스크 역할에 붙인다. (DEC-15 최소 권한)
data "aws_iam_policy_document" "assets_rw" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.assets.arn}/*"]
  }
}

resource "aws_iam_policy" "assets_rw" {
  name        = "${var.name_prefix}-assets-rw"
  description = "App task role: read/write objects in the assets bucket"
  policy      = data.aws_iam_policy_document.assets_rw.json
}
