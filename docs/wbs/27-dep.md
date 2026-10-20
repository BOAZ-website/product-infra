# DEP CodeDeploy 명세서

기준일 2026-09-26 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

## 명세서 목적

- CodeDeploy 애플리케이션·배포 그룹·서비스 롤을 import함
- 기존 backend 배포 workflow가 쓰는 앱 이름·그룹 이름·태그·버킷을 바꾸지 않음

**범위:** CodeDeploy 애플리케이션, 배포 그룹, 배포 설정, 대상 태그
**범위 밖:** backend `cd.yml` 배포 방식 변경(#13 R3, backend#214), CodeDeploy·ALB 트래픽 연동(#13 R11, 보류)

---

## DEP-01 deploy 모듈 작성

**목적:** CodeDeploy를 관리할 모듈을 작성함

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | IAM-02(번들 버킷 output만 STO-01) | CodeDeploy 태그 방식(거의 해소) | Phase 2 2차 | 4.8 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| DEP-01-01 | 앱·배포 그룹·서비스 롤·대상 태그·배포 설정을 관리할 모듈 입력값 작성. 번들 버킷은 CodeDeploy 리소스가 참조하지 않아 입력값에 넣지 않음(2026-10-20 결정) | `terraform validate` 통과 |
| DEP-01-02 | 대상 지정은 `ec2_tag_filter`가 아니라 `ec2_tag_set` 블록 사용(실측 결과와 일치) | 코드에 `ec2_tag_set` 사용, plan 차이 없음 |

## DEP-02 CodeDeploy import

**목적:** 배포 그룹을 import하고 현재 설정을 그대로 유지함

> 공통 절차 적용 → 공통 절차(`docs/guides/import-procedure.md`) 참조
> 수정 파일: `modules/deploy/`, `envs/prod/deploy.tf`, `envs/prod/imports_deploy.tf`. 서비스 롤은 iam 그룹 output을 참조. 번들 버킷 output은 STO-01 머지 뒤 별도 PR에서 storage output을 이어 내보냄(DEP-02-03)
> 그룹 값 키·테스트: 이 그룹은 그룹 값 키가 없음(이름 기반 import, 1-1-1절 표). import 블록을 쓰는 PR에서 `envs/prod/tests/season.tftest.hcl`에 import 대상 `override_resource`를 같은 PR에서 추가함(1-2절)

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | DEP-01 | CodeDeploy 태그 방식(거의 해소) | Phase 2 2차 | 6.8 | #13(R11 보류) |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| DEP-02-01 | 배포 그룹의 배포 설정을 현재 값(AllAtOnce)으로 유지 | plan에 배포 설정 변경 없음 |
| DEP-02-02 | 배포 방식 OneAtATime은 backend `cd.yml`·`season-up.sh`가 배포를 만들 때마다 지정하므로 Terraform 설정에 넣지 않음. 배포 그룹 기본값(AllAtOnce)과 실제 배포 방식(OneAtATime)이 다르다는 점을 런북에 기록 | 코드에 OneAtATime 없음, 런북에 별도 절 존재 |
| DEP-02-03 | backend workflow가 쓰는 앱·그룹·버킷·ARN을 output으로 내보내되 값은 바꾸지 않음. 버킷 output은 STO-01 머지 뒤 별도 PR에서 추가(2026-10-20 결정), 버킷 이름을 문자열·변수 기본값으로 임시 기재하지 않음 | STA-10 계약 검사 통과 |

