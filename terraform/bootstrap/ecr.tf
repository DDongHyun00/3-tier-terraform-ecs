# 앱 이미지 저장소. main을 destroy해도 이미지는 남아야 하므로 bootstrap에 둔다.
resource "aws_ecr_repository" "board" {
  name = "3tier/board"

  # 같은 태그로 다시 push할 수 없게 한다. 배포 태그는 커밋 SHA이므로
  # "어떤 코드가 돌고 있나"가 이미지 태그만으로 확정된다.
  image_tag_mutability = "IMMUTABLE"

  # push할 때마다 취약점 스캔
  image_scanning_configuration {
    scan_on_push = true
  }

  # 반복 destroy/apply 중 실수로 bootstrap을 지워도 이미지가 있는 리포지토리는 남는다
  force_delete = false
}

# 수명 주기: 태그 없는 이미지(빌드 중간 산출물)는 1일 뒤 삭제,
# 태그 있는 이미지는 최근 10개만 유지. 스토리지 비용을 막는다.
resource "aws_ecr_lifecycle_policy" "board" {
  repository = aws_ecr_repository.board.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 10 tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}
