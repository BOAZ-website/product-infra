# 공통 파일: STA 담당만 수정 (docs/guides/import-procedure.md 1절)
#
# default_tags는 넣지 않음. import하는 기존 자원에 태그가 없어 plan "No changes"를 맞출 수 없기 때문
# 모든 그룹 import와 최종 일치 확인(STA-09) 뒤 태그 전용 PR로 적용 (docs/records/decisions.md "default_tags 적용 시점")

provider "aws" {
  region = "ap-northeast-2"

  # 다른 계정 자격 증명으로 실행하면 plan 단계에서 실패시킴
  allowed_account_ids = [var.expected_account_id]
}

# CloudFront viewer 인증서(ACM)·WAF WebACL(CLOUDFRONT 범위) 조회용. CloudFront 배포·Route53은 기본 provider 사용
# cdn 그룹(CDN-01)이 사용하기 전까지 미사용 경고를 무시함
# tflint-ignore: terraform_unused_declarations
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  allowed_account_ids = [var.expected_account_id]
}
