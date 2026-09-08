# ---------------------------------------------------------------------------
# GitHub Actions → AWS, without access keys
#
# The obvious way to let a pipeline deploy to AWS is to create an IAM user,
# generate an access key pair, and paste it into GitHub Secrets. It works, and
# it means a permanent credential to your AWS account now exists in two places
# forever. It does not expire. It is not tied to a repository, a branch or a
# workflow run. If it leaks — in a log, in a fork, in a compromised action —
# whoever finds it has your account until somebody notices.
#
# OIDC federation removes the credential entirely:
#
#   1. The workflow asks GitHub for a signed JSON Web Token describing the
#      run: which repository, which branch, which workflow, which environment.
#   2. It presents that token to AWS STS with AssumeRoleWithWebIdentity.
#   3. STS validates the signature against GitHub's public keys, checks the
#      token's claims against this role's trust policy, and returns
#      credentials valid for the length of the job.
#
# Nothing is stored. The trust policy below is what makes it safe: it names
# one repository and one set of refs, so a token from anywhere else is
# rejected even though it is perfectly valid and signed by GitHub.
# ---------------------------------------------------------------------------

# An account can only have one OIDC provider per issuer URL, and it is shared
# by every repository. Create it here if this is the first project to need it;
# set create_github_oidc_provider = false to reuse an existing one.
resource "aws_iam_openid_connect_provider" "github" {
  count = local.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.github_oidc_thumbprints

  tags = {
    Name = "github-actions-oidc"
  }
}

data "aws_iam_openid_connect_provider" "github" {
  count = local.use_existing_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"
}

# ---------------------------------------------------------------------------
# Trust policy — who may assume this role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "github_actions_trust" {
  count = local.create_deploy_role ? 1 : 0

  statement {
    sid     = "GitHubActionsAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    # The audience claim. GitHub sets this to sts.amazonaws.com when the
    # workflow uses the official credentials action.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The subject claim: the specific repository and ref the token was issued
    # for. This is the whole security boundary.
    #
    # Never write this as "repo:owner/*" or, worse, leave it out. Without a
    # sub condition, ANY GitHub Actions workflow in ANY repository on GitHub
    # can assume this role — the token is genuine, it just is not yours.
    #
    # local.github_subjects covers both the classic and the immutable claim
    # formats; see locals.tf for why that matters.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_subjects
    }
  }
}

# ---------------------------------------------------------------------------
# Permissions policy — what the role may do
#
# Scoped to this bucket and this distribution, and to the specific actions a
# deployment performs. Nothing here can read another bucket, touch another
# distribution, or create infrastructure.
#
# Note what is absent: no s3:PutBucketPolicy, no s3:DeleteBucket, no
# cloudfront:UpdateDistribution. The pipeline deploys the site; it does not
# change the platform. Terraform does that, run by an engineer who reviewed
# a plan.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "github_actions_deploy" {
  count = local.create_deploy_role ? 1 : 0

  # `aws s3 sync` lists the bucket to work out what has changed. Without
  # ListBucket it re-uploads everything and cannot honour --delete.
  statement {
    sid    = "ListSiteBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.site.arn]
  }

  statement {
    sid    = "ManageSiteObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }

  # Invalidation only. The pipeline may clear the cache; it may not
  # reconfigure the distribution.
  statement {
    sid    = "InvalidateDistributionCache"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations",
    ]
    resources = [aws_cloudfront_distribution.site.arn]
  }
}

resource "aws_iam_role" "github_actions" {
  count = local.create_deploy_role ? 1 : 0

  name        = "${local.name_prefix}-github-actions-deploy"
  description = "Assumed by GitHub Actions in ${var.github_repository} to deploy the static site"

  assume_role_policy = data.aws_iam_policy_document.github_actions_trust[0].json

  # Credentials last for the job, not the day. A deployment takes a couple of
  # minutes; an hour-long credential is an hour-long window.
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  count = local.create_deploy_role ? 1 : 0

  name   = "deploy-static-site"
  role   = aws_iam_role.github_actions[0].id
  policy = data.aws_iam_policy_document.github_actions_deploy[0].json
}
