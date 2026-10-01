# 현재 운영 시즌 상태 (SEA-01). 시크릿·자원 ID가 없어 커밋함(.gitignore 예외)
# 시즌 전환은 이 파일을 바꾸는 PR로 진행하고, 두 값을 한 PR에서 함께 바꾸지 않음
#   시작: season_capacity = "on" apply → target healthy 확인 → api_origin = "alb" apply
#   종료: api_origin = "ec2" apply → CloudFront Deployed 확인 → season_capacity = "off" apply
# 절차 전체: design.md "시즌 전환과 안전 게이트"(런북은 DOC-09)
season_capacity = "off"
api_origin      = "ec2"
