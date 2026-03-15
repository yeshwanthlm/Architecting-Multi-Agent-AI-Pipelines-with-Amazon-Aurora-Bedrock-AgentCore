##############################################################################
# IAM — Enhanced Monitoring Role (RDS)
##############################################################################

resource "aws_iam_role" "enhanced_monitoring" {
  name        = "electrify-monitor-${local.region}-${local.suffix}"
  description = "Allows your Aurora DB cluster to deliver Enhanced Monitoring metrics."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
  ]

  tags = merge(local.common_tags, {
    Name = "electrify-monitor-${local.region}-${local.suffix}"
  })
}

##############################################################################
# IAM — Service Integration Role (RDS → S3)
##############################################################################

resource "aws_iam_role" "service_integration" {
  name        = "electrify-integrate-${local.region}-${local.suffix}"
  description = "Allows Aurora DB cluster to integrate with other AWS services such as S3."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "rds.amazonaws.com" }
    }]
  })

  inline_policy {
    name = "inline-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "s3:ListBucket", "s3:GetObject", "s3:GetObjectVersion",
          "s3:AbortMultipartUpload", "s3:DeleteObject",
          "s3:ListMultipartUploadParts", "s3:PutObject"
        ]
        Resource = ["arn:aws:s3:::*/*", "arn:aws:s3:::*"]
      }]
    })
  }

  tags = merge(local.common_tags, {
    Name = "electrify-integrate-${local.region}-${local.suffix}"
  })
}

##############################################################################
# IAM — AgentCore SDK Runtime Role
##############################################################################

resource "aws_iam_role" "agentcore_sdk_runtime" {
  name = "AmazonBedrockAgentCoreSDKRuntime-${local.region}-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = ["bedrock-agentcore.amazonaws.com", "lambda.amazonaws.com"]
      }
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonBedrockFullAccess",
    "arn:aws:iam::aws:policy/BedrockAgentCoreFullAccess",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole",
  ]

  inline_policy {
    name = "AgentCoreRuntimePolicy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "AgentCoreRuntimeAccess"
          Effect   = "Allow"
          Action   = ["bedrock-agentcore:*"]
          Resource = "*"
        },
        {
          Sid    = "MemoryAccess"
          Effect = "Allow"
          Action = [
            "bedrock-agentcore:CreateMemory", "bedrock-agentcore:DeleteMemory",
            "bedrock-agentcore:GetMemory", "bedrock-agentcore:UpdateMemory",
            "bedrock-agentcore:ListMemories", "bedrock-agentcore:RetrieveMemories",
            "bedrock-agentcore:CreateEvent", "bedrock-agentcore:GetEvent",
            "bedrock-agentcore:ListEvents", "bedrock-agentcore:DeleteEvent"
          ]
          Resource = "arn:aws:bedrock-agentcore:*:*:memory/*"
        },
        {
          Sid    = "GatewayAccess"
          Effect = "Allow"
          Action = [
            "bedrock-agentcore:CreateGateway", "bedrock-agentcore:DeleteGateway",
            "bedrock-agentcore:GetGateway", "bedrock-agentcore:UpdateGateway",
            "bedrock-agentcore:ListGateways", "bedrock-agentcore:CreateGatewayTarget",
            "bedrock-agentcore:DeleteGatewayTarget", "bedrock-agentcore:GetGatewayTarget",
            "bedrock-agentcore:UpdateGatewayTarget", "bedrock-agentcore:ListGatewayTargets",
            "bedrock-agentcore:InvokeGateway"
          ]
          Resource = "*"
        },
        {
          Sid    = "RuntimeAccess"
          Effect = "Allow"
          Action = [
            "bedrock-agentcore:CreateAgentRuntime", "bedrock-agentcore:DeleteAgentRuntime",
            "bedrock-agentcore:GetAgentRuntime", "bedrock-agentcore:UpdateAgentRuntime",
            "bedrock-agentcore:ListAgentRuntimes", "bedrock-agentcore:InvokeAgentRuntime"
          ]
          Resource = "*"
        },
        {
          Sid    = "CloudWatchLogsAccess"
          Effect = "Allow"
          Action = ["logs:*"]
          Resource = "*"
        },
        {
          Sid    = "XRayAccess"
          Effect = "Allow"
          Action = [
            "xray:PutTraceSegments", "xray:PutTelemetryRecords",
            "xray:GetSamplingRules", "xray:GetSamplingTargets"
          ]
          Resource = "*"
        },
        {
          Sid      = "SecretsManagerAccess"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = "*"
        },
        {
          Sid    = "BedrockModelAccess"
          Effect = "Allow"
          Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
          Resource = "*"
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "AmazonBedrockAgentCoreSDKRuntime-${local.region}-${local.suffix}"
  })
}

##############################################################################
# IAM — Client IDE Role + Instance Profile
##############################################################################

resource "aws_iam_role" "client_ide" {
  name        = "electrify-ide-${local.region}-${local.suffix}"
  description = "Permits user interaction with AWS APIs from the VSCode IDE."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = ["ec2.amazonaws.com", "ssm.amazonaws.com"]
      }
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess",
    "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonQDeveloperAccess",
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonBedrockFullAccess",
    "arn:aws:iam::aws:policy/BedrockAgentCoreFullAccess",
    "arn:aws:iam::aws:policy/AWSLambda_FullAccess",
    "arn:aws:iam::aws:policy/AmazonCognitoPowerUser",
  ]

  inline_policy {
    name = "inline-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Action = [
            "rds:*", "s3:*", "ssm:*", "kinesis:*", "kms:*", "sns:*",
            "secretsmanager:*", "rds-db:connect",
            "ec2:CreateVpcPeeringConnection", "ec2:DescribeVpcPeeringConnections",
            "ec2:ModifyVolume", "ec2:ModifyVolumeAttribute",
            "ec2:DescribeVolumesModifications", "ec2:AcceptVpcPeeringConnection",
            "ec2:DescribeRegions", "lambda:UpdateFunctionCode",
            "lambda:UpdateFunctionConfiguration",
            "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy",
            "iam:DeleteRolePolicy", "iam:GetRolePolicy", "iam:CreatePolicy",
            "iam:DeletePolicy", "iam:CreateRole", "iam:DeleteRole",
            "iam:ListPolicies", "iam:ListRoles", "iam:PassRole",
            "rds-data:*", "logs:*", "aws-marketplace:Subscribe",
            "cloudfront:CreateInvalidation"
          ]
          Resource = "*"
        },
        {
          Sid    = "CreateBedrockAgentCoreIdentityServiceLinkedRolePermissions"
          Effect = "Allow"
          Action = "iam:CreateServiceLinkedRole"
          Resource = "arn:aws:iam::*:role/aws-service-role/runtime-identity.bedrock-agentcore.amazonaws.com/AWSServiceRoleForBedrockAgentCoreRuntimeIdentity"
          Condition = {
            StringEquals = {
              "iam:AWSServiceName" = "runtime-identity.bedrock-agentcore.amazonaws.com"
            }
          }
        },
        {
          Sid    = "BedrockAgentCoreMemoryAccess"
          Effect = "Allow"
          Action = [
            "bedrock-agentcore:ListEvents", "bedrock-agentcore:CreateEvent",
            "bedrock-agentcore:GetEvent", "bedrock-agentcore:GetGateway",
            "bedrock-agentcore:DeleteEvent", "bedrock-agentcore:ListMemories",
            "bedrock-agentcore:CreateMemory", "bedrock-agentcore:GetMemory",
            "bedrock-agentcore:DeleteMemory", "bedrock-agentcore:UpdateMemory",
            "bedrock-agentcore:RetrieveMemories"
          ]
          Resource = "arn:aws:bedrock-agentcore:*:*:memory/*"
        },
        {
          Sid    = "AgentCoreObservabilityAccess"
          Effect = "Allow"
          Action = [
            "logs:CreateLogDelivery", "logs:PutDeliveryDestination",
            "logs:PutDeliveryDestinationPolicy", "logs:PutDeliverySource",
            "logs:CreateDelivery", "logs:GetDelivery", "logs:DeleteDelivery",
            "logs:DescribeDeliveries", "logs:DescribeDeliverySources",
            "logs:DescribeDeliveryDestinations", "logs:GetDeliveryDestination",
            "logs:GetDeliveryDestinationPolicy", "logs:GetDeliverySource",
            "logs:DeleteDeliveryDestination", "logs:DeleteDeliveryDestinationPolicy",
            "logs:DeleteDeliverySource", "logs:PutResourcePolicy",
            "logs:DescribeResourcePolicies", "logs:DeleteResourcePolicy"
          ]
          Resource = "*"
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "electrify-ide-${local.region}-${local.suffix}"
  })
}

resource "aws_iam_instance_profile" "client_ide" {
  name = "electrify-ide-${local.region}-${local.suffix}"
  path = "/"
  role = aws_iam_role.client_ide.name

  tags = merge(local.common_tags, {
    Name = "electrify-ide-${local.region}-${local.suffix}"
  })
}

##############################################################################
# IAM — Lab Support Lambda Role
##############################################################################

resource "aws_iam_role" "lab_support" {
  name        = "electrify-support-${local.region}-${local.suffix}"
  description = "Role to permit the Lambda support functions to interact with relevant AWS APIs."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  inline_policy {
    name = "inline-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = "arn:aws:logs:*:*:*"
        },
        {
          Effect = "Allow"
          Action = [
            "cloudformation:DescribeStacks", "cloudformation:DescribeStackEvents",
            "cloudformation:DescribeStackResource", "cloudformation:DescribeStackResources",
            "ec2:DescribeInstances", "ec2:AssociateIamInstanceProfile",
            "ec2:ModifyInstanceAttribute", "ec2:ReplaceIamInstanceProfileAssociation",
            "ec2:DescribeIamInstanceProfileAssociations", "ec2:DisassociateIamInstanceProfile",
            "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces",
            "ec2:DeleteNetworkInterface",
            "iam:ListInstanceProfiles", "iam:PassRole", "iam:GetRole",
            "iam:DeleteRole", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
            "iam:ListAttachedRolePolicies", "iam:DetachRolePolicy",
            "ssm:DescribeInstanceInformation", "ssm:SendCommand",
            "cloudwatch:PutMetricData", "cloudwatch:ListMetrics", "cloudwatch:GetMetricData",
            "s3:ListBucket", "s3:DeleteObject", "s3:DeleteObjectVersion", "s3:ListBucketVersions",
            "cognito-idp:DeleteResourceServer", "lambda:DeleteFunction",
            "bedrock-agentcore:*", "bedrock-agent:ListAgents", "bedrock-agent:DeleteAgent",
            "logs:DescribeLogGroups", "logs:DeleteLogGroup"
          ]
          Resource = "*"
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "electrify-support-${local.region}-${local.suffix}"
  })
}

##############################################################################
# IAM — Secret Plaintext Lambda Role
##############################################################################

resource "aws_iam_role" "secret_plaintext_lambda" {
  name        = "electrify-secretLambda-${local.region}-${local.suffix}"
  description = "Role required for the secretsmanager Lambda function to retrieve password."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  managed_policy_arns = [
    "arn:${local.partition}:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]

  inline_policy {
    name = "AwsSecretsManager"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_secretsmanager_secret.vscode.arn,
          aws_secretsmanager_secret.cognito_test_user_password.arn,
        ]
      }]
    })
  }

  tags = merge(local.common_tags, {
    Name = "electrify-secretLambda-${local.region}-${local.suffix}"
  })
}

##############################################################################
# IAM — Lambda Layer Builder Role
##############################################################################

resource "aws_iam_role" "lambda_layer_builder" {
  name        = "${local.suffix}-layer-builder-${local.region}"
  description = "Role to enable the layer builder function to access services"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  inline_policy {
    name = "inline-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
          Resource = "${aws_s3_bucket.data.arn}*"
        },
        {
          Effect   = "Allow"
          Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = "arn:aws:logs:*:*:*"
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-layer-builder-${local.region}"
  })
}

##############################################################################
# IAM — Monolith Lambda Role
##############################################################################

resource "aws_iam_role" "monolith" {
  name        = "${local.suffix}-monolith-${local.region}"
  description = "Role to allow the monolith API to connect to services"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  ]

  inline_policy {
    name = "inline-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = [aws_secretsmanager_secret.cluster_admin.arn]
        },
        {
          Effect   = "Allow"
          Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = "arn:aws:logs:*:*:*"
        },
        {
          Effect   = "Allow"
          Action   = ["execute-api:Invoke"]
          Resource = "*"
        },
        {
          Effect   = "Allow"
          Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Scan"]
          Resource = "*"
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-monolith-${local.region}"
  })
}

##############################################################################
# IAM — API Gateway Invoke Lambda Role
##############################################################################

resource "aws_iam_role" "api_invoke_lambda" {
  name        = "${local.suffix}-api-invoke-${local.region}"
  description = "Role to allow API Gateway integrations to invoke Lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "apigateway.amazonaws.com" }
    }]
  })

  inline_policy {
    name = "inline-policy"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["lambda:InvokeFunction"]
          Resource = "*"
        },
        {
          Effect   = "Allow"
          Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = "arn:aws:logs:*:*:*"
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-api-invoke-${local.region}"
  })
}

##############################################################################
# IAM — Cognito IdP Roles (Authenticated & Unauthenticated)
##############################################################################

resource "aws_iam_role" "idp_authenticated" {
  name        = "${local.suffix}-idp-authed-${local.region}"
  description = "Role to permit authenticated end users to access AWS services."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Condition = {
        StringEquals           = { "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id }
        "ForAnyValue:StringLike" = { "cognito-identity.amazonaws.com:amr" = "authenticated" }
      }
    }]
  })

  inline_policy {
    name = "inline-policy"
    policy = jsonencode({
      Statement = [{
        Effect   = "Allow"
        Resource = ["*"]
        Action   = ["pricing:*"]
      }]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-idp-authed-${local.region}"
  })
}

resource "aws_iam_role" "idp_unauthenticated" {
  name        = "${local.suffix}-idp-unauthed-${local.region}"
  description = "Role to permit unauthenticated end users to access AWS services."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Condition = {
        StringEquals           = { "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id }
        "ForAnyValue:StringLike" = { "cognito-identity.amazonaws.com:amr" = "unauthenticated" }
      }
    }]
  })

  inline_policy {
    name = "inline-policy"
    policy = jsonencode({
      Statement = [{
        Effect   = "Allow"
        Resource = ["*"]
        Action   = ["pricing:*"]
      }]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-idp-unauthed-${local.region}"
  })
}

##############################################################################
# IAM — Set User Password Lambda Role
##############################################################################

resource "aws_iam_role" "set_user_password" {
  name = "${local.suffix}-set-password-${local.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  ]

  inline_policy {
    name = "CognitoAccess"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["cognito-idp:AdminSetUserPassword"]
          Resource = aws_cognito_user_pool.customers.arn
        },
        {
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = aws_secretsmanager_secret.cognito_test_user_password.arn
        }
      ]
    })
  }

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-set-password-${local.region}"
  })
}
