# SEA 시즌 전환 명세서

기준일 2026-09-26 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

## 명세서 목적

- 모집 시즌(on)과 평시(off)에 따라 ALB·EC2-B·Target Group·CloudFront origin·RDS Multi-AZ를 코드로 바꾼다.
- 시즌 시작은 "EC2-B 기동·최신 번들 재배포(런북) → ALB 생성·Target Group 등록(`season_capacity = on`) → 대상 정상 확인 → origin 교체(`api_origin = alb`)", 종료는 "origin 복귀 → CloudFront 반영 완료 확인 → ALB 삭제" 순서를 지킨다.
- 한 번의 apply로는 이 순서를 보장할 수 없어서 변수 2개로 나눈다: `season_capacity`(ALB·EC2-B·Multi-AZ), `api_origin`(ec2·alb). RDS Multi-AZ 변경은 오래 걸리므로 별도 단계.
- 12월 시즌은 기존 스크립트로 전환한다. 이 명세서의 전환 기능(SEA-02·03)은 2027년에 완성한다.

**범위:** 시즌 변수 모델, 시즌 시작·종료 순서 제어, 관련 테스트
**범위 밖:** 12월 시즌 실제 전환(→ OPS-01, 기존 스크립트)

---

## SEA-01 시즌 변수 모델 최소 구현

**목적:** 보호 자원 그룹 import에 필요한 만큼만 시즌 변수와 상태 모델을 먼저 만든다.

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STA-07, MS2a | 없음 | MS2b | 5.1 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| SEA-01-01 | `season_capacity`는 `off`·`on`, `api_origin`은 `ec2`·`alb`만 허용. `api_origin = alb`인데 `season_capacity = off`면 plan 전에 실패 | 잘못된 값·조합 입력 시 `terraform plan` 즉시 오류 |
| SEA-01-02 | `season_capacity` off·on 각각의 ALB·EC2-B 상태·기능 태그·대상 목록·api origin·Multi-AZ를 locals로 정의 | `locals.tf`에 두 상태가 표 형태로 대응 |
| SEA-01-03 | 시크릿·추정 ID를 기본값으로 넣지 않음 | `terraform.tfvars.example`에 실제 값 없음 |

## SEA-02 시즌 시작(on) 순서 제어 + P4

**목적:** 시즌 시작 시 ALB가 준비되고 대상이 정상이 된 뒤에만 origin을 바꾼다.

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | CMP-02, CDN-02, STA-09 | 없음 | MS3 | 7.1, 8.7 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| SEA-02-01 | EC2-B 기동·재배포 → `season_capacity = on` apply(ALB·listener·Target Group 등록) → 대상 정상 확인 → `api_origin = alb` apply 순서를 런북과 사전 조건으로 표현 | 런북 순서와 사전 조건(`api_origin = alb`는 `season_capacity = on`에서만) 확인 |
| SEA-02-02 | `describe-target-health`를 15초마다 확인해 최대 900초(60회) 대기. 모든 대상이 healthy가 되지 않으면 origin 교체 중단(`aws elbv2 wait target-in-service` 기본값은 약 600초라 그대로 쓰지 않음) | 비정상 상태를 만들면 900초 뒤 중단되고 origin이 바뀌지 않음 |
| SEA-02-03 | P4 테스트: 시즌 시작 순서와 대기 조건 | `pytest tests/integration/test_season_on_gate.py` 통과 |

## SEA-03 시즌 종료(off) 2단계 apply + P5

**목적:** origin을 먼저 되돌리고 CloudFront 반영이 끝난 뒤에만 ALB를 지운다. 반영 전에 ALB를 지우면 502 오류.

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | SEA-02 | 없음 | MS3 | 7.2, 8.8 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| SEA-03-01 | 1단계 apply(origin을 EC2-A로 복귀)와 2단계 apply(CloudFront `Deployed` 확인 후 ALB 삭제) 분리 | `Deployed` 전에 2단계를 시도하면 차단 |
| SEA-03-02 | 최종 off 상태: EC2-B stopped·기능 태그 없음, EC2-A만 대상, Multi-AZ 꺼짐 | off plan 결과가 SEA-01 모델과 일치 |
| SEA-03-03 | P5 테스트: 시즌 종료 2단계 순서 | `pytest tests/integration/test_season_off_gate.py` 통과 |

## SEA-04 시즌 상태 매핑 테스트 P3

**목적:** 입력값별로 기대 상태가 맞게 나오는지 테스트한다.

| 규모 | 선행 | 차단 결정 | 마일스톤 | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 하루이틀 | SEA-01 | 없음 | MS3 | 8.2 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| SEA-04-01 | 두 변수의 허용 조합(off+ec2, on+ec2, on+alb)과 금지 조합(off+alb), 잘못된 문자열에 대한 기대 상태 비교 테스트 | `pytest -k P3` 통과 |

---

## 확인 필요 사항

- 시즌 전환 담당을 스크립트에서 Terraform으로 넘기는 조건: 2027 비시즌 on→off 리허설 2회 성공 [추정]
- 스크립트 삭제 시점: Terraform으로 실제 시즌을 한 번 문제없이 치른 뒤 [추정]
