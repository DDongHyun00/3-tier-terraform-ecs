# 배포 역할 3tier-github-deploy의 권한 (#35). AdministratorAccess를 떼고 서비스별 정책 5개로 바꿨다.
# 근거: CloudTrail 이벤트 기록(역할 세션의 plan 호출 + 같은 코드를 로컬에서 apply·destroy한 쓰기 호출)
#       + 기록에 안 남는 작업(S3 객체, ECR 레이어, PassRole, 태그 동시 생성)은 terraform/main과 워크플로에서 보충.
#       + E07에서 만들 오토스케일링·알람·대시보드·SNS 권한은 미리 넣었다.
# main의 apply와 destroy가 모두 되어야 한다. 리소스는 이름·ARN(리전·계정·리소스 종류)으로 좁히고,
# 이름으로 못 좁히는 EC2 삭제는 태그(Project)로 좁혔다.
#
# 권한 상승 차단: 이 역할이 만들거나 고치는 IAM 역할에는 permissions boundary(3tier-ecs-boundary)가 반드시 붙어야 한다.
# 역할에 무슨 정책을 넣어도 실제 권한은 boundary 안(이미지 풀, 로그, 시크릿 읽기, assets 객체)으로 묶인다.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account     = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.region
  main_prefix = "3tier-prod" # terraform/main의 name_prefix (3tier-<env>)
  iam_prefix  = "3tier"      # IAM 역할·정책 이름 접두사

  project_tag = "3-tier-terraform-ecs" # provider default_tags의 Project 값

  ecs_boundary_name = "3tier-ecs-boundary" # modules/compute/iam.tf가 같은 이름으로 참조한다
  ecs_boundary_arn  = "arn:aws:iam::${local.account}:policy/${local.ecs_boundary_name}"

  # EC2 리소스는 ID로만 식별돼 이름으로 좁힐 수 없다. 리전·계정·리소스 종류까지는 고정한다
  ec2_arns = [
    for type in ["vpc", "subnet", "internet-gateway", "elastic-ip", "natgateway", "route-table", "security-group", "security-group-rule"] :
    "arn:aws:ec2:${local.region}:${local.account}:${type}/*"
  ]
}

# ---------- permissions boundary: main이 만드는 ECS 역할의 권한 상한 ----------
# 실행 역할(이미지 풀·로그·시크릿 주입)과 태스크 역할(assets 객체 읽기·쓰기)이 쓰는 것만.
data "aws_iam_policy_document" "ecs_boundary" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrPull"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
    resources = [aws_ecr_repository.board.arn]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${local.region}:${local.account}:log-group:/ecs/${local.main_prefix}-*"]
  }

  statement {
    sid       = "DbSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${local.region}:${local.account}:secret:${local.main_prefix}-*"]
  }

  statement {
    sid       = "DbSecretKms"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "AssetsObjects"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["arn:aws:s3:::3tier-assets-${var.account_suffix}/*"]
  }
}

resource "aws_iam_policy" "ecs_boundary" {
  name        = local.ecs_boundary_name
  description = "Permissions boundary for ECS roles created by the deploy role (#35)"
  policy      = data.aws_iam_policy_document.ecs_boundary.json
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
data "aws_iam_policy_document" "deploy_network" {
  # Describe는 리소스 수준 권한을 지원하지 않아 *
  statement {
    sid       = "Ec2Read"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }

  # 생성·연결·규칙 변경. 기본 egress 규칙(AWS가 만든 것, 태그 없음)을 지우는 Revoke가 있어 태그 조건은 걸지 않는다
  statement {
    sid = "Ec2CreateAndChange"
    actions = [
      "ec2:CreateVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:ModifySubnetAttribute",
      "ec2:CreateInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:AllocateAddress",
      "ec2:DisassociateAddress",
      "ec2:CreateNatGateway",
      "ec2:CreateRouteTable",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:CreateRoute",
      "ec2:ReplaceRoute",
      "ec2:DeleteRoute",
      "ec2:CreateSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
    ]
    resources = local.ec2_arns
  }

  # 삭제는 이 프로젝트 태그가 붙은 것만. 계정의 다른 VPC·서브넷·SG는 지울 수 없다
  statement {
    sid = "Ec2DeleteProjectOnly"
    actions = [
      "ec2:DeleteVpc",
      "ec2:DeleteSubnet",
      "ec2:DeleteInternetGateway",
      "ec2:ReleaseAddress",
      "ec2:DeleteNatGateway",
      "ec2:DeleteRouteTable",
      "ec2:DeleteSecurityGroup",
    ]
    resources = local.ec2_arns

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [local.project_tag]
    }
  }

  # 생성과 동시에 붙는 태그
  statement {
    sid       = "Ec2TagOnCreate"
    actions   = ["ec2:CreateTags"]
    resources = local.ec2_arns

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateVpc", "CreateSubnet", "CreateInternetGateway", "AllocateAddress", "CreateNatGateway", "CreateRouteTable", "CreateSecurityGroup", "AuthorizeSecurityGroupIngress", "AuthorizeSecurityGroupEgress"]
    }
  }

  # 나중에 태그를 바꾸는 것은 이 프로젝트 리소스만
  statement {
    sid       = "Ec2TagProjectOnly"
    actions   = ["ec2:CreateTags", "ec2:DeleteTags"]
    resources = local.ec2_arns

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [local.project_tag]
    }
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

  # 태스크 정의에 실행 역할·태스크 역할을 넣을 때(terraform, deploy.yml). ECS 태스크에 넘기는 것만
  statement {
    sid       = "PassRoleToEcsTasks"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account}:role/${local.iam_prefix}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
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

  # 인증서 요청·목록은 리소스 수준 권한이 없어 *
  statement {
    sid       = "AcmRequest"
    actions   = ["acm:RequestCertificate", "acm:ListCertificates", "acm:AddTagsToCertificate"]
    resources = ["*"]
  }

  # 인증서 ARN은 UUID라 이름으로 못 좁힌다. 리전·계정·종류까지 고정
  statement {
    sid = "AcmCertificate"
    actions = [
      "acm:DeleteCertificate",
      "acm:DescribeCertificate",
      "acm:GetCertificate",
      "acm:ListTagsForCertificate",
      "acm:RemoveTagsFromCertificate",
    ]
    resources = ["arn:aws:acm:${local.region}:${local.account}:certificate/*"]
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

  # 이름으로 존 찾기(data 소스)는 존 단위로 지정할 수 없어 *
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

  # 역할 생성과 권한 부여는 boundary가 붙은 역할에만. boundary 없는 역할(이 역할 자신 포함)에는 정책을 넣거나 붙일 수 없다
  statement {
    sid = "IamRoleWithBoundaryOnly"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.account}:role/${local.iam_prefix}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.ecs_boundary_arn]
    }
  }

  # iam:PermissionsBoundary 조건을 지원하지 않는 역할 작업
  statement {
    sid = "IamRoleOther"
    actions = [
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:GetRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.account}:role/${local.iam_prefix}-*"]
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
    resources = ["arn:aws:iam::${local.account}:policy/${local.iam_prefix}-*"]
  }

  # boundary 자체는 고칠 수 없다. 위 IamPolicies(3tier-*)에 걸리므로 명시적으로 거부한다
  statement {
    sid    = "DenyBoundaryChange"
    effect = "Deny"
    actions = [
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
    resources = [local.ecs_boundary_arn]
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

  # 캐시 정책 목록은 리소스 수준 권한이 없어 *
  statement {
    sid       = "CloudFrontList"
    actions   = ["cloudfront:ListCachePolicies"]
    resources = ["*"]
  }

  # 배포·OAC ID는 생성 때 정해져 이름으로 못 좁힌다. 계정·리소스 종류까지 고정(CloudFront는 글로벌이라 리전 없음)
  statement {
    sid = "CloudFrontDistribution"
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:ListTagsForResource",
    ]
    resources = ["arn:aws:cloudfront::${local.account}:distribution/*"]
  }

  statement {
    sid = "CloudFrontOac"
    actions = [
      "cloudfront:CreateOriginAccessControl",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:GetOriginAccessControlConfig",
    ]
    resources = ["arn:aws:cloudfront::${local.account}:origin-access-control/*"]
  }

  statement {
    sid       = "CloudFrontCachePolicy"
    actions   = ["cloudfront:GetCachePolicy"]
    resources = ["arn:aws:cloudfront::${local.account}:cache-policy/*"]
  }
}

# ---------- 5. 관측성 (E07: Application Auto Scaling, CloudWatch 알람·대시보드, SNS) ----------
data "aws_iam_policy_document" "deploy_observability" {
  # 조회와 정책 작업은 리소스 수준 권한이 없거나 제한적이라 *
  statement {
    sid = "AutoScalingRead"
    actions = [
      "application-autoscaling:DescribeScalableTargets",
      "application-autoscaling:DescribeScalingPolicies",
      "application-autoscaling:DescribeScalingActivities",
      "application-autoscaling:PutScalingPolicy",
      "application-autoscaling:DeleteScalingPolicy",
    ]
    resources = ["*"]
  }

  # 스케일링 대상 ARN은 ID라 리전·계정·종류까지 고정
  statement {
    sid = "AutoScalingTarget"
    actions = [
      "application-autoscaling:RegisterScalableTarget",
      "application-autoscaling:DeregisterScalableTarget",
      "application-autoscaling:TagResource",
      "application-autoscaling:UntagResource",
      "application-autoscaling:ListTagsForResource",
    ]
    resources = ["arn:aws:application-autoscaling:${local.region}:${local.account}:scalable-target/*"]
  }

  # ECS 서비스 오토스케일링의 서비스 연결 역할. 계정에 아직 없어서 첫 등록 때 만든다
  statement {
    sid       = "AutoScalingServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.account}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["ecs.application-autoscaling.amazonaws.com"]
    }
  }

  statement {
    sid       = "AlarmRead"
    actions   = ["cloudwatch:DescribeAlarms", "cloudwatch:ListDashboards"]
    resources = ["*"]
  }

  # 직접 만드는 알람(3tier-prod-*)과 목표 추적 정책이 만드는 알람(TargetTracking-*)
  statement {
    sid = "AlarmWrite"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
      "cloudwatch:ListTagsForResource",
    ]
    resources = [
      "arn:aws:cloudwatch:${local.region}:${local.account}:alarm:${local.main_prefix}-*",
      "arn:aws:cloudwatch:${local.region}:${local.account}:alarm:TargetTracking-*",
    ]
  }

  # 대시보드는 글로벌 리소스라 ARN에 리전이 없다
  statement {
    sid       = "Dashboard"
    actions   = ["cloudwatch:PutDashboard", "cloudwatch:GetDashboard", "cloudwatch:DeleteDashboards"]
    resources = ["arn:aws:cloudwatch::${local.account}:dashboard/${local.main_prefix}-*"]
  }

  statement {
    sid = "Sns"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:ListSubscriptionsByTopic",
      "sns:GetSubscriptionAttributes",
      "sns:SetSubscriptionAttributes",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource",
    ]
    resources = ["arn:aws:sns:${local.region}:${local.account}:${local.main_prefix}-*"]
  }
}

# ---------- 정책 생성과 부착 ----------
locals {
  deploy_policies = {
    state-ecr     = data.aws_iam_policy_document.deploy_state_ecr.json
    network       = data.aws_iam_policy_document.deploy_network.json
    compute       = data.aws_iam_policy_document.deploy_compute.json
    data          = data.aws_iam_policy_document.deploy_data.json
    observability = data.aws_iam_policy_document.deploy_observability.json
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
