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
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}