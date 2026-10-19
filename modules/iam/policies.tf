# 고객 관리형 정책, 롤별 정책 연결, 인라인 정책
# - ARN의 계정 ID는 var.account_id, CloudFront 배포 ID는 그룹 값(var.group_vars.distribution_ids)으로 조립함
# - Statement·Action·Resource 순서는 실제 정책 문서와 같게 둠
# - 롤·정책 이름을 바꿀 때는 envs/prod/iam.tf의 local.iam_import도 함께 고침

locals {
  distribution_arns = {
    for k, id in var.group_vars.distribution_ids : k => "arn:aws:cloudfront::${var.account_id}:distribution/${id}"
  }

  policies = {
    # www 프론트 배포. dev 버킷·dev 배포는 현행 정책에 남아 있는 항목이라 그대로 import함
    # dev 배포는 이미 삭제된 CloudFront 배포임(2026-10-13 조회). 정책에서 빼는 정리는 plan "No changes" 확인 뒤 별도 PR
    frontend_deploy = {
      name        = "boaz-prod-frontend-deploy"
      description = null
      policy = {
        Statement = [{
          Action   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
          Effect   = "Allow"
          Resource = ["arn:aws:s3:::boaz-prod-frontend", "arn:aws:s3:::boaz-prod-frontend/*", "arn:aws:s3:::boaz-dev-frontend", "arn:aws:s3:::boaz-dev-frontend/*"]
          }, {
          Action   = "cloudfront:CreateInvalidation"
          Effect   = "Allow"
          Resource = [local.distribution_arns["www"], local.distribution_arns["dev"]]
        }]
        Version = "2012-10-17"
      }
    }

    # 관리자 콘솔 배포(IAM-01)
    frontend_admin_deploy = {
      name        = "boaz-prod-frontend-admin-deploy"
      description = "frontend_admin console deploy: admin bucket write + admin CloudFront invalidation. IAM-01"
      policy = {
        Statement = [{
          Action   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
          Effect   = "Allow"
          Resource = ["arn:aws:s3:::boaz-prod-frontend-admin", "arn:aws:s3:::boaz-prod-frontend-admin/*"]
          Sid      = "AdminBucketDeploy"
          }, {
          Action   = "cloudfront:CreateInvalidation"
          Effect   = "Allow"
          Resource = local.distribution_arns["admin"]
          Sid      = "AdminCloudFrontInvalidate"
        }]
        Version = "2012-10-17"
      }
    }

    # 아카이빙 버킷 접근. EC2 롤 외에 IAM 사용자 1명에게도 연결된 공유 정책이라 본문을 고치면 그 사용자 권한도 바뀜
    ec2_s3_archiving = {
      name        = "boaz-ec2-s3-archiving-policy"
      description = null
      policy = {
        Statement = [{
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
          Effect   = "Allow"
          Resource = ["arn:aws:s3:::boaz-archiving/*", "arn:aws:s3:::boaz-archiving"]
        }]
        Version = "2012-10-17"
      }
    }

    # 지원서 버킷 접근
    ec2_s3_recruitment = {
      name        = "boaz-ec2-s3-recruitment-policy"
      description = null
      policy = {
        Statement = [{
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
          Effect   = "Allow"
          Resource = ["arn:aws:s3:::boaz-recruitment", "arn:aws:s3:::boaz-recruitment/*"]
        }]
        Version = "2012-10-17"
      }
    }
  }

  # 키: <롤 키>_<정책 역할>. 고객 관리형은 이 모듈의 정책 자원, AWS 관리형은 고정 ARN(계정 ID 없음)
  role_policy_attachments = {
    frontend_frontend_deploy             = { role = "frontend", policy_arn = aws_iam_policy.this["frontend_deploy"].arn }
    frontend_admin_frontend_admin_deploy = { role = "frontend_admin", policy_arn = aws_iam_policy.this["frontend_admin_deploy"].arn }
    codedeploy_codedeploy_role           = { role = "codedeploy", policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole" }
    ec2_s3_archiving                     = { role = "ec2", policy_arn = aws_iam_policy.this["ec2_s3_archiving"].arn }
    ec2_s3_recruitment                   = { role = "ec2", policy_arn = aws_iam_policy.this["ec2_s3_recruitment"].arn }
    ec2_cloudwatch_agent                 = { role = "ec2", policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" }
    ec2_ssm_core                         = { role = "ec2", policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" }
    # 전체 버킷 읽기 권한. 과권한 여부 검토와 권한 축소는 plan "No changes" 확인 뒤 별도 PR(IAM-02-04)
    ec2_s3_readonly = { role = "ec2", policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" }
  }

  role_policies = {
    backend_github_action_deploy = {
      role = "backend"
      name = "boaz-github-action-deploy"
      policy = {
        Statement = [{
          Action   = "s3:PutObject"
          Effect   = "Allow"
          Resource = "arn:aws:s3:::boaz-codedeploy-bucket/*"
          Sid      = "S3UploadBundle"
          }, {
          Action   = ["codedeploy:CreateDeployment", "codedeploy:GetDeployment", "codedeploy:GetDeploymentConfig", "codedeploy:RegisterApplicationRevision", "codedeploy:GetApplicationRevision"]
          Effect   = "Allow"
          Resource = "*"
          Sid      = "CodeDeployTrigger"
        }]
        Version = "2012-10-17"
      }
    }
    ec2_codedeploy_read = {
      role = "ec2"
      name = "boaz-codedeploy-read"
      policy = {
        Statement = [{
          Action   = ["codedeploy:GetApplication", "codedeploy:GetDeploymentGroup", "codedeploy:ListApplications", "codedeploy:ListDeploymentGroups"]
          Effect   = "Allow"
          Resource = "*"
          Sid      = "ReadCodeDeployDeploymentGroup"
        }]
        Version = "2012-10-17"
      }
    }
    ec2_ssm_read = {
      role = "ec2"
      name = "boaz-ssm-read"
      policy = {
        Statement = [{
          Action   = ["ssm:GetParameter", "ssm:GetParametersByPath"]
          Effect   = "Allow"
          Resource = "arn:aws:ssm:ap-northeast-2:${var.account_id}:parameter/*"
        }]
        Version = "2012-10-17"
      }
    }
    ec2_cloudwatch_list_metric = {
      role = "ec2"
      name = "cloudwatch-list-metric"
      policy = {
        Statement = [{
          Action   = ["cloudwatch:ListMetrics", "cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics"]
          Effect   = "Allow"
          Resource = "*"
        }]
        Version = "2012-10-17"
      }
    }
  }
}

resource "aws_iam_policy" "this" {
  for_each = local.policies

  name        = each.value.name
  description = each.value.description
  policy      = jsonencode(each.value.policy)

  # 이름·설명이 바뀌면 교체되어 ARN이 바뀌고, 이 모듈 밖 연결(아카이빙 정책의 IAM 사용자 연결)이 끊김
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = local.role_policy_attachments

  role       = aws_iam_role.this[each.value.role].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy" "this" {
  for_each = local.role_policies

  role   = aws_iam_role.this[each.value.role].name
  name   = each.value.name
  policy = jsonencode(each.value.policy)
}
