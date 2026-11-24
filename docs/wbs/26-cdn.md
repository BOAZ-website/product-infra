# CDN CloudFront·Route53·ACM·WAF 명세서

기준일 2026-11-24 · → 전체 일정은 `docs/wbs/00-wbs.md` 참조

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
| CDN-02-03 | www의 403/404 → `/index.html` 동작, 각 배포의 캐시 정책을 그대로 유지. admin은 조사 당시 오류 응답 설정이 없었으나, 2026-11-29까지 콘솔로 SPA 오류 응답(403·404 → `/index.html`, 응답 코드 200, CDN-03-03)과 보안 헤더 정책(CDN-03-02)을 적용함. import 직전 실제 설정을 다시 조회해 그 값 그대로 import함("시즌 전 콘솔 변경") | plan에 캐시 정책·오류 응답 변경 없음 |
| CDN-02-04 | 레거시 OAI 4개와 대응 자원 없는 인증서 검증 CNAME의 처리 방침 기록(이번엔 관리 제외) | decisions.md에 방침·사유 존재 |

## CDN-03 관리자 CloudFront 보안·SPA 설정

**목적:** 12월 관리자 페이지 오픈에 필요한 CloudFront 쪽 보안·라우팅 설정을 코드로 추가함. CDN-02 1단계(admin 배포 포함) plan "No changes" 확인 직후 별도 PR로 진행함. 원래는 2026-11-23까지 apply할 계획이었으나, 2026-11-24 PO 결정으로 CDN import·apply를 시즌 뒤로 옮기고 CDN-03-02·03은 2026-11-29까지 콘솔로 먼저 적용함(decisions.md "RDB·CDN import 시즌 뒤 연기"). #13 R5·R9·R10.

| 규모 | 선행 | 차단 결정 | Phase | tasks.md | GitHub 이슈 |
| --- | --- | --- | --- | --- | --- |
| 한 주 | CDN-02 1단계(CDN-03-02·03), CDN-02 2단계(CDN-03-04 중 api 배포 항목) | 없음. WAF는 참조만 하는 것으로 확정됨. CDN-03-01은 콘솔로 적용함 | Phase 2 2차 | 신규 | #13(R5, R9, R10) |

| 기능 ID | 기능 | 완료 확인 방법 |
| --- | --- | --- |
| CDN-03-01 | 관리자 로그인 API 요청 제한 등 WAF 규칙 추가. decisions.md "WAF WebACL 관리 방식" 결정에 따라 WebACL은 참조만 함. 규칙은 콘솔로 적용하고 결과를 decisions.md에 기록함. 로그인 API는 api 도메인으로 요청됨. 대상은 api WebACL임. api WebACL에는 IP별 요청 제한 규칙이 이미 있음. 보강 여부를 확인함 | decisions.md에 적용 내용 기록, 콘솔 규칙 확인 |
| CDN-03-02 | 관리자 CloudFront에 관리형 보안 헤더 정책 연결 | 배포 설정 조회 결과에 정책 연결 |
| CDN-03-03 | 관리자 CloudFront에 SPA 오류 응답 추가: 403·404 → `/index.html`, 응답 코드 200. apply 전에 기존 정적 HTML 관리자 페이지 동작 영향 확인 | 없는 경로 요청 시 200과 index.html 응답, 기존 페이지 정상 |
| CDN-03-04 | 인프라 보안 보완 항목(오리진 보호, 클라이언트 IP 전달, origin 구간 설정) 반영. 세부 내용은 팀 비공개 문서 참조. api 배포 대상 항목은 CDN-02 2단계(CMP-02 이후) 뒤에 진행함 | 시즌 뒤(원본 보안 별도 티켓): 비공개 문서의 확인 항목 중 관리자 배포 대상 항목 전부 통과. CDN-02 2단계 뒤: api 배포 대상 항목 전부 통과 |
| CDN-03-05 | cdn 그룹은 시즌 전에 apply하지 않음(2026-11-24 PO 결정, decisions.md "RDB·CDN import 시즌 뒤 연기". `scripts/apply-group.sh`가 cdn 실행을 막음). CDN-03-02·03은 2026-11-29까지 콘솔로 적용하고, 서류평가 화면 수동 배포(2026-11-27) 뒤 관리자 페이지 접속·로그인·평가 화면 새로고침을 확인함. 코드 반영과 apply는 동결 종료 뒤 | 콘솔 변경 전후 값과 확인 결과를 2026-11-29까지 decisions.md에 기록 |

---

## 확인 필요 사항

- (이전 계획) CDN-03은 12월 관리자 페이지 오픈 전, 시즌 동결 시작 전에 apply까지 끝내기로 했었음. 2026-10-02부터 선행을 STO-01 → CDN-01 → CDN-02 1단계 → CDN-03으로 바꿔 CMP-01·CMP-02를 기다리지 않음. 이전 apply 마감은 2026-11-23(`docs/wbs/01-schedule.md` "동결 전 묶음")이었음. 현재: 2026-11-24 PO 결정으로 CDN-01~03 모두 시즌 뒤로 옮김(decisions.md "RDB·CDN import 시즌 뒤 연기")
- CDN-02 2단계(api)는 CMP-02 이후라 동결 후 묶음(2027-02 착수 [추정])으로 옮김. CDN-03-04 중 api 배포 대상 항목도 함께 옮김
- CDN-03이 2026-11-23까지 apply되지 못하면 CDN-03-02·03을 콘솔로 먼저 적용하고 동결 종료 후 코드에 반영함(2026-11-18 확정, decisions.md "CDN-03 지연 시 대응")
- 시즌 전 콘솔 변경(2026-11-24 PO 결정, decisions.md "RDB·CDN import 시즌 뒤 연기"): CDN import를 시즌 뒤로 미뤄 아래 설정은 콘솔로 먼저 바꾸고 당일 decisions.md에 기록함. 시즌 뒤 import 때 이 값으로 코드를 맞춰 plan "No changes"를 확인함
  - 관리자 CloudFront 보안 헤더 정책 연결(CDN-03-02): 2026-11-29까지
  - 관리자 CloudFront SPA 오류 응답 403·404 → `/index.html`, 응답 코드 200(CDN-03-03): 2026-11-29까지
  - api CloudFront 원본 요청 정책 `Managed-AllViewer` → `Managed-AllViewerAndCloudFrontHeaders-2022-06`: 2026-11-25(decisions.md "api 클라이언트 IP 헤더 전달(시즌 전)")
  - season-up·season-down이 바꾸는 api 원본(도메인·포트)은 이 목록에 넣지 않음. api import는 season-down 뒤 비시즌 값으로 함
  - api CloudFront 추가 지표는 콘솔로 켜지 않고 obs 그룹의 `aws_cloudfront_monitoring_subscription`으로 켬(`docs/wbs/20-obs.md` OBS-01-09). cdn 코드에는 선언하지 않음
- CloudFront가 자동 생성한 WebACL이 요금제 묶음인지 [확인 필요]
- 원본 보안(CDN-03-04의 오리진 보호·클라이언트 IP 전달)은 모니터링과 분리해 별도 티켓으로 진행하고, 28기 지원서 접수 마감 뒤로 미룸(2026-11-24 확정). 28기 모집 전 조건(CloudFront→시즌 ALB 구간 HTTPS 전환을 2026-11-23까지 변경·승인하고 시즌 종료와 원복 절차까지 검증)을 지키지 못했기 때문임. 시즌 ALB는 season-up마다 새로 만들어져 HTTPS 전환에 고정 원본 도메인, 서울 리전 인증서, 443 리스너, `season-up.sh`·`season-down.sh` 수정이 필요함
  - 2026-12 시즌 동안 CloudFront→ALB 구간과 ALB→EC2 구간은 HTTP로 둠(잔여 위험: 이 구간에서 인증 토큰이 평문으로 전달됨)
  - CloudFront가 보내는 원본 검증 헤더를 원본에서 검사해 요청을 차단하는 작업은 평시 EC2-A의 HTTPS 전환과 함께 진행함. 평시 원본이 HTTP인 상태에서 검증 헤더를 보내면 헤더 값도 평문으로 전달되기 때문임
  - 순서: EC2-A HTTPS와 인증서 자동 갱신 준비 → 시즌 전환(season-up·season-down)과 배포 헬스체크 정상 동작 확인 → 검증 헤더 차단 적용
  - `CloudFront-Viewer-Address`는 검증 헤더 검사를 통과한 요청에서만 사용자 IP로 사용함
  - 예외: api의 `CloudFront-Viewer-Address` 전달(원본 요청 정책 변경)만 2026-11-25 콘솔로 먼저 적용함. 검증 헤더 검사 전까지 로그 기록에만 씀(decisions.md "api 클라이언트 IP 헤더 전달(시즌 전)")
