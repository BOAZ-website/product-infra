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
- push protection에 막히면 우회(bypass)하지 말고 값을 지운 뒤 커밋을 다시 만든다. CI의 gitleaks가 실패해도 같다.
- `scripts/check-sensitive.sh`의 검사식을 바꾸면 `scripts/test-check-sensitive.sh`에 사례를 추가하고 함께 통과시킨다.
- 규칙 원문: README.md "보안 정보 공개 금지"

## GitHub Milestone·이슈 생성 규칙

- AI 도구는 GitHub Milestone과 이슈를 미리 일괄 생성하지 않는다.
- 현재 Phase 또는 다음 Phase를 시작할 때 사용자가 승인하면, 그때 해당 Phase의 Milestone과 그 Phase 티켓 이슈만 생성한다.
- 승인 없이 Milestone·이슈를 만들지 않는다. 다른 Phase의 이슈를 앞당겨 만들지 않는다.
- Phase 구분과 티켓 목록: `docs/wbs/01-schedule.md`. 규칙 원문: README.md "Milestone / 이슈 생성"

## 문서 작성 규칙

Notion 문서, PR·이슈 본문, 저장소 안 문서를 쓰거나 고칠 때 적용한다. AI 도구에 문서 작성을 맡길 때도 이 절을 따르게 한다.

- 문서만 읽고 이해할 수 있게 쓴다. 작성 당시 맥락(회의, 대화)을 모르는 팀원이 처음 읽어도 뜻이 통해야 한다.
- 비유 표현을 쓰지 않는다. 뜻 그대로의 말로 쓴다.
- 팀에서 만들어 붙인 말은 쓰지 않는다. 써야 하면 무엇인지 풀어 쓴다. BOAZ 도메인 용어(기수, 트랙, BASE·ADV·스터디, HOST 계정 등)와 WBS 티켓 ID는 그대로 쓴다.
- 업계 표준 기술 용어는 그대로 쓴다(API, ERD, 스키마, PR, OIDC 등). 과하게 풀어 써서 산출물 이름이 사라지게 하지 않는다.
- 작성자만 뜻을 아는 식별자를 쓰지 않는다: 커밋 해시, 워크플로 실행 번호, 개인 GitHub 계정명. 팀원이 찾아갈 수 있는 대상(저장소·브랜치 이름, 파일 경로, PR·이슈 번호와 링크)은 써도 된다.
- 담당은 실명 대신 역할로 쓴다. 예: 인프라 담당, 백엔드 리드, 운영진
- 날짜는 `2026-09-30` 형식의 절대 날짜로 쓴다. "다음 주", "금일" 같은 상대 표현을 쓰지 않는다.
- 영어 설정 이름은 무엇을 하는 설정인지 한국어로 풀고, 필요하면 괄호에 원래 이름을 적는다. 예: 관리자에게도 규칙 적용(enforce admins)
- PR·이슈 본문은 저장소 템플릿(`.github/PULL_REQUEST_TEMPLATE.md`, `.github/ISSUE_TEMPLATE/`)의 섹션 이름과 순서를 그대로 지킨다. 템플릿에 없는 섹션을 만들지 않고, 문서 작업 중에 템플릿 파일 자체를 고치지 않는다.
- 연결된 Notion 티켓이 있으면 템플릿의 첫 섹션(개요·Summary 등) 안에 링크를 적는다.
- 고치지 않는 것: 회의 발언 기록 원문, 외부 자료 인용, 코드 블록, 다른 문서가 링크하는 파일·폴더 이름
- `docs/` 문서는 개조식 명사형 종결(`~함`, `~됨`)을 쓴다.
- 완료 항목(`docs/records/decisions.md`의 `완료` 행, `docs/wbs/*.md`의 완료 티켓)은 확정된 결과만 적는다. "~ 회의에서 ~로 결정함" 같은 경과 대신 "~ 채택", "~로 확정"으로 쓰고, "예정", "대응" 같은 진행형 표현을 남기지 않는다.

## 문서 위치

- 문서 지도와 읽기 순서: `docs/README.md`
- 작업 목록·명세서(기준 문서, 노션 원본): `docs/wbs/`
- 그룹 import 공통 절차: `docs/guides/import-procedure.md`
- 조사·결정·import 기록: `docs/records/`
