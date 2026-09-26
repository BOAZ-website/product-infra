# BOAZ 현행 인프라

BOAZ 홈페이지(`www.bigdataboaz.com`)와 API 서버(`api.bigdataboaz.com`)의 **현재 AWS 인프라 구성**을 정리한 문서.

- 성격: 현행 상태(as-is). "지금 무엇이 어떻게 구성되어 있는가"만 담는다.
- 기준: 2026-09-23 AWS 읽기 전용 조사(`docs/records/inventory.md`)
- 자원 ID(VPC·서브넷·보안 그룹·인스턴스·CloudFront 배포 ID 등), 계정 ID, 개인 IP는 이 문서에 적지 않는다. 필요하면 `docs/records/inventory.md` 또는 AWS에서 직접 조회한다.
- Terraform 이전 방법은 `docs/overview/migration-plan.md`와 `docs/wbs/` 참조. 이번 이전은 현행 구조를 그대로 코드로 옮기는 작업이라, 이 문서의 구성은 이전 전후가 같다.

---

## 1. 공통

| 항목 | 값 |
|---|---|
| 리전 | `ap-northeast-2`(서울). CloudFront 인증서·WAF만 `us-east-1` |
| 운영 도메인 | `bigdataboaz.com` (`www`, `api`, `admin`) |
| IaC | 없음(콘솔 + 셸 스크립트로 운영) |

---

## 2. 트래픽 경로

```text
평시:
  사용자 → Route53 → CloudFront(api)   → EC2-A:8080 → RDS(Single-AZ)
  사용자 → Route53 → CloudFront(www)   → S3(boaz-prod-frontend)
  사용자 → Route53 → CloudFront(admin) → S3(boaz-prod-frontend-admin)

시즌(모집 기간):
  사용자 → Route53 → CloudFront(api) → ALB:80 → EC2-A/EC2-B:8080 → RDS(Multi-AZ)
```

- api CloudFront origin은 평시에 EC2-A 퍼블릭 DNS(port 8080)에 직접 연결된다. EC2-A에 Elastic IP가 연결되어 있어 재시작해도 DNS는 바뀌지 않는다.
- 시즌에는 origin이 ALB DNS(port 80)로 교체된다.
- CloudFront 3개(api·www·admin) 모두 WAF WebACL이 연결되어 있다.

---

## 3. 네트워크

| 구분 | 구성 |
|---|---|
| VPC | `10.0.0.0/16` 1개 |
| Public Subnet | `10.0.1.0/24`(2a), `10.0.2.0/24`(2c) |
| Private Subnet | `10.0.11.0/24`(2a), `10.0.12.0/24`(2c) |
| 라우팅 | public: 인터넷 게이트웨이 경유 / private: VPC 내부만 / main: VPC 내부만 |
| NAT Gateway | 없음(private subnet은 아웃바운드 인터넷 불가) |
| Network ACL | 기본 NACL 1개 |

### 보안 그룹

| 보안 그룹 | 인바운드 |
|---|---|
| `boaz-alb-sg` | TCP 80 ← CloudFront 관리형 prefix list |
| `prod-cf-to-ec2-sg` | TCP 8080 ← CloudFront 관리형 prefix list |
| `prod-alb-to-ec2-sg` | TCP 8080 ← `boaz-alb-sg` |
| `prod-ec2-to-rds-sg` | 없음(RDS 접근용 출발지로 사용, 아웃바운드는 RDS 3306만) |
| `prod-rds-sg` | TCP 3306 ← `prod-ec2-to-rds-sg` |
| `prod-ssh-sg` | TCP 22 ← 운영진 개인 IP 2개(`/32`) |

- CloudFront 관리형 prefix list는 모든 CloudFront 배포를 포함한다. 우리 배포에서 온 요청만 받는 오리진 보호는 아직 없다.
- SSH는 IP 2개로만 제한되어 있다. EC2 롤에 Session Manager 권한이 있어 SSH 대신 Session Manager로 바꾸는 것을 검토 중이다(`docs/records/decisions.md`).
- 평시에 ALB는 없지만 `boaz-alb-sg`, `prod-alb-to-ec2-sg`는 시즌에 다시 쓰기 위해 상시 유지한다.

---

## 4. 컴퓨팅(EC2)

| 항목 | EC2-A | EC2-B |
|---|---|---|
| Name | `boaz-api-prod-A` | `boaz-api-prod-B` |
| 상태 | running(상시) | stopped(시즌에만 기동) |
| Type | `t3.small` | `t3.small` |
| AZ | public subnet 2a | public subnet 2c |
| Elastic IP | 연결됨 | 없음 |
| Instance Profile | `role-prod-ec2` | `role-prod-ec2` |

- 두 인스턴스 모두 보안 그룹 4개 부착: `prod-ec2-to-rds-sg`, `prod-ssh-sg`, `prod-cf-to-ec2-sg`, `prod-alb-to-ec2-sg`
- 애플리케이션: Spring Boot, 포트 8080, systemd `boaz.service`, 상태 확인 `/actuator/health`

---

## 5. 로드밸런싱

| 항목 | 값 |
|---|---|
| Target Group | `boaz-api-tg`, HTTP 8080, 상태 확인 `/actuator/health` |
| 등록 대상(평시) | EC2-A만(ALB가 없어 상태 `unused`) |
| ALB | 평시 없음. 시즌마다 `boaz-alb`로 생성·삭제(DNS가 매번 바뀜) |

---

## 6. 데이터베이스(RDS)

| 항목 | 값 |
|---|---|
| 식별자 | `boaz-prod-db` |
| 엔진 | MySQL `8.4.11` |
| 인스턴스 클래스 | `db.t3.micro` |
| 스토리지 | `gp3`, 20 GB, 암호화 ON |
| Multi-AZ | false(평시 Single-AZ, 시즌 Multi-AZ) |
| 퍼블릭 접근 | 비활성 |
| 삭제 방지 | 활성 |
| 백업 보관 | 7일 |
| Subnet Group | `boaz-prod-rds-subnet-group`(private subnet 2a·2c) |
| Parameter Group | `boaz-prod-mysql84` |
| 유지보수 시간 | 목요일 20:00 UTC |

---

## 7. 스토리지(S3)

| 버킷 | 용도 |
|---|---|
| `boaz-prod-frontend` | 운영 프론트(www) origin |
| `boaz-prod-frontend-admin` | 관리자 콘솔(admin) origin |
| `boaz-dev-frontend` | dev 프론트(현재 연결된 CloudFront 배포 없음) |
| `boaz-codedeploy-bucket` | 백엔드 CodeDeploy 배포 번들 |
| `boaz-recruitment` | 지원서 업로드(30일 후 자동 삭제) |
| `boaz-archiving` | 아카이빙(공개 읽기) |
| 기타 레거시 버킷 | 용도 확인 필요, 관리 대상 여부 미결정(`docs/records/decisions.md`) |

- 모든 버킷의 버전 관리가 꺼져 있다. 버킷별 암호화·퍼블릭 차단·정책은 `docs/records/inventory.md` 참조.

---

## 8. CDN(CloudFront)

| 배포 | Alias | Origin | 비고 |
|---|---|---|---|
| api | `api.bigdataboaz.com` | EC2-A 퍼블릭 DNS, port 8080 | 캐시 끔, WAF 연결 |
| www | `www.bigdataboaz.com` | `boaz-prod-frontend` S3 | SPA 오류 응답(403·404 → `/index.html`), WAF 연결 |
| admin | `admin.bigdataboaz.com` | `boaz-prod-frontend-admin` S3 | 오류 응답 설정 없음, WAF 연결 |

- api 배포는 origin이 하나이며 평시 EC2-A ↔ 시즌 ALB로 교체된다.
- 접근 로그는 꺼져 있다.

---

## 9. DNS / 인증서

| 항목 | 값 |
|---|---|
| Hosted Zone | `bigdataboaz.com`, 레코드 15개 |
| 주요 레코드 | `api`·`www`·`admin` → 각 CloudFront |
| ACM | CloudFront용 인증서는 `us-east-1` |

---

## 10. 배포 파이프라인

### Backend(EC2 + CodeDeploy)

| 항목 | 값 |
|---|---|
| CodeDeploy App | `boaz-backend` |
| Deployment Group | `codedeploy-prod`, 대상 태그 `app=boaz-api`, 자동 롤백 켜짐 |
| 배포 설정 | `CodeDeployDefault.AllAtOnce` |
| Service Role | `role-prod-codedeploy` |
| 흐름 | GitHub Actions → S3(`boaz-codedeploy-bucket`) 번들 업로드 → CodeDeploy → EC2 systemd |

### Frontend(S3 + CloudFront)

| 항목 | 값 |
|---|---|
| 흐름 | GitHub Actions → `aws s3 sync dist/` → CloudFront 캐시 무효화 |
| www 배포 | `main` 푸시 → `boaz-prod-frontend` |
| dev 배포 | `dev` 푸시 → dev 버킷(연결된 CloudFront 배포가 삭제되어 동작 여부 확인 필요) |
| admin 배포 | 배포 워크플로우 없음(frontend_admin 저장소에서 추가 예정) |

---

## 11. IAM / OIDC

| Role / Provider | 용도 |
|---|---|
| `role-prod-github-actions` | 백엔드 GitHub Actions OIDC(배포) |
| `role-prod-github-actions-frontend` | 프론트 GitHub Actions OIDC(배포) |
| `role-prod-codedeploy` | CodeDeploy 서비스 롤 |
| `role-prod-ec2` | EC2 instance profile. 관리형 정책 5개(`AmazonS3ReadOnlyAccess`, `AmazonSSMManagedInstanceCore`, `CloudWatchAgentServerPolicy`, 아카이빙·지원서 버킷 접근 정책 2개) + 인라인 정책 3개(CodeDeploy 읽기, SSM 파라미터 읽기, CloudWatch 지표 조회) |
| GitHub OIDC Provider | `token.actions.githubusercontent.com` |

---

## 12. 파라미터(SSM Parameter Store)

| 구분 | 개수 | 내용 |
|---|---|---|
| 인프라 식별자 `/boaz/infra/*` | 12개 | `EC2_B_ID`, `EC2_A_DOMAIN`, `EC2_A_PORT`, `CLOUDFRONT_DIST_ID`, `RDS_IDENTIFIER`, `S3_BUCKET`, `CODEDEPLOY_APP`, `CODEDEPLOY_GROUP`, `TARGET_GROUP_ARN`, `ALB_SG_ID`, `ALB_SUBNETS`, `ALB_PORT` |
| 앱 시크릿(루트 경로) | 14개 | `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `JWT_SECRET`, `S3_*_BUCKET_NAME`, `KAKAO_*`, `GOOGLE_*`, `NAVER_*`, `SWAGGER_*` |

- 앱 시크릿 값은 조회하지 않았다. 비밀값 6개는 SecureString, `DB_URL`·`DB_USERNAME`은 일반 문자열(전환 여부 결정 대기).

---

## 13. 시즌 전환 동작(현행)

모집 시즌에 `season-up.sh` / `season-down.sh`가 AWS CLI로 수행하는 상태 변화.

| 대상 | 평시 | 시즌 |
|---|---|---|
| ALB `boaz-alb` + listener(:80) | 없음 | 생성 |
| EC2-B | stopped, `app=boaz-api` 태그 없음 | running, 태그 부착 |
| Target Group 등록 | EC2-A만 | EC2-A + EC2-B |
| CloudFront api origin | EC2-A:8080 | ALB DNS:80 |
| RDS `multi_az` | false | true |

- 시즌 시작 순서: EC2-B 기동 → 최신 번들 재배포(OneAtATime) → ALB 생성 → EC2-B를 Target Group에 등록 → 대상 정상 대기 → origin 교체
- 시즌 종료: CloudFront origin을 EC2-A로 복귀 → `Deployed` 확인 후 ALB 삭제(반영 전 삭제 시 502)
- 상시 유지 자원: Target Group `boaz-api-tg`, `boaz-alb-sg`, `prod-alb-to-ec2-sg`, EC2-B(중지 상태), `/boaz/infra/*`

---

## 14. 관측된 특이사항

- RDS Multi-AZ를 시즌마다 켜고 끄는 구조(가용성 설정을 트래픽 이벤트에 연동).
- RDS 여유 메모리가 월평균 107~140MB, 최저 약 25MB로 빠듯함(이슈 #13 실측).
- private subnet에 NAT가 없어 private subnet 자원은 아웃바운드 인터넷 불가.
- GitHub OIDC trust에 같은 저장소 조건이 중복 기재됨(동작에는 문제없음).

---

## 참고

- 조사 기록: `docs/records/inventory.md`(식별자 포함), 결정 기록: `docs/records/decisions.md`
- 이전 계획: `docs/overview/migration-plan.md`, 작업 목록: `docs/wbs/00-wbs.md`
- 현행 시즌 운영 스크립트·절차: `backend/infra/scripts/README.md`
