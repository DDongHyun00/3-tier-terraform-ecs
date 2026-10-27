# 배포 역할 3tier-github-deploy의 권한 (#35). AdministratorAccess를 떼고 서비스별 정책 4개로 바꿨다.
# 근거: CloudTrail 이벤트 기록(역할 세션의 plan 호출 + 같은 코드를 로컬에서 apply·destroy한 쓰기 호출)
#       + 기록에 안 남는 작업(S3 객체, ECR 레이어, PassRole, 태그 동시 생성)은 terraform/main과 워크플로에서 보충.
# main의 apply와 destroy가 모두 되어야 한다. 리소스는 이름(3tier-prod-)·ARN으로 좁힐 수 있는 곳만 좁혔다.
# 3tier-prod-로 좁힌 이유: 3tier-로 두면 이 역할(3tier-github-deploy)과 이 정책들까지 고칠 수 있어 스스로 권한을 키울 수 있다.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account     = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.region
  main_prefix = "3tier-prod" # terraform/main의 name_prefix (3tier-<env>)
}

# ---------- 1. state 버킷 + ECR (모든 워크플로) ----------
data "aws_iam_policy_document" "deploy_state_ecr" {
  statement {
    sid       = "TfStateList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }

  # main state와 잠금 파일(.tflock)만. bootstrap state는 읽지 못한다
  statement {
    sid       = "TfStateMain"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/main/*"]
  }

  # 리소스 수준 권한을 지원하지 않는 작업이라 *
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrRepo"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:ListTagsForResource",
    ]
    resources = [aws_ecr_repository.board.arn]
  }
}

# ---------- 2. 네트워크 (EC2) ----------
# EC2 리소스 ARN은 생성 때 정해지는 ID(vpc-xxxx)라 이름 접두사로 좁힐 수 없어 *
data "aws_iam_policy_document" "deploy_network" {
  statement {
    sid       = "Ec2Read"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }

  statement {
    sid = "Ec2Write"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:DisassociateAddress",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:CreateRoute",
      "ec2:ReplaceRoute",
      "ec2:DeleteRoute",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }
}

# ---------- 3. 컴퓨트 (ECS, ELB, ACM, Route 53, Logs, IAM) ----------
data "aws_iam_policy_document" "deploy_compute" {
  # 조회 작업과 태스크 정의 등록·해제는 리소스 수준 권한이 없거나 제한적이라 *
  statement {
    sid = "EcsReadAndTaskDef"
    actions = [
      "ecs:Describe*",
      "ecs:List*",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
    ]
    resources = ["*"]
  }

  statement {
    sid = "EcsWrite"
    actions = [
      "ecs:CreateCluster",
      "ecs:UpdateCluster",
      "ecs:UpdateClusterSettings",
      "ecs:DeleteCluster",
      "ecs:CreateService",
      "ecs:UpdateService",
      "ecs:DeleteService",
      "ecs:TagResource",
      "ecs:UntagResource",
    ]
    resources = [
      "arn:aws:ecs:${local.region}:${local.account}:cluster/${local.main_prefix}-*",
      "arn:aws:ecs:${local.region}:${local.account}:service/${local.main_prefix}-*/*",
      "arn:aws:ecs:${local.region}:${local.account}:task-definition/${local.main_prefix}-*:*",
    ]
  }

  # 태스크 정의에 실행 역할·태스크 역할을 넣을 때(terraform, deploy.yml)
  statement {
    sid       = "PassEcsRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account}:role/${local.main_prefix}-*"]
  }

  statement {
    sid       = "ElbRead"
    actions   = ["elasticloadbalancing:Describe*"]
    resources = ["*"]
  }

  statement {
    sid = "ElbWrite"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyListenerAttributes",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:${local.region}:${local.account}:loadbalancer/app/${local.main_prefix}-*",
      "arn:aws:elasticloadbalancing:${local.region}:${local.account}:targetgroup/${local.main_prefix}-*",
      "arn:aws:elasticloadbalancing:${local.region}:${local.account}:listener/app/${local.main_prefix}-*",
    ]
  }

  # 인증서 ARN은 UUID라 이름으로 좁힐 수 없어 *
  statement {
    sid = "Acm"
    actions = [
      "acm:RequestCertificate",
      "acm:DeleteCertificate",
      "acm:DescribeCertificate",
      "acm:GetCertificate",
      "acm:ListCertificates",
      "acm:ListTagsForCertificate",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
    ]
    resources = ["*"]
  }

  # 호스팅 존 하나(3tier.link)만
  statement {
    sid = "Route53Zone"
    actions = [
      "route53:GetHostedZone",
      "route53:ListResourceRecordSets",
      "route53:ChangeResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.main.zone_id}"]
  }

  # 이름으로 존 찾기(data 소스)와 변경 반영 대기는 존 단위로 지정할 수 없어 *, change/*
  statement {
    sid       = "Route53Lookup"
    actions   = ["route53:ListHostedZones", "route53:ListHostedZonesByName"]
    resources = ["*"]
  }

  statement {
    sid       = "Route53Change"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  # 로그 그룹 목록 조회는 리소스 수준 권한이 없어 *
  statement {
    sid       = "LogsRead"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  statement {
    sid = "LogsWrite"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:TagLogGroup",
    ]
    resources = ["arn:aws:logs:${local.region}:${local.account}:log-group:/ecs/${local.main_prefix}-*"]
  }

  # ECS 실행 역할·태스크 역할(3tier-prod-*)만. 배포 역할 자신(3tier-github-deploy)은 고칠 수 없다
  statement {
    sid = "IamRoles"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.account}:role/${local.main_prefix}-*"]
  }

  # 붙일 수 있는 정책도 제한한다. 없으면 태스크 역할에 AdministratorAccess를 붙여 우회할 수 있다
  statement {
    sid       = "IamAttachAllowedPolicies"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["arn:aws:iam::${local.account}:role/${local.main_prefix}-*"]

    condition {
      test     = "ArnLike"
      variable = "iam:PolicyARN"
      values = [
        "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy",
        "arn:aws:iam::${local.account}:policy/${local.main_prefix}-*",
      ]
    }
  }

  statement {
    sid = "IamPolicies"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = ["arn:aws:iam::${local.account}:policy/${local.main_prefix}-*"]
  }
}

# ---------- 4. 데이터 (RDS, Secrets Manager, KMS, S3 assets, CloudFront) ----------
data "aws_iam_policy_document" "deploy_data" {
  statement {
    sid       = "RdsRead"
    actions   = ["rds:Describe*", "rds:ListTagsForResource"]
    resources = ["*"]
  }

  # RDS 이름은 첫 글자가 영문이어야 해서 db-3tier-prod*. CreateDBInstance는 기본 파라미터 그룹·옵션 그룹도 검사한다
  statement {
    sid = "RdsWrite"
    actions = [
      "rds:CreateDBInstance",
      "rds:ModifyDBInstance",
      "rds:DeleteDBInstance",
      "rds:CreateDBSubnetGroup",
      "rds:ModifyDBSubnetGroup",
      "rds:DeleteDBSubnetGroup",
      "rds:AddTagsToResource",
      "rds:RemoveTagsFromResource",
    ]
    resources = [
      "arn:aws:rds:${local.region}:${local.account}:db:db-${local.main_prefix}*",
      "arn:aws:rds:${local.region}:${local.account}:subgrp:db-${local.main_prefix}*",
      "arn:aws:rds:${local.region}:${local.account}:pg:default.*",
      "arn:aws:rds:${local.region}:${local.account}:og:default:*",
    ]
  }

  # ARN 끝에 무작위 6자가 붙으므로 이름 뒤를 *로
  statement {
    sid = "Secrets"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:UpdateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:PutSecretValue",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:ListSecretVersionIds",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
    ]
    resources = ["arn:aws:secretsmanager:${local.region}:${local.account}:secret:${local.main_prefix}-*"]
  }

  # AWS 관리형 키(aws/secretsmanager, aws/rds)는 키 ID로 지정할 수 없어 *. 대신 두 서비스를 거친 호출만
  statement {
    sid       = "KmsViaServices"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey", "kms:CreateGrant"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "secretsmanager.${local.region}.amazonaws.com",
        "rds.${local.region}.amazonaws.com",
      ]
    }
  }

  statement {
    sid = "AssetsBucket"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucket*",
      "s3:GetAccelerateConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutBucketTagging",
    ]
    resources = ["arn:aws:s3:::3tier-assets-${var.account_suffix}"]
  }

  # force_destroy: 객체가 남아 있어도 버킷을 지울 수 있게
  statement {
    sid       = "AssetsObjectsDelete"
    actions   = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
    resources = ["arn:aws:s3:::3tier-assets-${var.account_suffix}/*"]
  }

  # 배포·OAC ID는 생성 때 정해져 이름으로 좁힐 수 없어 *
  statement {
    sid = "CloudFront"
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:ListTagsForResource",
      "cloudfront:CreateOriginAccessControl",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:GetOriginAccessControlConfig",
      "cloudfront:GetCachePolicy",
      "cloudfront:ListCachePolicies",
    ]
    resources = ["*"]
  }
}

# ---------- 정책 생성과 부착 ----------
locals {
  deploy_policies = {
    state-ecr = data.aws_iam_policy_document.deploy_state_ecr.json
    network   = data.aws_iam_policy_document.deploy_network.json
    compute   = data.aws_iam_policy_document.deploy_compute.json
    data      = data.aws_iam_policy_document.deploy_data.json
  }
}

resource "aws_iam_policy" "github_deploy" {
  for_each = local.deploy_policies

  name        = "3tier-github-deploy-${each.key}"
  description = "GitHub Actions deploy role: ${each.key} (least privilege, #35)"
  policy      = each.value
}

resource "aws_iam_role_policy_attachment" "github_deploy" {
  for_each = aws_iam_policy.github_deploy

  role       = aws_iam_role.github_deploy.name
  policy_arn = each.value.arn
}
