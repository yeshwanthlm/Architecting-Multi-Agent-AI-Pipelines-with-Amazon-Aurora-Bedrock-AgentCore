##############################################################################
# SSM Document — Bootstrap VSCode Instance
##############################################################################

resource "aws_ssm_document" "client_bootstrap" {
  name          = "electrify-bootstrap-client-${local.region}-${local.suffix}"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Bootstrap VSCode Server IDE Instance"
    parameters = {
      VSCodePassword = {
        type    = "String"
        default = jsondecode(aws_secretsmanager_secret_version.vscode.secret_string)["password"]
      }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "BootstrapTools"
      inputs = {
        runCommand = [
          "#!/bin/bash -xe",
          "exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1",
          "echo \"$(date \"+%F %T\") * running as $(whoami)\" >> /bootstrap.log",
          "dnf install -y --allowerasing curl gnupg whois argon2 nginx openssl unzip jq ncurses-compat-libs git autoconf libtool pip npm nodejs24",
          "alternatives --set node /usr/bin/node-24",
          "export HOME=/home/${var.vscode_user} && curl -fsSL https://cli.kiro.dev/install | bash",
          "adduser -c '' ${var.vscode_user}",
          "passwd -l ${var.vscode_user}",
          "echo '${var.vscode_user}:{{ VSCodePassword }}' | chpasswd",
          "usermod -aG wheel ${var.vscode_user}",
          "echo LANG=en_US.utf-8 >> /etc/environment",
          "echo LC_ALL=en_US.UTF-8 >> /etc/environment",
          "mkdir -p /tmp && curl -fsSL https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip -o /tmp/aws-cli.zip",
          "unzip -q -d /tmp /tmp/aws-cli.zip && sudo /tmp/aws/install --update && rm -rf /tmp/aws",
          "sudo dnf install postgresql17 -y && pip install uv",
          "mkdir -p /home/${var.vscode_user}${var.home_folder}",
          "mkdir -p /root/seed && cd /root/seed",
          "curl -O https://rivassets.s3.us-east-1.amazonaws.com/dat403riv2025/supportscripts.zip && unzip -o supportscripts.zip",
          "export SECRETSTRING=`aws secretsmanager get-secret-value --secret-id '${aws_secretsmanager_secret.cluster_admin.name}' --region ${local.region} | jq -r '.SecretString'` && export DBPASS=`echo $SECRETSTRING | jq -r '.password'` && export DBUSER=`echo $SECRETSTRING | jq -r '.username'`",
          "echo \"export DBPASS=\\\"$DBPASS\\\" DBUSER=$DBUSER PGPASSWORD=\\\"$DBPASS\\\" PGUSER=$DBUSER\" >> /home/${var.vscode_user}/.bashrc",
          "echo \"export PGPASSWORD=\\\"$DBPASS\\\" PGUSER=$DBUSER\" >> /root/.bashrc",
          "cat >> /home/${var.vscode_user}/.bashrc <<EOF\nexport PGHOST='${aws_rds_cluster.main.endpoint}'\nexport PGSECRET='${aws_secretsmanager_secret.cluster_admin.name}'\nexport PGDATABASE=postgres\nexport MODEL_REGION=us-west-2\nexport MODEL_ID=global.anthropic.claude-sonnet-4-20250514-v1:0\nexport PGHOSTARN='${aws_rds_cluster.main.arn}'\nexport IDENTITY_POOL='${aws_cognito_identity_pool.main.id}'\nexport COGNITO_POOL='${aws_cognito_user_pool.customers.id}'\nexport COGNITO_CLIENT='${aws_cognito_user_pool_client.customers.id}'\nexport COGNITO_DOMAIN='${aws_cognito_user_pool_domain.customers.domain}'\nexport BACKEND_API_ID='${aws_apigatewayv2_api.http.id}'\nexport API_CREDENTIALS_ARN='${aws_iam_role.api_invoke_lambda.arn}'\nexport CONTENTBUCKET='${aws_s3_bucket.website.bucket}'\nexport CLOUDFRONT_DISTRIBUTION_ID='${aws_cloudfront_distribution.website.id}'\nexport AGENTCORE_ROLE_ARN='${aws_iam_role.agentcore_sdk_runtime.arn}'\nexport OAUTH_ISSUER_URL='https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.customers.id}/.well-known/openid-configuration'\nEOF",
          "cat >> /root/.bashrc <<EOF\nexport PGHOST='${aws_rds_cluster.main.endpoint}'\nexport PGDBNODE='${aws_rds_cluster_instance.node_1.endpoint}'\nexport PGDATABASE=postgres\nEOF",
          "if curl -fsSL https://raw.githubusercontent.com/coder/code-server/main/install.sh | bash -s --; then echo ok; elif curl -fsSL https://code-server.dev/install.sh | bash -s --; then echo fallback; else exit 1; fi",
          "systemctl enable --now code-server@${var.vscode_user}",
          "mkdir -p /home/${var.vscode_user}/.config/code-server",
          "tee /home/${var.vscode_user}/.config/code-server/config.yaml <<EOF\nbind-addr: 127.0.0.1:${var.vscode_server_port}\ncert: false\nauth: password\nhashed-password: \"$(echo -n '{{ VSCodePassword }}' | argon2 $(openssl rand -base64 12) -e)\"\nEOF",
          "systemctl enable nginx.service",
          "sudo -u ${var.vscode_user} --login code-server --install-extension amazonwebservices.aws-toolkit-vscode --force || true",
          "sudo -u ${var.vscode_user} --login code-server --install-extension amazonwebservices.amazon-q-vscode --force || true",
          "source /root/.bashrc && psql -d postgres -f /root/seed/init_schema.sql",
          "cd /root/seed && uv sync && uv run populate.py",
          "chown -R ${var.vscode_user}:${var.vscode_user} /home/${var.vscode_user}",
          "systemctl restart code-server@${var.vscode_user}",
          "systemctl restart nginx",
          "sudo dnf -y --releasever=latest update",
          "echo \"$(date \"+%F %T\") * Bootstrap complete\" >> /bootstrap.log"
        ]
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "electrify-bootstrap-client-${local.region}-${local.suffix}"
  })
}

##############################################################################
# EC2 — VSCode IDE Instance
##############################################################################

resource "aws_instance" "vscode_ide" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = local.ide_type
  subnet_id              = aws_subnet.public_1.id
  vpc_security_group_ids = [aws_security_group.client.id]
  iam_instance_profile   = aws_iam_instance_profile.client_ide.name

  root_block_device {
    device_name           = "/dev/xvda"
    volume_size           = 80
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    mkdir -p ${var.home_folder} && chown -R ${var.vscode_user}:${var.vscode_user} ${var.home_folder}
  EOF
  )

  tags = merge(local.common_tags, {
    Name           = "electrify-VSCode-ide-${local.region}-${local.suffix}"
    BootstrapGroup = "bootstrap-${local.suffix}"
  })
}

##############################################################################
# CloudFront — Cache Policy for VSCode IDE
##############################################################################

resource "aws_cloudfront_cache_policy" "vscode" {
  name        = "${var.instance_name}-${local.suffix}"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "all"
    }
    enable_accept_encoding_gzip = false
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = [
          "Accept-Charset", "Authorization", "Origin", "Accept",
          "Referer", "Host", "Accept-Language", "Accept-Encoding", "Accept-Datetime"
        ]
      }
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

##############################################################################
# CloudFront — VSCode IDE Distribution
##############################################################################

resource "aws_cloudfront_distribution" "vscode_ide" {
  enabled     = true
  http_version = "http2and3"

  origin {
    domain_name = aws_instance.vscode_ide.public_dns
    origin_id   = "CloudFront-${local.suffix}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "CloudFront-${local.suffix}"
    viewer_protocol_policy   = "allow-all"
    cache_policy_id          = aws_cloudfront_cache_policy.vscode.id
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
  }

  ordered_cache_behavior {
    path_pattern             = "/proxy/*"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "CloudFront-${local.suffix}"
    viewer_protocol_policy   = "allow-all"
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
    origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    compress                 = false
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.common_tags, {
    Name = "electrify-VSCode-dist-${local.region}-${local.suffix}"
  })
}
