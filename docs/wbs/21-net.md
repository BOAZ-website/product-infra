# NET 네트워크 명세서

기준일 2026-09-26 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

## 명세서 목적

- VPC·서브넷·라우팅·보안 그룹을 다시 만들지 않고 import함
- 보안 그룹 규칙은 규칙마다 개별 리소스로 관리함
- 모듈 코드 작성, import, plan "No changes" 확인을 한 PR에서 끝냄

**범위:** VPC, 서브넷 4개, 라우트 테이블 3개, 인터넷 게이트웨이, Network ACL, 보안 그룹과 규칙
**범위 밖:** 규칙 내용 변경(SSH 방식 변경 등은 별도 승인 후 별도 PR)

---

## NET-01 network 그룹 import

**목적:** network 모듈을 작성하고 네트워크 자원을 import해 plan "No changes"를 확인함

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 2~3주 | STA-07 | Network ACL 관리 방식 | Phase 2 1차 | 4.1, 6.1 | 없음 |

> 공통 절차 적용(착수 선언·직전 재조사·plan "No changes" 확인·import-log 기록) → 공통 절차(`docs/guides/import-procedure.md`) 참조
> 수정 파일: `modules/network/`, `envs/prod/network.tf`, `envs/prod/imports_network.tf`

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| NET-01-01 | 재조사 때 보안 그룹 규칙 ID도 수집(`describe-security-group-rules`) | inventory에 규칙 ID 목록 존재 |
| NET-01-02 | VPC·서브넷 4개·라우트 테이블 3개·인터넷 게이트웨이를 조사로 확정한 식별자로 import | `terraform state list`에 각 주소 존재 |
| NET-01-03 | 보안 그룹 규칙을 규칙별 리소스(`aws_vpc_security_group_ingress_rule` 등)로 정의, 보안 그룹 안에 규칙을 함께 쓰지 않음 | 코드에 보안 그룹 내부 `ingress`·`egress` 블록 없음 |
| NET-01-04 | CloudFront 관리형 prefix list → ALB 보안 그룹, ALB 보안 그룹 → EC2 보안 그룹 TCP 8080 관계 연결 | plan에서 출발지·포트가 조사 결과와 일치 |
| NET-01-05 | SSH 인바운드 규칙은 변경하지 않음. Session Manager 대체안은 decisions.md에 기록 | plan에서 해당 규칙 변경 없음 |
| NET-01-06 | 기본 아웃바운드(전체 허용) 규칙을 코드에 명시 | plan에 아웃바운드 삭제 없음 |
| NET-01-07 | 다른 그룹이 쓸 output 제공: VPC ID, 서브넷 ID, 보안 그룹 ID | `envs/prod/network.tf`에 output 참조 가능 |

---

## 확인 필요 사항

- Network ACL을 관리 대상에 넣을지(기본안: 현행 그대로 import) [확인 필요]
