##############################################################################
# Lambda — Layer Builder Function
# Builds psycopg2-binary + requests layer and uploads to S3
##############################################################################

resource "aws_lambda_function" "layer_builder" {
  function_name = "${local.suffix}-layer-builder"
  description   = "Custom Resource to create lambda layer"
  handler       = "index.handler"
  runtime       = "python3.13"
  role          = aws_iam_role.lambda_layer_builder.arn
  timeout       = 120
  memory_size   = 512

  environment {
    variables = {
      S3BUCKET = aws_s3_bucket.data.bucket
    }
  }

  filename         = data.archive_file.layer_builder.output_path
  source_code_hash = data.archive_file.layer_builder.output_base64sha256

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-layer-builder"
  })
}

data "archive_file" "layer_builder" {
  type        = "zip"
  output_path = "${path.module}/.terraform/tmp/layer_builder.zip"

  source {
    content  = <<-PYTHON
import os, sys, shutil, subprocess, boto3, zipfile
from datetime import datetime
import cfnresponse

target_bucket = os.environ['S3BUCKET']

def upload_file_to_s3(file_path, bucket, key):
    s3 = boto3.client('s3')
    s3.upload_file(file_path, bucket, key)

def make_zip_filename():
    now = datetime.now()
    timestamp = now.strftime('%Y%m%d_%H%M%S')
    return f'PyImportLayers_{timestamp}.zip'

def zipdir(path, zipname):
    zipf = zipfile.ZipFile(zipname, 'w', zipfile.ZIP_DEFLATED)
    for root, dirs, files in os.walk(path):
        for file in files:
            zipf.write(os.path.join(root, file),
                       os.path.relpath(os.path.join(root, file), os.path.join(path, '..')))
    zipf.close()

def empty_bucket(bucket_name):
    s3_client = boto3.client('s3')
    response = s3_client.list_objects_v2(Bucket=bucket_name)
    if 'Contents' in response:
        keys = [{'Key': obj['Key']} for obj in response['Contents']]
        s3_client.delete_objects(Bucket=bucket_name, Delete={'Objects': keys})

def handler(event, context):
    responseData = {"Bucket": "", "Key": ""}
    reason = ""
    status = cfnresponse.SUCCESS
    try:
        if event['RequestType'] != 'Delete':
            layers = ['psycopg2-binary', 'requests']
            os.chdir('/tmp')
            if os.path.exists("python"):
                shutil.rmtree("python")
            os.mkdir("python")
            for layer in layers:
                subprocess.check_call([sys.executable, "-m", "pip", "install", layer, "-t", "python", "--upgrade"])
            target_zip_file = make_zip_filename()
            zipdir("python", target_zip_file)
            upload_file_to_s3(target_zip_file, target_bucket, "layers/%s" % target_zip_file)
            responseData = {"Bucket": target_bucket, "Key": "layers/%s" % target_zip_file}
        else:
            empty_bucket(target_bucket)
    except Exception as e:
        status = cfnresponse.FAILED
        reason = f"Exception thrown: {e}"
    cfnresponse.send(event, context, status, responseData, reason=reason)
PYTHON
    filename = "index.py"
  }
}

# Trigger the layer builder on first apply via a null_resource (Terraform replacement for CFN Custom Resource)
resource "terraform_data" "build_lambda_layer" {
  triggers_replace = [aws_lambda_function.layer_builder.arn]

  provisioner "local-exec" {
    command = <<-BASH
      aws lambda invoke \
        --function-name ${aws_lambda_function.layer_builder.function_name} \
        --region ${local.region} \
        --payload '{"RequestType":"Create","ResponseURL":"http://localhost","StackId":"arn:aws:cloudformation:x:x:stack/x/x","RequestId":"x","LogicalResourceId":"x","ResourceProperties":{"S3BUCKET":"${aws_s3_bucket.data.bucket}"}}' \
        --cli-binary-format raw-in-base64-out \
        /tmp/layer_builder_response.json && \
      cat /tmp/layer_builder_response.json
    BASH
  }
}

##############################################################################
# Lambda — Copy Lambda Code Function
# Downloads app.zip from public URL and places it in the data S3 bucket
##############################################################################

resource "aws_lambda_function" "copy_lambda_code" {
  function_name = "${local.suffix}-copy-lambda-code"
  description   = "Copy Lambda code from source S3 bucket"
  handler       = "index.handler"
  runtime       = "python3.13"
  role          = aws_iam_role.lambda_layer_builder.arn
  timeout       = 60

  environment {
    variables = {
      TARGET_BUCKET = aws_s3_bucket.data.bucket
    }
  }

  filename         = data.archive_file.copy_lambda_code.output_path
  source_code_hash = data.archive_file.copy_lambda_code.output_base64sha256

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-copy-lambda-code"
  })
}

data "archive_file" "copy_lambda_code" {
  type        = "zip"
  output_path = "${path.module}/.terraform/tmp/copy_lambda_code.zip"

  source {
    content  = <<-PYTHON
import boto3, os, urllib.request, cfnresponse

def handler(event, context):
    try:
        if event['RequestType'] == 'Delete':
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            return
        target_bucket = os.environ['TARGET_BUCKET']
        s3 = boto3.client('s3')
        url = 'https://rivassets.s3.us-east-1.amazonaws.com/dat403riv2025/app.zip'
        with urllib.request.urlopen(url) as response:
            data = response.read()
        s3.put_object(Bucket=target_bucket, Key='api/app.zip', Body=data)
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
    except Exception as e:
        cfnresponse.send(event, context, cfnresponse.FAILED, {'Error': str(e)})
PYTHON
    filename = "index.py"
  }
}

resource "terraform_data" "copy_lambda_code" {
  triggers_replace = [aws_lambda_function.copy_lambda_code.arn]

  provisioner "local-exec" {
    command = <<-BASH
      aws lambda invoke \
        --function-name ${aws_lambda_function.copy_lambda_code.function_name} \
        --region ${local.region} \
        --payload '{"RequestType":"Create","ResponseURL":"http://localhost","StackId":"arn:x","RequestId":"x","LogicalResourceId":"x","ResourceProperties":{}}' \
        --cli-binary-format raw-in-base64-out \
        /tmp/copy_code_response.json && \
      cat /tmp/copy_code_response.json
    BASH
  }
}

##############################################################################
# Lambda — psycopg2 Layer
# NOTE: The S3 key is resolved after the layer_builder runs.
# We reference a known prefix; the exact filename is timestamped by the builder.
##############################################################################

# Retrieve the layer zip key from the builder output
data "aws_s3_objects" "layer_zip" {
  bucket = aws_s3_bucket.data.bucket
  prefix = "layers/"

  depends_on = [terraform_data.build_lambda_layer]
}

resource "aws_lambda_layer_version" "psycopg2" {
  layer_name          = "${local.suffix}-layer-psycopg2"
  s3_bucket           = aws_s3_bucket.data.bucket
  s3_key              = reverse(sort(data.aws_s3_objects.layer_zip.keys))[0]
  compatible_runtimes = ["python3.13"]

  depends_on = [terraform_data.build_lambda_layer]
}

##############################################################################
# Lambda — Monolith API Function
##############################################################################

resource "aws_lambda_function" "api_monolith" {
  function_name = "${local.suffix}-monolith"
  description   = "Lambda function to handle monolith API requests"
  handler       = "app.handler"
  runtime       = "python3.13"
  role          = aws_iam_role.monolith.arn
  timeout       = 30
  s3_bucket     = aws_s3_bucket.data.bucket
  s3_key        = "api/app.zip"

  layers = [
    "arn:aws:lambda:${local.region}:017000801446:layer:AWSLambdaPowertoolsPythonV2:47",
    aws_lambda_layer_version.psycopg2.arn,
  ]

  vpc_config {
    security_group_ids = [aws_security_group.client.id]
    subnet_ids = [
      aws_subnet.private_1.id,
      aws_subnet.private_2.id,
      aws_subnet.private_3.id,
    ]
  }

  environment {
    variables = {
      REGION                  = local.region
      LOG_LEVEL               = "DEBUG"
      POWERTOOLS_SERVICE_NAME = "ApiMonolith"
      DBSECRET                = aws_secretsmanager_secret.cluster_admin.name
      DBENDPOINT              = aws_rds_cluster.main.endpoint
      DBSCHEMA                = "postgres"
      ORIGINKEY               = local.suffix
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-monolith"
  })

  depends_on = [terraform_data.copy_lambda_code]
}

##############################################################################
# Lambda — Secret Plaintext Function
# Returns the plaintext value of a Secrets Manager secret (used in outputs)
##############################################################################

resource "aws_lambda_function" "secret_plaintext" {
  function_name = "${local.suffix}-SecretPlaintext-${local.region}"
  description   = "Return the value of the secret"
  handler       = "index.lambda_handler"
  runtime       = "python3.13"
  role          = aws_iam_role.secret_plaintext_lambda.arn
  memory_size   = 128
  timeout       = 10

  filename         = data.archive_file.secret_plaintext.output_path
  source_code_hash = data.archive_file.secret_plaintext.output_base64sha256

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-SecretPlaintext-${local.region}"
  })
}

data "archive_file" "secret_plaintext" {
  type        = "zip"
  output_path = "${path.module}/.terraform/tmp/secret_plaintext.zip"

  source {
    content  = <<-PYTHON
import boto3, json, cfnresponse, logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def is_valid_json(json_string):
    try:
        json.loads(json_string)
        return True
    except json.JSONDecodeError:
        return False

def lambda_handler(event, context):
    try:
        if event['RequestType'] == 'Delete':
            cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData={}, reason='No action to take')
        else:
            secret_name = event['ResourceProperties']['SecretArn']
            secrets_mgr = boto3.client('secretsmanager')
            secret = secrets_mgr.get_secret_value(SecretId=secret_name)
            secret_value = secret['SecretString']
            responseData = json.loads(secret_value) if is_valid_json(secret_value) else {'secret': secret_value}
            cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData=responseData, reason='OK', noEcho=True)
    except Exception as e:
        cfnresponse.send(event, context, cfnresponse.FAILED, responseData={}, reason=str(e))
PYTHON
    filename = "index.py"
  }
}

##############################################################################
# Lambda — Lab Support Function
# Handles bootstrap triggering and cleanup operations
##############################################################################

resource "aws_lambda_function" "lab_support" {
  function_name = "${local.suffix}-support-${local.region}"
  description   = "Custom Resource to provide support operations for the Aurora postgres labs."
  handler       = "index.handler"
  runtime       = "python3.13"
  role          = aws_iam_role.lab_support.arn
  timeout       = 600

  filename         = data.archive_file.lab_support.output_path
  source_code_hash = data.archive_file.lab_support.output_base64sha256

  environment {
    variables = {
      REGION = local.region
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-support-${local.region}"
  })

  depends_on = [aws_instance.vscode_ide]
}

data "archive_file" "lab_support" {
  type        = "zip"
  output_path = "${path.module}/.terraform/tmp/lab_support.zip"

  source {
    content  = <<-PYTHON
from os import environ
import boto3, time

session = boto3.session.Session(region_name=environ["REGION"])
ec2 = session.client('ec2')
ssm = session.client('ssm')

def handler(event, context):
    props = event["ResourceProperties"]
    response_data = {}
    try:
        response_data["DBClusterId"] = props["Cluster"].lower()
        if event["RequestType"] == 'Create':
            result = ec2.describe_instances(Filters=[{'Name': 'tag:Name','Values': [props['IDEEnvTagName']]}])
            if 'Reservations' in result and len(result['Reservations']) > 0:
                vscode = result['Reservations'][0]['Instances'][0]
                while vscode['State']['Name'] != 'running':
                    time.sleep(5)
                    vscode = ec2.describe_instances(InstanceIds=[vscode['InstanceId']])['Reservations'][0]['Instances'][0]
                status = 'Offline'
                tries = 0
                while status != 'Online' and tries < 50:
                    response = ssm.describe_instance_information(Filters=[{'Key': 'InstanceIds', 'Values': [vscode['InstanceId']]}])
                    if 'InstanceInformationList' in response and len(response['InstanceInformationList']) > 0:
                        status = response['InstanceInformationList'][0]['PingStatus']
                    tries += 1
                    time.sleep(10)
                if status == 'Online':
                    ssm.send_command(InstanceIds=[vscode['InstanceId']], DocumentName=props["IDEBoostrapDoc"])
    except Exception as e:
        print("[ERROR]", e)
PYTHON
    filename = "index.py"
  }
}

# Trigger the lab support function (equivalent to CFN Custom Resource)
resource "terraform_data" "lab_support" {
  triggers_replace = [
    aws_instance.vscode_ide.id,
    aws_ssm_document.client_bootstrap.name,
  ]

  provisioner "local-exec" {
    command = <<-BASH
      aws lambda invoke \
        --function-name ${aws_lambda_function.lab_support.function_name} \
        --region ${local.region} \
        --payload '{
          "RequestType":"Create",
          "ResponseURL":"http://localhost",
          "StackId":"arn:x",
          "RequestId":"x",
          "LogicalResourceId":"x",
          "ResourceProperties":{
            "Cluster":"${aws_rds_cluster.main.cluster_identifier}",
            "IDEEnvTagName":"electrify-VSCode-ide-${local.region}-${local.suffix}",
            "IDEBoostrapDoc":"${aws_ssm_document.client_bootstrap.name}"
          }
        }' \
        --cli-binary-format raw-in-base64-out \
        /tmp/lab_support_response.json && \
      cat /tmp/lab_support_response.json
    BASH
  }
}

##############################################################################
# Lambda — Set Cognito User Password Function
##############################################################################

resource "aws_lambda_function" "set_user_password" {
  function_name = "${local.suffix}-set-user-password"
  handler       = "index.handler"
  runtime       = "python3.13"
  role          = aws_iam_role.set_user_password.arn
  timeout       = 30

  filename         = data.archive_file.set_user_password.output_path
  source_code_hash = data.archive_file.set_user_password.output_base64sha256

  tags = merge(local.common_tags, {
    Name = "${local.suffix}-set-user-password"
  })
}

data "archive_file" "set_user_password" {
  type        = "zip"
  output_path = "${path.module}/.terraform/tmp/set_user_password.zip"

  source {
    content  = <<-PYTHON
import boto3, cfnresponse, json

def handler(event, context):
    try:
        if event['RequestType'] == 'Delete':
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            return
        cognito = boto3.client('cognito-idp')
        secrets = boto3.client('secretsmanager')
        user_pool_id = event['ResourceProperties']['UserPoolId']
        username = event['ResourceProperties']['Username']
        secret_arn = event['ResourceProperties']['SecretArn']
        secret_response = secrets.get_secret_value(SecretId=secret_arn)
        password = secret_response['SecretString']
        cognito.admin_set_user_password(UserPoolId=user_pool_id, Username=username, Password=password, Permanent=True)
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {'Password': password})
    except Exception as e:
        cfnresponse.send(event, context, cfnresponse.FAILED, {'Error': str(e)})
PYTHON
    filename = "index.py"
  }
}

# Trigger the set user password function
resource "terraform_data" "set_user_password" {
  triggers_replace = [
    aws_cognito_user.test_user.id,
    aws_secretsmanager_secret_version.cognito_test_user_password.id,
  ]

  provisioner "local-exec" {
    command = <<-BASH
      aws lambda invoke \
        --function-name ${aws_lambda_function.set_user_password.function_name} \
        --region ${local.region} \
        --payload '{
          "RequestType":"Create",
          "ResponseURL":"http://localhost",
          "StackId":"arn:x",
          "RequestId":"x",
          "LogicalResourceId":"x",
          "ResourceProperties":{
            "UserPoolId":"${aws_cognito_user_pool.customers.id}",
            "Username":"rroe@example.com",
            "SecretArn":"${aws_secretsmanager_secret.cognito_test_user_password.arn}"
          }
        }' \
        --cli-binary-format raw-in-base64-out \
        /tmp/set_password_response.json && \
      cat /tmp/set_password_response.json
    BASH
  }
}
