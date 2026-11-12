# DEC-14. 사람 인증은 IAM Identity Center와 MFA로, 영구 키 0개

- 상태: 확정
- 날짜: 2026-10-07

## 배경

이 프로젝트는 영구 액세스 키를 쓰지 않는 것이 목표였다. 배포 자동화도, 사람이 쓰는 계정도 마찬가지다. 그래서 로컬에서 Terraform과 AWS CLI를 쓸 때의 인증 방법부터 정해야 했다.

## 선택지

| 선택지 | 장점 | 단점 |
|---|---|---|
| IAM 사용자와 액세스 키 | 설정이 약 5분이면 끝난다 | 영구 키가 파일로 남고 AWS도 더는 권하지 않는다 |
| IAM Identity Center | 브라우저 로그인과 MFA로 임시 자격 증명을 받는 AWS 권장 방식이다 | 설정이 약 15분 걸리고 세션이 끝나면 다시 로그인해야 한다 |

## 결정

Identity Center를 쓴다. 사용자는 `3tier-admin`, 권한 세트는 `3tier-AdministratorAccess`, CLI 프로필은 `3tier`(SSO)로 만들었다. 사람은 SSO, 배포는 GitHub OIDC, 앱은 ECS 태스크 역할로 인증한다.

## 결과

- 이 프로젝트의 Terraform과 CLI 명령은 모두 SSO 프로필 `3tier`로만 실행했다.
- 이 프로젝트에서 영구 액세스 키를 쓰는 주체는 하나도 없다.
- 세션이 끝나면 `aws sso login`을 다시 해야 한다.
