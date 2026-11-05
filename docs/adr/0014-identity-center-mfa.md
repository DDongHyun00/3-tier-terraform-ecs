# DEC-14. 사람 인증은 IAM Identity Center + MFA, 영구 키 0개

- 상태: 확정 · 날짜: 2026-10-07 · 검증: 해당 없음
- 관련 이슈: https://github.com/DDongHyun00/3-tier-terraform-ecs/issues/13

## 배경

로컬에 실습용 IAM 사용자의 영구 액세스 키가 남아 있었다. 프로젝트의 보안 항목이 "액세스 키 없는 배포"인데 사람 계정에 영구 키가 있으면 반쪽이다.

## 검토한 선택지

- IAM 사용자 + 액세스 키: 5분. 영구 키가 파일로 남음. AWS가 더 이상 권장하지 않음
- IAM Identity Center: 15분. 브라우저 로그인 + MFA로 임시 자격 증명. AWS 권장

## 결정

Identity Center 사용자 `3tier-admin`, 권한 세트 `3tier-AdministratorAccess`, CLI 프로필 `3tier`(SSO). 사람은 SSO, 배포는 OIDC, 앱은 태스크 역할.

## 결과

- 계정 전체에 영구 액세스 키를 쓰는 주체가 없다
- 세션이 만료되면 `aws sso login`을 다시 해야 한다
