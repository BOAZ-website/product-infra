# bootstrap은 state 버킷만 새로 만드는 root라 기존 자원 import가 없음. default_tags를 처음부터 적용

provider "aws" {
  region = "ap-northeast-2"

  # 다른 계정 자격 증명으로 실행하면 plan 단계에서 실패시킴
  allowed_account_ids = [var.expected_account_id]

  default_tags {
    tags = {
      Project     = "boaz"
      Environment = "shared" # state 버킷은 모든 환경(envs/<환경>)이 함께 쓰는 공용 자원
      ManagedBy   = "terraform"
      Repository  = "BOAZ-website/product-infra"
    }
  }
}
