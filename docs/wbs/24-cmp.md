# CMP 서버 명세서

기준일 2026-09-26 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

## 명세서 목적

- EC2-A(상시)·EC2-B(시즌용)와 Elastic IP를 다시 만들지 않고 import함
- Target Group과 ALB를 시즌 상태에 따라 있고 없도록 구성함
- 시즌 시작 때 EC2-B가 옛 버전 앱으로 서비스되지 않도록 재배포 순서를 강제함

**범위:** EC2-A/B, Elastic IP와 연결, Target Group, ALB·listener
**범위 밖:** 인스턴스 타입 변경(수동 승인 절차 → DOC-12), ASG 전환

---

## CMP-01 EC2·EIP 그룹 import

**목적:** compute 모듈을 작성하고 EC2-A/B와 Elastic IP를 import함

> 공통 절차 적용 → 공통 절차(`docs/guides/import-procedure.md`) 참조
> 수정 파일: `modules/compute/`, `envs/prod/compute.tf`, `envs/prod/imports/compute.tf`. 인스턴스 프로파일은 iam 그룹 output을 참조

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 2~3주 | SEA-01, IAM-02 | EC2-A EIP 처리, EC2-B 제어 방식 | Phase 2 2차 | 4.5, 6.4 | #13(R18) |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| CMP-01-01 | EC2-A/B를 조사로 확정한 식별자로 import | `terraform state list`에 두 인스턴스 존재 |
| CMP-01-02 | 기존 Elastic IP와 연결을 import하고 `prevent_destroy` 적용 | plan에 EIP·연결 삭제 없음 |
| CMP-01-03 | AMI·`user_data`는 항상 변경 무시 목록(`ignore_changes`)에 넣음. 기능 태그(`app=boaz-api`)·인스턴스 상태는 넣지 않음 | 기능 태그를 바꾸면 plan에 변경이 나옴 |
| CMP-01-04 | EC2-A/B 모두 `prevent_destroy` 적용 | 삭제하는 plan이 오류로 차단 |
| CMP-01-05 | EC2-B 켜기·끄기는 `aws_ec2_instance_state`로 하고 ASG로 바꾸지 않은 이유를 기록 | decisions.md에 두 방식 비교와 선택 이유 존재 |

## CMP-02 Target Group·ALB 그룹 import

**목적:** Target Group을 import하고 ALB를 시즌 상태에 따라 만들고 지우도록 구성함. 계획서의 "로드밸런싱(Target Group)" 그룹이 이 티켓

> 공통 절차 적용 → 공통 절차(`docs/guides/import-procedure.md`) 참조
> 수정 파일: compute 그룹 파일(`modules/compute/`, `envs/prod/compute.tf`)에 함께 둠. CMP-01과 같은 담당이 진행

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | CMP-01 | 없음 | Phase 2 2차 | 6.6 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| CMP-02-01 | Target Group의 등록 대상·상태 확인 설정·포트·보안 그룹·서브넷 import | `terraform state list`에 Target Group 존재 |
| CMP-02-02 | `season_capacity = off`면 ALB·listener 없음, `on`이면 있음 | off·on 각각의 plan에서 존재 여부가 모델과 일치 |
| CMP-02-03 | origin 교체는 `api_origin` 별도 apply로만 하고, 그 전에 실제 대상 상태를 확인하는 단계를 둠(Terraform 의존 관계는 상태 검사 통과를 기다리지 않음). 확인 방법은 SEA-02와 같음 | `api_origin = alb` apply 직전 `aws elbv2 describe-target-health` 결과에서 모든 대상이 healthy |

## CMP-03 EC2-B 재배포 순서 게이트

**목적:** 시즌 시작 때 "EC2-B 기동 → 최신 번들 재배포 성공 → Target Group 등록" 순서를 지키게 함

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | CMP-02, DEP-02 | 없음 | Phase 2 2차 | 신규 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| CMP-03-01 | EC2-B 기동 → 재배포 성공 → `season_capacity = on` apply(Target Group 등록) 순서를 런북에 명시. 현행 `season-up.sh`의 재배포 단계를 그대로 옮김 | 재배포 전에 등록하는 경우를 검증 스크립트가 실패로 판정 |
| CMP-03-02 | 12월 시즌 전 EC2-B를 한 번 켜서 OS 패치·CodeDeploy 에이전트 상태 확인 후 다시 끔 | 점검 결과 기록, EC2-B 다시 stopped |

---

## 확인 필요 사항

- 공인 IPv4 과금(IP당 월 약 $3.6)을 비용표에 반영 [추정]
- EC2-B 사전 점검 날짜 [확인 필요]
