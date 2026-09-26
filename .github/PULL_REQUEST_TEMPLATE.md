## 💡 개요

* Issue Number: #
* 기능 ID: <!-- 노션 명세서 기준. 예: NET-01-02, NET-01-03 -->
* import 그룹: <!-- network / iam / params / storage / compute / database / cdn / deploy / 해당 없음 -->

## 🪐 주요 변경 사항
-

## ✅ 상세 내용
-

## 🔍 영향 범위 (Terraform)

<!-- plan 결과 기준으로 작성. 확인 안 됐으면 그대로 두지 말고 사유를 적어주세요. -->

- 대상 스택: <!-- bootstrap / envs/prod / modules/* -->
- 영향 리소스:
- `terraform plan` 결과: <!-- No changes / create N / update N / (delete·replace 있으면 반드시 사유) -->
- 보호 리소스(RDS, S3, CloudFront 등) `delete`/`replace` 여부: 없음 / 있음(사유·승인 필수)
- `season_mode` 관련 변경: 없음 / 있음

## 📋 import 그룹 PR 체크리스트

<!-- import 그룹 PR만 작성. 그 외 PR은 이 절을 지워주세요. 기준: docs/guides/import-procedure.md -->

- [ ] 수정 파일이 자기 그룹 파일(`modules/<그룹>/`, `envs/prod/<그룹>.tf`, `envs/prod/imports/<그룹>.tf`)뿐이다
- [ ] 착수 전 해당 그룹 자원을 다시 조사해 `docs/records/inventory.md`를 갱신했다
- [ ] plan 결과에 변경·교체·삭제가 0건이다(import만 있음)
- [ ] 보호 대상 자원에 `prevent_destroy`가 있다
- [ ] plan 출력과 코드에 시크릿 값, 계정 ID, 개인 IP가 없다
- [ ] `docs/records/import-log.md`에 그룹 상태와 결과를 기록했다

## 🔔 참고 사항 / 승인

- 운영 승인 필요 여부:
- 관련 문서 업데이트: <!-- docs/import-log.md, decisions.md, runbook-season.md 등 -->
