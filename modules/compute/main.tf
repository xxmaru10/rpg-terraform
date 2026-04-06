# modules/compute/main.tf

# ──────────────────────────────────────────────
# Key Pair
# ──────────────────────────────────────────────
resource "aws_key_pair" "main" {
  key_name   = "${var.project}-${var.env}-key"
  public_key = var.public_key

  tags = var.tags
}

# ──────────────────────────────────────────────
# IAM Role for EC2 (S3 access, SSM, etc.)
# ──────────────────────────────────────────────
resource "aws_iam_role" "ec2" {
  name = "${var.project}-${var.env}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "s3_access" {
  name = "${var.project}-${var.env}-s3-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecr" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
# SSM Session Manager (alternative to SSH, free)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-${var.env}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ──────────────────────────────────────────────
# Data: Latest Amazon Linux 2023 ARM AMI
# (t4g is ARM/Graviton — cheaper than t2.micro but not free tier)
# For free tier we use x86 t2.micro, so we pick based on var.instance_type
# ──────────────────────────────────────────────
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ──────────────────────────────────────────────
# EBS Volume for persistent data (DB, uploads)
# Separate from root volume so data survives AMI changes
# ──────────────────────────────────────────────
resource "aws_ebs_volume" "data" {
  availability_zone = var.availability_zone
  size              = var.ebs_size_gb
  type              = "gp3"
  encrypted         = true

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-data-volume"
  })
}

# ──────────────────────────────────────────────
# EC2 Instance
# ──────────────────────────────────────────────
resource "aws_instance" "main" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.main.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    project          = var.project
    env              = var.env
    db_password      = var.db_password
    db_name          = var.db_name
    db_user          = var.db_user
    turn_secret      = var.turn_secret
    s3_bucket        = var.s3_bucket_name
    aws_region       = var.aws_region
    nest_api_port    = var.nest_api_port
    domain           = var.domain
    supabase_url     = var.supabase_url
    supabase_key     = var.supabase_key
  })

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-server"
  })

  lifecycle {
    # Prevent accidental termination
    prevent_destroy = false
    ignore_changes  = [ami] # Don't reprovision on AMI updates
  }
}

# Attach data volume
resource "aws_volume_attachment" "data" {
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.data.id
  instance_id  = aws_instance.main.id
  force_detach = false
}

# Elastic IP (free while attached)
resource "aws_eip" "main" {
  instance = aws_instance.main.id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-eip"
  })

  depends_on = [aws_instance.main]
}


resource "null_resource" "upload_configs" {
  depends_on = [aws_volume_attachment.data, aws_eip.main]

  triggers = {
    nginx_hash  = filemd5("${path.module}/configs/nginx.conf")
    coturn_hash = filemd5("${path.module}/configs/turnserver.conf")
    instance_id = aws_instance.main.id
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key_path)
    host        = aws_eip.main.public_ip
    timeout     = "5m"
  }

provisioner "remote-exec" {
  inline = [
    "cloud-init status --wait || true",
    "sudo mkdir -p /opt/rpg-platform",
    "sudo chown ec2-user:ec2-user /opt/rpg-platform",
    "sudo chmod 755 /opt/rpg-platform",
    "ls -la /opt/rpg-platform"  
  ]
}

  provisioner "file" {
    source      = "${path.module}/configs/nginx.conf"
    destination = "/opt/rpg-platform/nginx.conf"
  }

  provisioner "file" {
    source      = "${path.module}/configs/turnserver.conf"
    destination = "/opt/rpg-platform/turnserver.conf"
  }

  provisioner "remote-exec" {
  inline = [
    "cd /opt/rpg-platform && docker exec rpg-platform-nginx-1 nginx -s reload || true"
  ]
}
}



resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "rpg-platform"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "CPU Utilization"
          region  = var.aws_region
          period  = 300
          stat    = "Average"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", aws_instance.main.id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "CPU Credits (t3.small burst)"
          region  = var.aws_region
          period  = 300
          stat    = "Average"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/EC2", "CPUCreditBalance", "InstanceId", aws_instance.main.id],
            ["AWS/EC2", "CPUCreditUsage", "InstanceId", aws_instance.main.id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Memory Used %"
          region  = var.aws_region
          period  = 60
          stat    = "Average"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["RPGPlatform/EC2", "mem_used_percent"]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Disk Used % — /data"
          region  = var.aws_region
          period  = 60
          stat    = "Average"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["RPGPlatform/EC2", "disk_used_percent", "path", "/data", "device", "nvme1n1", "fstype", "xfs"]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          title   = "Network In/Out"
          region  = var.aws_region
          period  = 300
          stat    = "Sum"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", aws_instance.main.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.main.id]
          ]
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 24
        height = 6
        properties = {
          title   = "Backend Errors"
          region  = var.aws_region
          query   = "SOURCE '/rpg-platform/backend' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
          view    = "table"
        }
      }
    ]
  })
}

# CPU credit running low — t3.small will throttle at 0
resource "aws_cloudwatch_metric_alarm" "cpu_credits" {
  alarm_name          = "rpg-cpu-credits-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUCreditBalance"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 20
  alarm_description   = "CPU credits running low — instance will throttle"
  alarm_actions = [aws_sns_topic.alerts.arn]
  dimensions = {
    InstanceId = aws_instance.main.id
  }
}

# Disk space running out on /data
resource "aws_cloudwatch_metric_alarm" "disk_space" {
  alarm_name          = "rpg-disk-space-low"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_used_percent"
  namespace           = "RPGPlatform/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "/data volume over 80% full"
  alarm_actions = [aws_sns_topic.alerts.arn]
  dimensions = {
    path = "/data"
  }
}

# Instance down
resource "aws_cloudwatch_metric_alarm" "instance_health" {
  alarm_name          = "rpg-instance-health"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "EC2 instance health check failed"
  alarm_actions = [aws_sns_topic.alerts.arn]
  dimensions = {
    InstanceId = aws_instance.main.id
  }
}

resource "aws_sns_topic" "alerts" {
  name = "rpg-platform-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "gqueiroz_photo@hotmail.com"
}