# 시즌 전환 런북

기준일 2026-11-19, 작성: 컴퓨팅 담당, 관련 티켓: CMP-03-01, CMP-02-03, SEA-02-04, DOC-09

## 이 문서의 범위

- 시즌 시작 중 "EC2-B 기동 → 최신 번들 재배포 성공 → Target Group 등록" 순서와, origin 교체 전 대상 상태 확인(CMP-02-03)을 다룸
- 시즌 종료 절차, 배포 그룹 기본값과 실제 배포 방식 차이 등 나머지 내용은 DOC-09(Phase 5)에서 이 파일에 보탬
- 실행 주체: 관리자. 1, 2, 4단계는 AWS 쓰기 권한이 필요함. 3단계 게이트와 5단계 확인은 읽기 전용 조회만 함

## 적용 시점

| 시즌 | 전환 방법 | 이 런북과의 관계 |
| --- | --- | --- |
| 2026-12 | `season-up.sh`(backend 저장소 `infra/scripts/`, OPS-01-02) | 스크립트가 1, 2단계(태그 부착, 기동, 재배포 성공 대기)를 끝낸 뒤에만 등록함(`set -eo pipefail`, `aws deploy wait deployment-successful`). 이 런북의 3·5단계 게이트는 Terraform 전환 이후에 사용함. 이번 시즌의 인스턴스별 배포 결과 확인은 이슈 #58의 운영 체크리스트를 따름 |
| Terraform 전환 이후(SEA-02, Phase 4) | 1, 2단계는 CLI, 4단계는 `season_capacity = on` apply | 1~5단계를 이 순서로 실행함. 사람이 2단계와 4단계 사이에 apply를 하므로 3단계 게이트로 순서를 확인함 |

## 0. 사전 조건

- 전환 중 backend `main` 머지와 수동 배포 금지. `cd.yml`이 `main` CI 완료 시 자동 배포하므로, 전환 중 새 배포가 끼면 3단계 게이트가 실패함. 금지 방법은 백엔드 리드와 확정 [확인 필요](decisions.md "EC2-B 기동·재배포 연동")
- **전환 중 `envs/prod` apply 금지**(SEA-02-04). 1~3단계 동안 Terraform 목표값은 `season_capacity = off`임. compute 그룹 import 뒤에 이 사이 apply를 하면 EC2-B `app` 태그가 지워지고 EC2-B가 다시 중지됨
- 설정 값 불러오기. `/boaz/infra/*`는 String 파라미터라 복호화하지 않음(`season-up.sh` 0단계와 같음)

```bash
export AWS_PROFILE='<관리자 프로필>' AWS_REGION=ap-northeast-2

ssm_get() {
  aws ssm get-parameter --name "/boaz/infra/$1" --query "Parameter.Value" --output text
}
EC2_B_ID=$(ssm_get "EC2_B_ID")
CODEDEPLOY_APP=$(ssm_get "CODEDEPLOY_APP")
CODEDEPLOY_GROUP=$(ssm_get "CODEDEPLOY_GROUP")
```

## 1. EC2-B 태그 부착과 기동

`season-up.sh` 1단계와 같음. 기동 전에 CodeDeploy 대상 태그(`app=boaz-api`)를 먼저 붙여야 2단계 재배포 대상에 EC2-B가 들어감. 태그는 중지 상태 인스턴스에도 붙일 수 있음

```bash
aws ec2 create-tags --resources "$EC2_B_ID" --tags "Key=app,Value=boaz-api"
aws ec2 start-instances --instance-ids "$EC2_B_ID" > /dev/null
aws ec2 wait instance-running --instance-ids "$EC2_B_ID"
```

## 2. 최신 번들 재배포

배포 그룹의 마지막 성공 배포 번들을 다시 배포해 EC2-A와 EC2-B에 같은 번들을 반영함. 배포 방식은 항상 `OneAtATime`(decisions.md "CodeDeploy 배포 방식")

```bash
redeploy_last_success() {
  local last_deploy_id bundle_bucket bundle_key
  last_deploy_id=$(aws deploy get-deployment-group \
    --application-name "$CODEDEPLOY_APP" --deployment-group-name "$CODEDEPLOY_GROUP" \
    --query 'deploymentGroupInfo.lastSuccessfulDeployment.deploymentId' --output text) || return 1
  if [[ -z "$last_deploy_id" || "$last_deploy_id" == None ]]; then
    echo "배포 그룹에 마지막 성공 배포가 없음. 재배포 중단" >&2
    return 1
  fi

  bundle_bucket=$(aws deploy get-deployment --deployment-id "$last_deploy_id" \
    --query 'deploymentInfo.revision.s3Location.bucket' --output text) || return 1
  bundle_key=$(aws deploy get-deployment --deployment-id "$last_deploy_id" \
    --query 'deploymentInfo.revision.s3Location.key' --output text) || return 1
  if [[ -z "$bundle_bucket" || "$bundle_bucket" == None || -z "$bundle_key" || "$bundle_key" == None ]]; then
    echo "마지막 성공 배포의 S3 번들을 찾지 못함. 재배포 중단" >&2
    return 1
  fi

  DEPLOYMENT_ID=$(aws deploy create-deployment \
    --application-name "$CODEDEPLOY_APP" --deployment-group-name "$CODEDEPLOY_GROUP" \
    --deployment-config-name CodeDeployDefault.OneAtATime \
    --s3-location "bucket=$bundle_bucket,key=$bundle_key,bundleType=zip" \
    --query 'deploymentId' --output text) || return 1

  aws deploy wait deployment-successful --deployment-id "$DEPLOYMENT_ID"
}
redeploy_last_success
```

- 재배포 성공 판정은 CodeDeploy ValidateService 훅(`/actuator/health` 200 확인)을 그대로 씀(decisions.md "EC2-B 기동·재배포 연동")
- 재배포 명령이나 성공 대기가 실패하면 등록 단계로 이동하지 않음

### 2-1. 인스턴스별 배포 결과 확인

인스턴스가 두 대이면 마지막 인스턴스 배포가 실패해도 전체 배포가 성공으로 끝날 수 있음(decisions.md "CodeDeploy 배포 방식"). EC2-A·B가 모두 대상에 포함되고 두 대 모두 `Succeeded`인지 확인함. 한 대라도 빠졌거나 실패하면 등록 단계로 이동하지 않음

```bash
aws deploy batch-get-deployment-targets --deployment-id "$DEPLOYMENT_ID" \
  --target-ids $(aws deploy list-deployment-targets --deployment-id "$DEPLOYMENT_ID" --query 'targetIds' --output text) \
  --query 'deploymentTargets[].instanceTarget.[targetId,status]' --output text
```

### 2-2. CodeDeploy 에이전트 상태 확인

EC2-B에서 `systemctl is-active codedeploy-agent` 결과가 `active`인지 한 번 확인함(decisions.md "EC2-B 기동·재배포 연동")

## 3. 재배포 순서 게이트

Target Group 등록 전에 실행함. 통과(exit 0)한 경우에만 4단계로 감. `/boaz/infra/*`와 Terraform 그룹 값에서 예상 대상과 Target Group을 읽고, 출력에는 자원 ID를 쓰지 않음

```bash
python3 scripts/check_ec2b_redeploy.py
```

| 규칙 | 확인 내용 | 실패하면 |
| --- | --- | --- |
| R1 | EC2-B가 running | 1단계 다시 실행 |
| R2 | EC2-B에 `app=boaz-api` 태그 있음 | 태그를 붙인 뒤 2단계부터 다시 실행 |
| R3 | EC2-B를 켠 뒤 만든 배포가 있음 | 2단계 실행 |
| R4 | 배포 그룹에 진행·대기 중인 배포 없음 | 배포가 끝날 때까지 기다린 뒤 다시 실행 |
| R5 | 가장 최근 배포가 성공 | 실패 원인 확인 뒤 2단계 다시 실행 |
| R6 | 가장 최근 배포에서 EC2-A·B 대상이 모두 성공 | 2-1, 2-2 확인 뒤 2단계 다시 실행 |
| R7 | EC2-B가 아직 Target Group에 등록되지 않음 | 전환을 멈추고 현재 CloudFront origin과 등록 경위를 확인한 뒤 복구 절차를 정함 |

## 4. Target Group 등록(`season_capacity = on` apply)

- `envs/prod/season.auto.tfvars`의 `season_capacity`를 `on`으로 바꾸는 PR을 머지한 뒤 관리자가 apply함
- plan에서 예상하는 변경: ALB, listener, EC2-B 등록 생성. EC2-B 전원과 `app` 태그는 1단계에서 이미 맞춰져 변경 없음
- EC2-B 전원이나 태그 변경이 plan에 나오면 1단계가 빠진 것임. apply하지 않고 1단계부터 확인함

## 5. origin 교체 전 대상 상태 확인(CMP-02-03)

`api_origin = alb` apply는 4단계와 따로 함. 전환 전에 예상한 EC2-A·B가 모두 `EC2_A_PORT`에 등록돼 있고 두 대 모두 `healthy`인지 확인함. 15초 간격으로 최대 15분 동안 확인함(SEA-02-02)

```bash
python3 scripts/check_ec2b_redeploy.py --wait-target-health
```

- 통과(exit 0)한 경우에만 `api_origin`을 `alb`로 바꾸는 PR을 머지하고 관리자가 apply함
- 대상이나 포트가 다르거나 한 대라도 `healthy`가 아니면 시간 초과 시 exit 1을 반환함. 조회 실패는 exit 2를 반환함. 두 경우 모두 origin 교체를 중단함
