data "aws_canonical_user_id" "this" {}

locals {
  create_bucket = var.create_bucket

  bucket_name = "s3-bucket-${random_pet.this.id}"

  attach_policy = true
  policy = "${aws_s3_bucket_policy.this}"


#resource generating name to avoid circular dependencies
resource "random_pet" "this" {
  length = 2
}

#data "aws_iam_policy_document" "bucket_policy" {
 # statement {
  #  #principals = "*"
#
 #   actions = [
  #    "s3:GetObject",
   # ]
#
 #   resources = [
  #    "arn:aws:s3:::${local.bucket_name}",
   # ]
  #}
#}

resource "aws_s3_bucket" "this" {
  count = local.create_bucket ? 1 : 0

  bucket        = local.bucket_name
  bucket_prefix = var.bucket_prefix

  force_destroy       = var.force_destroy
  object_lock_enabled = var.object_lock_enabled
  tags                = var.tags

  #bucket policies:
  #attach_policy = true
  #policy = data.aws_iam_policy_document.bucket_policy
}

resource "aws_s3_bucket_policy" "this" {
  count = local.create_bucket && local.attach_policy ? 1 : 0

  bucket = aws_s3_bucket.this[0].id
  policy = file("bucketPolicy.json")
}

#Add index.html to the bucket upon creation
resource "aws_s3_object" "index_document" {
  bucket       = aws_s3_bucket.this[0].id
  key          = "index.html"
  source       = "website/index.html"
  content_type = "text/html"
  acl          = "public-read"
  tags         = {
    "category" = "website"
  }
}

#Add error.html to the bucket upon creation
resource "aws_s3_object" "error_document" {
  bucket       = aws_s3_bucket.this[0].id
  key          = "error.html"
  source       = "website/error.html"
  content_type = "text/html"
  acl          = "public-read"
  tags         = {
    "category" = "website"
  }
}

#Static Website configuration
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.this[0].id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_logging" "this" {
  count = local.create_bucket && length(keys(var.logging)) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  target_bucket = var.logging["target_bucket"]
  target_prefix = try(var.logging["target_prefix"], null)
}

resource "aws_s3_bucket_acl" "this" {
  count = local.create_bucket && ((var.acl != null && var.acl != "null") || length(local.grants) > 0) ? 1 : 0

  bucket                = aws_s3_bucket.this[0].id
  expected_bucket_owner = var.expected_bucket_owner

  # hack when `null` value can't be used (eg, from terragrunt, https://github.com/gruntwork-io/terragrunt/pull/1367)
  acl = var.acl == "null" ? null : var.acl

  dynamic "access_control_policy" {
    for_each = length(local.grants) > 0 ? [true] : []

    content {
      dynamic "grant" {
        for_each = local.grants

        content {
          permission = grant.value.permission

          grantee {
            type          = grant.value.type
            id            = try(grant.value.id, null)
            uri           = try(grant.value.uri, null)
            email_address = try(grant.value.email, null)
          }
        }
      }

      owner {
        id           = try(var.owner["id"], data.aws_canonical_user_id.this.id)
        display_name = try(var.owner["display_name"], null)
      }
    }
  }
}

resource "aws_s3_bucket_website_configuration" "this" {
  count = local.create_bucket && length(keys(var.website)) > 0 ? 1 : 0

  bucket                = aws_s3_bucket.this[0].id
  expected_bucket_owner = var.expected_bucket_owner

  dynamic "index_document" {
    for_each = try([var.website["index_document"]], [])

    content {
      suffix = index_document.value
    }
  }

  dynamic "error_document" {
    for_each = try([var.website["error_document"]], [])

    content {
      key = error_document.value
    }
  }

  dynamic "redirect_all_requests_to" {
    for_each = try([var.website["redirect_all_requests_to"]], [])

    content {
      host_name = redirect_all_requests_to.value.host_name
      protocol  = try(redirect_all_requests_to.value.protocol, null)
    }
  }

  dynamic "routing_rule" {
    for_each = try(flatten([var.website["routing_rules"]]), [])

    content {
      dynamic "condition" {
        for_each = [try([routing_rule.value.condition], [])]

        content {
          http_error_code_returned_equals = try(routing_rule.value.condition["http_error_code_returned_equals"], null)
          key_prefix_equals               = try(routing_rule.value.condition["key_prefix_equals"], null)
        }
      }

      redirect {
        host_name               = try(routing_rule.value.redirect["host_name"], null)
        http_redirect_code      = try(routing_rule.value.redirect["http_redirect_code"], null)
        protocol                = try(routing_rule.value.redirect["protocol"], null)
        replace_key_prefix_with = try(routing_rule.value.redirect["replace_key_prefix_with"], null)
        replace_key_with        = try(routing_rule.value.redirect["replace_key_with"], null)
      }
    }
  }
}