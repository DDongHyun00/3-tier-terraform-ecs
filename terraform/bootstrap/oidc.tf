# GitHub Actions가 액세스 키 없이 AWS 역할을 수임하기 위한 OIDC 설정.
# 흐름: 워크플로 실행 → GitHub이 서명한 토큰 발급 → STS AssumeRoleWithWebIdentity → 아래 신뢰 조건(이 레포의 main 브랜치·PR)과 맞으면 1시간짜리 임시 자격 증명.

# 1. "GitHub이 서명한 토큰을 믿는다"는 등록. 계정에 하나만 있으면 된다.
#    thumbprint_list는 AWS가 GitHub 인증서를 자체 검증하므로 생략한다.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# 2. 신뢰 정책: 누가 이 역할을 수임할 수 있나.
#    sub 조건이 핵심이다. 이 줄이 없으면 GitHub의 아무 레포나 이 역할을 쓸 수 있다.
locals {
  github_owner      = split("/", var.github_repo)[0]
  github_repo_name  = split("/", var.github_repo)[1]
  github_sub_prefix = "repo:${local.github_owner}@${var.github_owner_id}/${local.github_repo_name}@${var.github_repo_id}"
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    # 토큰이 AWS STS용으로 발급된 것인지
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # 이 레포의 main 브랜치(apply·배포)와 PR(plan)에서 실행된 워크플로만.
    # 2026-07-15 이후 만든 레포는 sub에 불변 ID가 붙는다: repo:<owner>@<owner_id>/<name>@<repo_id>:...
    # 이름만 쓰면 매치되지 않아 AccessDenied가 난다 (TS-12). ID를 쓰면 레포 이름이 바뀌거나 재사용돼도 안전하다.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.github_sub_prefix}:ref:refs/heads/main",
        "${local.github_sub_prefix}:pull_request",
        # 승인 배포(#102, DEC-61): production 잡은 Environment를 써서 sub가 environment:production이 된다
        "${local.github_sub_prefix}:environment:production",
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "3tier-github-deploy"
  description        = "GitHub Actions deploy role for ${var.github_repo} (OIDC)"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

# 3. 권한: AdministratorAccess로 시작했다가(DEC-21) #35에서 서비스별 고객 관리형 정책으로 좁혔다.
#    정책 내용은 deploy_policies.tf.
