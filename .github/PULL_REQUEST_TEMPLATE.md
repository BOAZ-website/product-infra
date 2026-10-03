## 💡 개요

* Issue Number: #
* import 그룹: <!-- network / iam / params / storage / compute / database / cdn / deploy / obs / 해당 없음 -->

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
- 시즌 변수(`season_capacity`·`api_origin`, `season.auto.tfvars`) 관련 변경: 없음 / 있음

## 📋 import 그룹 PR 체크리스트

<!-- import 그룹 PR만 작성. 그 외 PR은 이 절을 지워주세요. 기준: docs/guides/import-procedure.md -->

- [ ] 수정 파일이 자기 그룹 파일(`modules/<그룹>/`, `envs/prod/<그룹>.tf`, `envs/prod/imports_<그룹>.tf`)뿐이다
- [ ] 착수 전 해당 그룹 자원을 다시 조사해 `docs/records/inventory.md`를 갱신했다
- [ ] plan 결과에 교체·삭제가 0건이다(import 그룹은 import만, obs는 create만, CDN-03은 명세서의 update만)
- [ ] 보호 대상 자원에 `prevent_destroy`가 있다
- [ ] plan 출력과 코드에 시크릿 값, 계정 ID, 개인 IP가 없다
- [ ] `docs/records/import-log.md`는 이 PR에 포함하지 않았다(착수·완료 기록은 별도 작은 PR)

## 🔒 보안 정보 확인

- [ ] 코드·문서·PR 본문에 공인 IP, 시크릿·키, 개인 계정명이 없다
- [ ] 계정 ID·자원 ID는 `docs/records/`에만 있다(다른 곳은 역할명)

## 🔔 참고 사항 / 승인

- 운영 승인 필요 여부:
- 관련 문서 업데이트: <!-- docs/records/import-log.md, docs/records/decisions.md, 런북 등 -->
