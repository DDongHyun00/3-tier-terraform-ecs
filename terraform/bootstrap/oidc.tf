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

    # 이 레포의 main 브랜치(apply·배포)와 PR(plan)에서 실행된 워크플로만
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_repo}:pull_request",
      ]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "3tier-github-deploy"
  description        = "GitHub Actions deploy role for ${var.github_repo} (OIDC)"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

# 3. 권한: AdministratorAccess로 시작한다 (DEC-21).
#    필요한 권한 목록은 실제 apply를 해 봐야 알 수 있으므로, E06(#35)에서
#    CloudTrail·Access Analyzer의 호출 기록을 보고 서비스별 정책으로 좁힌다.
#    그 전까지는 위 신뢰 조건(레포·브랜치 제한)이 유일한 제한이다.
resource "aws_iam_role_policy_attachment" "github_deploy_admin" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
