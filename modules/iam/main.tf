# iam 모듈
# 담당 명세서: IAM (docs/wbs/22-iam.md) · 이슈: #51 IAM-02
# 관리 자원: GitHub OIDC provider, 롤 5개, 고객 관리형 정책 4개, 정책 연결 8개, 인라인 정책 4개, EC2 인스턴스 프로파일
# (CI plan 역할은 bootstrap 관리라 제외)
#
# - 정책 연결은 롤마다 aws_iam_role_policy_attachment로만 관리함
#   aws_iam_role의 managed_policy_arns·inline_policy, *_exclusive, aws_iam_policy_attachment는 쓰지 않음
#   이유: 목록에 없는 연결을 떼는 변경이 update로 나와 안전 게이트(G4)를 통과함. boaz-ec2-s3-archiving-policy는 IAM 사용자에게도 연결돼 있음
# - 롤·고객 관리형 정책·OIDC provider·인스턴스 프로파일은 prevent_destroy. 배포·EC2 권한이 끊기면 운영 배포와 앱 동작이 바로 멈추기 때문
# - 정책 문서·설명은 실제 값과 같게 적음(다르면 update 또는 교체가 생김)

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["22ff89586561fc2d52f77491e9f1eff1b80be33e"]

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  github_oidc = {
    Federated = aws_iam_openid_connect_provider.github.arn
  }

  roles = {
    # backend 배포(backend 저장소 GitHub Actions)
    backend = {
      name        = "role-prod-github-actions"
      description = null
      assume_role_policy = {
        Statement = [{
          Action = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
              # backend cd.yml의 production environment 배포만 허용(#68, #74)
              "token.actions.githubusercontent.com:sub" = "repo:BOAZ-website/backend:environment:production"
            }
          }
          Effect    = "Allow"
          Principal = local.github_oidc
        }]
        Version = "2012-10-17"
      }
    }

    # www 프론트 배포(frontend 저장소 GitHub Actions)
    frontend = {
      name        = "role-prod-github-actions-frontend"
      description = null
      assume_role_policy = {
        Statement = [{
          Action = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
              # frontend deploy-www.yml의 Production environment 배포만 허용(environment 배포 브랜치는 main만, #68, #74)
              "token.actions.githubusercontent.com:sub" = "repo:BOAZ-website/frontend:environment:production"
            }
          }
          Effect    = "Allow"
          Principal = local.github_oidc
        }]
        Version = "2012-10-17"
      }
    }

    # 관리자 콘솔 배포(frontend_admin 저장소 main 브랜치만, IAM-01)
    # 2026-07-15 이후 생성 저장소라 immutable subject 형식을 씀(bootstrap/ci_plan_role.tf와 같음)
    frontend_admin = {
      name        = "role-prod-github-actions-frontend-admin"
      description = "GitHub Actions OIDC deploy role for frontend_admin (admin console). IAM-01"
      assume_role_policy = {
        Statement = [{
          Action = "sts:AssumeRoleWithWebIdentity"
          Condition = {
            StringEquals = {
              "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
              "token.actions.githubusercontent.com:sub" = "repo:BOAZ-website@258640138/frontend_admin@1351152812:ref:refs/heads/main"
            }
          }
          Effect    = "Allow"
          Principal = local.github_oidc
        }]
        Version = "2012-10-17"
      }
    }

    # CodeDeploy 서비스 롤(deploy 그룹이 output으로 참조)
    codedeploy = {
      name        = "role-prod-codedeploy"
      description = "Allows AWS CodeDeploy to perform deployment operations on behalf of the application.\n\nKey permissions:\n- Accessing EC2 instances and deployment target resources\n- Reading deployment artifacts stored in Amazon S3\n- Creating and managing application deployments\n- Interacting with AWS resources required during the deployment process"
      assume_role_policy = {
        Statement = [{
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "codedeploy.amazonaws.com"
          }
          Sid = ""
        }]
        Version = "2012-10-17"
      }
    }

    # EC2 롤(인스턴스 프로파일로 EC2-A·B에 연결)
    ec2 = {
      name        = "role-prod-ec2"
      description = "Allows EC2 instances to securely access AWS services on behalf of the application, including:\n- Downloading deployment artifacts from Amazon S3\n- Writing application and system logs to Amazon CloudWatch Logs\n- Reading configuration and secrets from AWS Systems Manager Parameter Store"
      assume_role_policy = {
        Statement = [{
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "ec2.amazonaws.com"
          }
        }]
        Version = "2012-10-17"
      }
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.roles

  name               = each.value.name
  description        = each.value.description
  assume_role_policy = jsonencode(each.value.assume_role_policy)

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_instance_profile" "ec2" {
  name = "role-prod-ec2"
  role = aws_iam_role.this["ec2"].name

  lifecycle {
    prevent_destroy = true
  }
}
