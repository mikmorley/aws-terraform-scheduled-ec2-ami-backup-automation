variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "timeout" {
  type    = number
  default = 60
}

variable "backup_tag" {
  type        = string
  default     = "Backup"
  description = "The EC2 Instance Tag that will be checked for the 'yes' value, to backup."
}

variable "backup_retention" {
  type        = number
  default     = 30
  description = "The number of days a backup will be kept."
}

variable "schedule_expression" {
  description = "Scheduling expression for triggering the Lambda Function using CloudWatch events. For example, cron(0 20 * * ? *) or rate(5 minutes)."
}

resource "aws_iam_role" "default" {
  name = "${var.name}-${var.region}"
  path = "/service-role/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com"
        ]
      },
      "Action": [
        "sts:AssumeRole"
      ]
    }
  ]
}
  EOF
}

resource "aws_iam_policy_attachment" "default" {
  name       = "permissions-for-${var.name}-${var.region}"
  roles      = [aws_iam_role.default.name]
  policy_arn = aws_iam_policy.default.arn
}

data "aws_iam_policy_document" "default" {
  statement {
    actions = [
      "cloudtrail:LookupEvents"
    ]
    resources = [
      "*"
    ]
    effect = "Allow"
  }

  statement {
    actions = [
      "ec2:CreateSnapshot",
      "ec2:CreateSnapshots",
      "ec2:CreateImage",
      "ec2:CreateTags",
      "ec2:Describe*",
      "ec2:DeleteSnapshot",
      "ec2:DeregisterImage",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "*"
    ]
    effect = "Allow"
  }
}

resource "aws_iam_policy" "default" {
  name        = "${var.name}-${var.region}"
  path        = "/service/"
  description = "Enables a Lambda function read and manage EC2 AMIs"

  policy = data.aws_iam_policy_document.default.json
}

resource "aws_cloudwatch_log_group" "default" {
  name              = "/aws/lambda/${aws_lambda_function.default.function_name}"
  retention_in_days = 14

  tags = {
    Name        = var.name
    Environment = var.environment
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/"
  output_path = "${path.module}/zip/lambda_function.zip"
}

resource "aws_lambda_function" "default" {
  function_name    = "${var.name}-${var.region}"
  filename         = data.archive_file.lambda_zip.output_path
  description      = "EC2 AMI Backup Automation"
  role             = aws_iam_role.default.arn
  handler          = "index.handler"
  runtime          = "nodejs12.x"
  timeout          = var.timeout
  memory_size      = 128
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      backup_tag       = var.backup_tag
      backup_retention = var.backup_retention
    }
  }

  tags = {
    Name        = var.name
    Type        = "Lambda Function"
    Environment = var.environment
  }
}

resource "aws_lambda_permission" "default" {
  statement_id  = "ScaleUpExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.default.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.default.arn
}

resource "aws_cloudwatch_event_rule" "default" {
  name                = "${var.name}-${var.region}-trigger"
  description         = "Triggers AMI Backup of EC2 Instances"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "default" {
  rule = aws_cloudwatch_event_rule.default.name
  arn  = aws_lambda_function.default.arn
}
