# CDN CloudFront·Route53·ACM·WAF 명세서

기준일 2026-09-26 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

## 명세서 목적

- CloudFront 배포 3개(api·www·admin), Route53 레코드, ACM 인증서를 import함
- 각 CloudFront에 연결된 WAF가 끊어지지 않게 함. `web_acl_id`를 적지 않으면 plan이 WAF 연결을 해제함
- api origin이 항상 정확히 1개인지 검사함

**범위:** CloudFront 배포 3개, Route53 호스팅 영역·레코드, us-east-1 ACM 인증서, WAF 연결(참조만)
**범위 밖:** WAF WebACL 자체 import와 규칙 변경(CDN-03에서 별도 진행)

---

## CDN-01 cdn 모듈 작성

**목적:** CloudFront·Route53·ACM을 관리할 모듈을 작성함

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | STO-01 | 없음(admin 포함 여부 해소) | Phase 2 2차 | 4.7 | 없음 |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| CDN-01-01 | api·www·admin CloudFront, Route53, ACM을 관리할 모듈 입력값 작성 | `terraform validate` 통과 |
| CDN-01-02 | api origin이 1개가 아니거나 현재 설정이 확정되지 않으면 plan 실패 | origin 2개 입력으로 오류 확인 |
| CDN-01-03 | `api_origin = ec2`면 EC2-A:8080, `alb`면 ALB:80을 api origin으로 사용 | ec2·alb 각각의 plan에서 origin 값이 모델과 일치 |

## CDN-02 CloudFront·Route53·ACM import

**목적:** 3개 배포와 DNS·인증서를 import하고 WAF 연결을 유지함. 두 단계로 나눠 진행함
- 1단계: admin·www CloudFront, Route53 레코드, ACM 인증서. 두 배포의 origin은 S3라 storage 그룹 output만 필요함(2026-10-02 조회 확인)
- 2단계: api CloudFront. origin이 EC2-A(평시)·ALB(시즌)라 compute 그룹 output이 필요해 CMP-02 머지 후 진행함

> 공통 절차 적용 → 공통 절차(`docs/guides/import-procedure.md`) 참조
> 수정 파일: `modules/cdn/`, `envs/prod/cdn.tf`, `envs/prod/imports_cdn.tf`. admin·www 버킷 정보는 storage 그룹 output을, EC2-A·ALB 주소는 compute 그룹 output을 참조
> 정·부 2명이 나눠 진행할 때는 모듈 안 파일을 자원별로 나누고(예: `cloudfront.tf`, `dns.tf`) PR·apply는 한 번에 하나씩 함
> 그룹 값 키·테스트: 코드에 못 적는 값은 `docs/guides/import-procedure.md` 1-1-1절의 키 규칙·키 표를 따름. 새 키와 import 블록을 쓰는 PR에서 `envs/prod/tests/season.tftest.hcl`의 자기 그룹 가짜 값과 import 대상 `override_resource`를 같은 PR에서 추가함(1-2절)

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 2~3주 | CDN-01, STO-01(1단계), CMP-02(2단계) | WAF WebACL 관리 방식 | Phase 2 2차 | 6.7 | #13(R9, R10 일부) |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| CDN-02-01 | CloudFront 3개·Route53 레코드·us-east-1 인증서를 조사로 확정한 값으로 import. 1단계(admin·www·Route53·ACM)를 먼저 머지하고 2단계(api)는 CMP-02 머지 후 별도 PR | `terraform state list`에 전부 존재 |
| CDN-02-02 | 각 배포에 기존 WAF WebACL을 `web_acl_id`로 참조(WebACL 자체는 import 안 함) | plan에 WAF 연결 해제 없음 |
| CDN-02-03 | www의 403/404 → `/index.html` 동작, 각 배포의 캐시 정책을 그대로 유지. admin은 현재 오류 응답 설정이 없으므로 없는 상태 그대로 import | plan에 캐시 정책·오류 응답 변경 없음 |
| CDN-02-04 | 레거시 OAI 4개와 대응 자원 없는 인증서 검증 CNAME의 처리 방침 기록(이번엔 관리 제외) | decisions.md에 방침·사유 존재 |

## CDN-03 관리자 CloudFront 보안·SPA 설정

**목적:** 12월 관리자 페이지 오픈에 필요한 CloudFront 쪽 보안·라우팅 설정을 코드로 추가함. CDN-02 1단계(admin 배포 포함) plan "No changes" 확인 직후 별도 PR로 진행하고, 시즌 동결 시작 전에 apply까지 끝냄. #13 R5·R9·R10.

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | CDN-02 1단계(CDN-03-02·03), CDN-02 2단계(CDN-03-04 중 api 배포 항목) | 없음. WAF는 참조만 하는 것으로 확정됨. CDN-03-01은 콘솔로 적용함 | Phase 2 2차 | 신규 | #13(R5, R9, R10) |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| CDN-03-01 | 관리자 로그인 API 요청 제한 등 WAF 규칙 추가. decisions.md "WAF WebACL 관리 방식" 결정에 따라 WebACL은 참조만 함. 규칙은 콘솔로 적용하고 결과를 decisions.md에 기록함. 로그인 API는 api 도메인으로 요청됨. 대상은 api WebACL임. api WebACL에는 IP별 요청 제한 규칙이 이미 있음. 보강 여부를 확인함 | decisions.md에 적용 내용 기록, 콘솔 규칙 확인 |
| CDN-03-02 | 관리자 CloudFront에 관리형 보안 헤더 정책 연결 | 배포 설정 조회 결과에 정책 연결 |
| CDN-03-03 | 관리자 CloudFront에 SPA 오류 응답 추가: 403·404 → `/index.html`, 응답 코드 200. apply 전에 기존 정적 HTML 관리자 페이지 동작 영향 확인 | 없는 경로 요청 시 200과 index.html 응답, 기존 페이지 정상 |
| CDN-03-04 | 인프라 보안 보완 항목(오리진 보호, 클라이언트 IP 전달, origin 구간 설정) 반영. 세부 내용은 팀 비공개 문서 참조. api 배포 대상 항목은 CDN-02 2단계(CMP-02 이후) 뒤에 진행함 | 비공개 문서의 확인 항목 전부 통과 |
| CDN-03-05 | 시즌 동결 시작(2026-12-07) 전에 apply 완료. 기준선은 2026-12-04(Phase 2 2차 마감). apply 후 관리자 페이지 접속·로그인 확인 | apply 로그 시각이 동결 시작 전, 확인 결과 기록 |

---

## 확인 필요 사항

- CDN-03은 12월 관리자 페이지 오픈 전, 시즌 동결 시작 전에 apply까지 끝나야 함. 2026-10-02부터 선행을 STO-01 → CDN-01 → CDN-02 1단계 → CDN-03으로 바꿔 CMP-01·CMP-02를 기다리지 않음. CDN-03 완료 예상 11월 말~12월 초 [추정]
- CDN-03이 동결 전에 끝나지 못하면 관리자 페이지 오픈을 시즌 뒤로 미루거나 콘솔 적용으로 전환하는 판단 필요 [확인 필요]
- CDN import가 2027-01 전에 끝나지 않으면, 관리자 콘솔 SPA 설정을 콘솔에서 먼저 바꾸고 코드에 반영하는 절차가 필요 [확인 필요]
- CloudFront가 자동 생성한 WebACL이 요금제 묶음인지 [확인 필요]
