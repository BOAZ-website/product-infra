# bootstrap은 state 버킷만 새로 만드는 root라 기존 자원 import가 없음. default_tags를 처음부터 적용

provider "aws" {
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project     = "boaz"
      Environment = "prod"
      ManagedBy   = "terraform"
      Repository  = "BOAZ-website/product-infra"
    }
  }
}
