# 배포 역할 3tier-github-deploy의 권한 (#35). AdministratorAccess를 떼고 서비스별 정책 5개로 바꿨다.
# 근거: CloudTrail 이벤트 기록(역할 세션의 plan 호출 + 같은 코드를 로컬에서 apply·destroy한 쓰기 호출)
#       + 기록에 안 남는 작업(S3 객체, ECR 레이어, PassRole, 태그 동시 생성)은 terraform/main과 워크플로에서 보충.
#       + E07에서 만들 오토스케일링·알람·대시보드·SNS 권한은 미리 넣었다.
# main의 apply와 destroy가 모두 되어야 한다. 리소스는 이름·ARN(리전·계정·리소스 종류)으로 좁히고,
# 이름으로 못 좁히는 EC2 삭제는 태그(Project)로 좁혔다.
#
# 권한 상승 차단: 이 역할이 만들거나 고치는 IAM 역할에는 permissions boundary(3tier-ecs-boundary)가 반드시 붙어야 한다.
# 역할에 무슨 정책을 넣어도 실제 권한은 boundary 안(이미지 풀, 로그, 시크릿 읽기, assets 객체)으로 묶인다.
# IAM 역할·정책·PassRole은 main 것(3tier-prod-*)만. 이 역할 자신·자기 정책·boundary는 명시적으로 거부한다.

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account     = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.region
  main_prefix = "3tier-prod" # terraform/main의 name_prefix (3tier-<env>)

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

  # ECS on EC2(#87): 컨테이너 인스턴스 역할이 쓰는 ECS 에이전트 작업. AmazonEC2ContainerServiceforEC2Role의 작업과 같고 클러스터는 이 프로젝트 것만
  statement {
    sid       = "EcsAgentDiscover"
    actions   = ["ecs:DiscoverPollEndpoint", "ec2:DescribeTags"]
    resources = ["*"]
  }

  statement {
    sid = "EcsAgentCluster"
    actions = [
      "ecs:RegisterContainerInstance",
      "ecs:DeregisterContainerInstance",
      "ecs:UpdateContainerInstancesState",
      "ecs:Submit*",
      "ecs:Poll",
      "ecs:StartTelemetrySession",
      "ecs:TagResource",
      "ecs:ListTagsForResource",
    ]
    resources = [
      "arn:aws:ecs:${local.region}:${local.account}:cluster/${local.main_prefix}-*",
      "arn:aws:ecs:${local.region}:${local.account}:container-instance/${local.main_prefix}-*/*",
    ]
  }

  # SSM Session Manager 접속(SSH 키 없음, DEC-50 D7). AmazonSSMManagedInstanceCore의 작업과 같다
  statement {
    sid = "SsmManagedInstance"
    actions = [
      "ssm:DescribeAssociation",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:DescribeDocument",
      "ssm:GetManifest",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }

  # ---- 관제 서버 역할(3tier-prod-mon-*, E11)의 상한. 실제 권한은 main의 역할 정책이 정한다 ----
  # Prometheus ec2_sd_configs가 수집 대상 인스턴스를 찾는다(DEC-55). 조회는 리소스 수준 권한이 없어 *
  statement {
    sid       = "MonitoringDiscoverInstances"
    actions   = ["ec2:DescribeInstances", "ec2:DescribeAvailabilityZones"]
    resources = ["*"]
  }

  # Grafana 알림 → 기존 알람 토픽(DEC-58, #95). 토픽이 KMS로 암호화돼 게시자에게 키 권한이 필요하다
  statement {
    sid       = "MonitoringAlertPublish"
    actions   = ["sns:Publish", "sns:GetTopicAttributes"]
    resources = ["arn:aws:sns:${local.region}:${local.account}:${local.main_prefix}-*"]
  }

  statement {
    sid       = "MonitoringAlertTopicKey"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = [aws_kms_key.alerts.arn]
  }

  # Grafana CloudWatch 데이터 소스(ALB·RDS 지표, #95). 읽기 작업은 리소스 수준 권한이 없어 *
  statement {
    sid = "MonitoringCloudWatchRead"
    actions = [
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "tag:GetResources",
    ]
    resources = ["*"]
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
  # GetSecurityGroupsForVpc: ALB 생성 때 ELB가 이 역할로 호출한다(invokedBy, Access Analyzer 대조로 확인)
  statement {
    sid       = "Ec2Read"
    actions   = ["ec2:Describe*", "ec2:GetSecurityGroupsForVpc"]
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

  # EIP 연결 해제(destroy 때 ReleaseAddress 앞에 호출). 연결 ID(eipassoc-)로 요청해 리소스 수준 권한이 없다.
  # EIP ARN으로 좁혔다가 destroy가 UnauthorizedOperation(리소스 */*)로 막혔다. 태그 조건도 못 쓰므로 *, 리전만 고정
  statement {
    sid       = "Ec2DisassociateAddress"
    actions   = ["ec2:DisassociateAddress"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
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
      "ecs:CreateCapacityProvider",
      "ecs:UpdateCapacityProvider",
      "ecs:DeleteCapacityProvider",
      "ecs:PutClusterCapacityProviders",
    ]
    resources = [
      "arn:aws:ecs:${local.region}:${local.account}:cluster/${local.main_prefix}-*",
      "arn:aws:ecs:${local.region}:${local.account}:service/${local.main_prefix}-*/*",
      "arn:aws:ecs:${local.region}:${local.account}:task-definition/${local.main_prefix}-*:*",
      "arn:aws:ecs:${local.region}:${local.account}:capacity-provider/${local.main_prefix}-*",
    ]
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
    actions   = ["acm:RequestCertificate", "acm:ListCertificates"]
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
      "acm:AddTagsToCertificate",
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
    resources = ["arn:aws:iam::${local.account}:role/${local.main_prefix}-*"]

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
    resources = ["arn:aws:iam::${local.account}:role/${local.main_prefix}-*"]
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

  # 이 역할 자신, 이 역할의 정책, boundary는 어떤 Allow가 있어도 고칠 수 없다(권한 상승·신뢰 조건 확대 차단)
  statement {
    sid    = "DenySelfAndBoundaryChange"
    effect = "Deny"
    actions = [
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = [
      aws_iam_role.github_deploy.arn,
      "arn:aws:iam::${local.account}:policy/3tier-github-deploy*",
      local.ecs_boundary_arn,
    ]
  }
}

# ---------- 3b. 컴퓨트: ECS on EC2 (#87, #88) ----------
# 시작 템플릿·ASG·인스턴스 프로필·AMI 조회. compute 정책이 관리형 정책 한도(6,144자)를 넘어 따로 뒀다
data "aws_iam_policy_document" "deploy_compute_ec2" {
  # 컨테이너 인스턴스 역할을 EC2(인스턴스 프로필)에 넘길 때. ECS 태스크용 PassRole과 서비스 조건이 달라 문장을 나눈다
  statement {
    sid       = "PassRoleToEc2"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account}:role/${local.main_prefix}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid = "IamInstanceProfile"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
    ]
    resources = ["arn:aws:iam::${local.account}:instance-profile/${local.main_prefix}-*"]
  }

  # 조회는 리소스 수준 권한이 없어 *
  statement {
    sid       = "AutoScalingRead"
    actions   = ["autoscaling:Describe*"]
    resources = ["*"]
  }

  statement {
    sid = "AutoScalingWrite"
    actions = [
      "autoscaling:CreateAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
      "autoscaling:DeleteAutoScalingGroup",
      "autoscaling:SetInstanceProtection",
      "autoscaling:CreateOrUpdateTags",
      "autoscaling:DeleteTags",
    ]
    resources = ["arn:aws:autoscaling:${local.region}:${local.account}:autoScalingGroup:*:autoScalingGroupName/${local.main_prefix}-*"]
  }

  # 시작 템플릿. 생성 때 이름이 ARN에 없어(lt-ID) 리전만 고정하고, 삭제·수정은 프로젝트 태그가 붙은 것만
  statement {
    sid       = "Ec2LaunchTemplateCreate"
    actions   = ["ec2:CreateLaunchTemplate"]
    resources = ["arn:aws:ec2:${local.region}:${local.account}:launch-template/*"]
  }

  statement {
    sid = "Ec2LaunchTemplateProjectOnly"
    actions = [
      "ec2:CreateLaunchTemplateVersion",
      "ec2:ModifyLaunchTemplate",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteLaunchTemplateVersions",
    ]
    resources = ["arn:aws:ec2:${local.region}:${local.account}:launch-template/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [local.project_tag]
    }
  }

  # ASG를 시작 템플릿으로 만들 때 호출자에게 RunInstances 권한이 있는지 확인한다. 인스턴스는 이 리전에서만
  statement {
    sid     = "Ec2RunInstancesForAsg"
    actions = ["ec2:RunInstances"]
    resources = [
      "arn:aws:ec2:${local.region}:${local.account}:instance/*",
      "arn:aws:ec2:${local.region}:${local.account}:volume/*",
      "arn:aws:ec2:${local.region}:${local.account}:network-interface/*",
      "arn:aws:ec2:${local.region}:${local.account}:launch-template/*",
      "arn:aws:ec2:${local.region}:${local.account}:subnet/*",
      "arn:aws:ec2:${local.region}:${local.account}:security-group/*",
      "arn:aws:ec2:${local.region}::image/*",
    ]
  }

  statement {
    sid       = "Ec2TagOnLaunch"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:aws:ec2:${local.region}:${local.account}:*/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateLaunchTemplate", "RunInstances"]
    }
  }

  # ECS 최적화 AMI ID 조회(공개 파라미터, DEC-50 D6)
  statement {
    sid       = "SsmEcsAmiParameter"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${local.region}::parameter/aws/service/ecs/optimized-ami/*"]
  }

  # 태스크 정의에 실행 역할·태스크 역할을 넣을 때(terraform, deploy.yml). ECS 태스크에 넘기는 것만
  statement {
    sid       = "PassRoleToEcsTasks"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account}:role/${local.main_prefix}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
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

  # 캐시 정책 조회(읽기 전용). s3.tf가 AWS 관리형 Managed-CachingOptimized를 이름으로 찾으므로
  # 계정 소유 cache-policy/*로 좁히면 조회가 막힌다. 목록 조회는 리소스 수준 권한도 없어 *
  statement {
    sid       = "CloudFrontCachePolicyRead"
    actions   = ["cloudfront:ListCachePolicies", "cloudfront:GetCachePolicy"]
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

  # 알람 토픽은 bootstrap에 있고(alerts.tf) main은 이름으로 찾는다(data 소스). 목록 조회는 리소스 수준 권한이 없어 *
  statement {
    sid       = "SnsList"
    actions   = ["sns:ListTopics"]
    resources = ["*"]
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
# ---------- 6. E11 네트워크·관제 (#111) ----------
# 관제 VPC·피어링(#91), 리전 NAT(DEC-41), S3 게이트웨이 엔드포인트, 관제 서버 단독 인스턴스(#92),
# 앱 지표 탐색 Cloud Map·지표 경로 차단 리스너 규칙(#94).
# network 정책에 넣지 않고 나눈 이유: 관리형 정책 크기 상한(6,144자)과 E11 변경을 한 묶음으로 되돌릴 수 있게 하려고.
locals {
  e11_ec2_arns = [
    for type in ["vpc", "vpc-peering-connection", "vpc-endpoint", "route-table", "natgateway", "elastic-ip"] :
    "arn:aws:ec2:${local.region}:${local.account}:${type}/*"
  ]
}

data "aws_iam_policy_document" "deploy_network_e11" {
  # 피어링 생성·수락. 같은 계정·리전이라 aws_vpc_peering_connection(auto_accept)이 두 작업을 함께 부른다
  statement {
    sid = "VpcPeeringCreateAndAccept"
    actions = [
      "ec2:CreateVpcPeeringConnection",
      "ec2:AcceptVpcPeeringConnection",
      "ec2:ModifyVpcPeeringConnectionOptions",
    ]
    resources = local.e11_ec2_arns
  }

  # S3 게이트웨이 엔드포인트. 생성 때 라우트 테이블에 경로를 넣는다
  statement {
    sid       = "VpcEndpointCreateAndChange"
    actions   = ["ec2:CreateVpcEndpoint", "ec2:ModifyVpcEndpoint"]
    resources = local.e11_ec2_arns
  }

  # 리전 NAT 수동 모드: AZ별 EIP 연결·해제(availability_zone_address)
  statement {
    sid       = "RegionalNatAddress"
    actions   = ["ec2:AssociateNatGatewayAddress", "ec2:DisassociateNatGatewayAddress"]
    resources = local.e11_ec2_arns
  }

  # 삭제는 이 프로젝트 태그가 붙은 것만
  statement {
    sid       = "E11DeleteProjectOnly"
    actions   = ["ec2:DeleteVpcPeeringConnection", "ec2:DeleteVpcEndpoints"]
    resources = local.e11_ec2_arns

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [local.project_tag]
    }
  }

  statement {
    sid       = "E11TagOnCreate"
    actions   = ["ec2:CreateTags"]
    resources = local.e11_ec2_arns

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateVpcPeeringConnection", "CreateVpcEndpoint"]
    }
  }

  # 생성 뒤 태그 변경(Name·default_tags 바뀔 때)은 이 프로젝트 리소스만. network 정책의 Ec2TagProjectOnly에는
  # 피어링·엔드포인트·인스턴스 ARN이 없어서 따로 둔다
  statement {
    sid       = "E11TagProjectOnly"
    actions   = ["ec2:CreateTags", "ec2:DeleteTags"]
    resources = concat(local.e11_ec2_arns, ["arn:aws:ec2:${local.region}:${local.account}:instance/*"])

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [local.project_tag]
    }
  }

  # 관제 서버는 ASG가 아닌 단독 인스턴스라 배포 역할이 직접 종료한다(RunInstances는 compute-ec2 정책에 있다)
  statement {
    sid       = "Ec2InstanceProjectOnly"
    actions   = ["ec2:TerminateInstances", "ec2:ModifyInstanceAttribute", "ec2:StopInstances", "ec2:StartInstances"]
    resources = ["arn:aws:ec2:${local.region}:${local.account}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Project"
      values   = [local.project_tag]
    }
  }

  # AL2023 arm64 AMI ID 조회(공개 파라미터, DEC-54)
  statement {
    sid       = "SsmAl2023AmiParameter"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${local.region}::parameter/aws/service/ami-amazon-linux-latest/*"]
  }

  # 앱 태스크 지표 탐색용 Cloud Map 비공개 DNS 네임스페이스·서비스(DEC-55, #94).
  # 네임스페이스 생성 때 Cloud Map이 호출자 권한으로 Route 53 비공개 호스팅 존을 만든다(Cloud Map API 권한 참조)
  statement {
    sid = "CloudMapNamespaceAndService"
    actions = [
      "servicediscovery:CreatePrivateDnsNamespace",
      "servicediscovery:DeleteNamespace",
      "servicediscovery:GetNamespace",
      "servicediscovery:CreateService",
      "servicediscovery:DeleteService",
      "servicediscovery:GetService",
      "servicediscovery:UpdateService",
      "servicediscovery:GetOperation",
      "servicediscovery:ListInstances",
      "servicediscovery:GetInstance",
      "servicediscovery:DeregisterInstance",
      "servicediscovery:ListNamespaces",
      "servicediscovery:ListServices",
      "servicediscovery:ListOperations",
      "servicediscovery:TagResource",
      "servicediscovery:UntagResource",
      "servicediscovery:ListTagsForResource",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  # destroy 때 등록이 남은 Cloud Map 서비스를 지우려면(force_destroy) 인스턴스 등록 해제를 부른다.
  # Cloud Map API 권한 참조상 DeregisterInstance는 Route 53 헬스 체크 조회·삭제·수정도 요구한다(헬스 체크는 쓰지 않는다)
  statement {
    sid       = "Route53HealthCheckForCloudMap"
    actions   = ["route53:GetHealthCheck", "route53:DeleteHealthCheck", "route53:UpdateHealthCheck"]
    resources = ["arn:aws:route53:::healthcheck/*"]
  }

  # 네임스페이스의 비공개 호스팅 존 생성·조회와, 관제 VPC에서도 그 이름을 풀게 하는 VPC 연결(DEC-55).
  # 존 ID는 생성 뒤에 정해져 hostedzone/*로 둔다. 공개 존(3tier.link)의 레코드 변경 권한은 compute 정책 그대로다.
  # ListHostedZonesByVPC: Terraform이 존-VPC 연결을 만든 뒤 다시 읽을 때 부른다(리소스 수준 권한 없음, 11/04 apply 403)
  statement {
    sid       = "Route53PrivateZoneCreate"
    actions   = ["route53:CreateHostedZone", "route53:ListHostedZonesByName", "route53:ListHostedZonesByVPC"]
    resources = ["*"]
  }

  statement {
    sid = "Route53PrivateZoneVpc"
    actions = [
      "route53:GetHostedZone",
      "route53:AssociateVPCWithHostedZone",
      "route53:DisassociateVPCFromHostedZone",
      "route53:ListTagsForResource",
    ]
    resources = ["arn:aws:route53:::hostedzone/*"]
  }

  # /actuator/prometheus를 ALB에서 막는 리스너 규칙(#94). Prometheus는 피어링으로 태스크에 직접 붙는다
  statement {
    sid = "ElbListenerRules"
    actions = [
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:SetRulePriorities",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
    ]
    resources = [
      "arn:aws:elasticloadbalancing:${local.region}:${local.account}:listener/app/${local.main_prefix}-*",
      "arn:aws:elasticloadbalancing:${local.region}:${local.account}:listener-rule/app/${local.main_prefix}-*",
    ]
  }
}

locals {
  deploy_policies = {
    state-ecr     = data.aws_iam_policy_document.deploy_state_ecr.json
    network       = data.aws_iam_policy_document.deploy_network.json
    compute       = data.aws_iam_policy_document.deploy_compute.json
    data          = data.aws_iam_policy_document.deploy_data.json
    observability = data.aws_iam_policy_document.deploy_observability.json
    compute-ec2   = data.aws_iam_policy_document.deploy_compute_ec2.json
    network-e11   = data.aws_iam_policy_document.deploy_network_e11.json
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
