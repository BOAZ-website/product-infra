# CLAUDE.md

AI 도구(Claude Code, Kiro 등)가 이 저장소에서 작업할 때 따르는 규칙. 사람에게도 같은 규칙이 적용된다.

## 공개 저장소 보안 규칙 (반드시 지킬 것)

이 저장소는 공개 저장소다. 문서·코드·커밋 메시지·PR 본문·이슈·코멘트를 작성할 때 아래를 지킨다.

- **절대 적지 않는다:** 공인 IP 주소(개인·사무실·서버 모두, `ec2-x-x-x-x` 형태의 EC2 퍼블릭 DNS 포함), SSH 허용 IP, 비밀번호·토큰·시크릿 값, AWS 액세스 키, 개인 키, 개인 계정명(IAM 사용자명 등)
- **`docs/records/`에만 적는다:** AWS 계정 ID, 계정 ID가 들어간 ARN, 자원 ID(VPC·서브넷·보안 그룹·인스턴스·EIP·CloudFront 배포·Route53 영역 등)
- 그 밖의 문서에는 역할명으로 쓴다. 예: "EC2-A", "api CloudFront 배포", "운영진 개인 IP 2개"
- AWS 조사 결과를 문서로 옮길 때도 위 규칙을 적용한다. 조회한 값을 그대로 붙여 넣지 않는다.
- 시크릿은 조회 자체를 하지 않는다(SSM 복호화, RDS 비밀번호 조회 금지).
- 커밋 전 `scripts/check-sensitive.sh`를 실행하거나 `.githooks/pre-commit` 훅을 켠다(`git config core.hooksPath .githooks`). 검사를 건너뛰지 않는다(`--no-verify` 금지).
- 규칙 원문: README.md "보안 정보 공개 금지"

## 문서 위치

- 문서 지도와 읽기 순서: `docs/README.md`
- 작업 목록·명세서(기준 문서, 노션 원본): `docs/wbs/`
- 그룹 import 공통 절차: `docs/guides/import-procedure.md`
- 조사·결정·import 기록: `docs/records/`
