
# VPC
# resource "aws_vpc" "example_vpc" {
#   cidr_block = "10.0.0.0/16"
  
# }

# Subnets
# resource "aws_subnet" "example_subnet" {
#   count             = 2
#   vpc_id            = aws_vpc.example_vpc.id
#   cidr_block        = "10.0.${count.index}.0/24"
#   availability_zone = element(data.aws_availability_zones.available.names, count.index)
#   map_public_ip_on_launch = true

# }

data "aws_availability_zones" "available" {}

# Internet Gateway
# resource "aws_internet_gateway" "example_igw" {
#   vpc_id = aws_vpc.example_vpc.id
# }

# Route Table
# resource "aws_route_table" "example_route_table" {
#   vpc_id = aws_vpc.example_vpc.id

#   route {
#     cidr_block = "0.0.0.0/0"
#     gateway_id = aws_internet_gateway.example_igw.id
#   }
# }

# Route Table Association
# resource "aws_route_table_association" "example_association" {
#   count     = 2
#   subnet_id = element(aws_subnet.example_subnet.*.id, count.index)
#   route_table_id = aws_route_table.example_route_table.id
# }

# Security Group
resource "aws_security_group" "example_sg" {
  vpc_id = "vpc-03d964f7cd3fa2c74"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB
resource "aws_lb" "example_alb" {
  name               = "example-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.example_sg.id]
  subnets            = ["subnet-example1_id","subnet-example2_id","subnet-example3_id"]
}

# ALB Target Group
resource "aws_lb_target_group" "example_tg" {
  name     = "example-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = "vpc-example_id"

health_check {
  enabled             = true
  interval            = 5
  path                = "/"
  port                = 80
  healthy_threshold   = 2
  unhealthy_threshold = 3
  timeout             = 2
  protocol            = "HTTP"
  matcher             = "200-399"
}
}

# ALB Listener
resource "aws_lb_listener" "example_listener" {
  load_balancer_arn = aws_lb.example_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example_tg.arn
  }
}

# Launch Template
resource "aws_launch_template" "example_lt" {
  name_prefix   = "example-lt"
  image_id      = "ami-0182f373e66f89c85" # Replace with your desired AMI ID
  instance_type = "t2.micro"
  iam_instance_profile {
    name = "demo-ec2-cicd"
  }
  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y nginx
              systemctl start nginx
              systemctl enable nginx
              EOF
  )
  network_interfaces {
    associate_public_ip_address = true
    security_groups = [aws_security_group.example_sg.id]
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "example_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 0
  vpc_zone_identifier  = ["subnet-","subnet-","subnet-"]
  launch_template {
    id      = aws_launch_template.example_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.example_tg.arn]
  
  tag {
    key                 = "Name"
    value               = "example-asg"
    propagate_at_launch = true
  }
}

# Auto Scaling Policy
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale_up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.example_asg.name
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale_down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.example_asg.name
}

###################
# S3 Bucket
resource "aws_s3_bucket" "mybucket" {
  #checkov:skip=CKV_AWS_144: "Ensure that S3 bucket has cross-region replication enabled"
  bucket = "example-cicd-demo"
}

# Enable Versioning
resource "aws_s3_bucket_versioning" "versioning_example" {
  bucket = aws_s3_bucket.mybucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable Server-Side Encryption
resource "aws_kms_key" "mykey" {
  #checkov:skip=CKV2_AWS_64: "Ensure KMS key Policy is defined"
  description             = "This key is used to encrypt bucket objects"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = aws_s3_bucket.mybucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.mykey.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Public Access Block
resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.mybucket.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Bucket Lifecycle Configuration
resource "aws_s3_bucket_lifecycle_configuration" "example" {
  bucket = aws_s3_bucket.mybucket.id

  rule {
    id     = "abortIncompleteMultipartUploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expireObjects"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

# Bucket Logging
resource "aws_s3_bucket_logging" "example" {
  bucket        = aws_s3_bucket.mybucket.id
  target_bucket = aws_s3_bucket.mybucket.id
  target_prefix = "build-log/"
}

# Event Notifications - Example: S3 to SQS (Requires configuring an SQS queue)
resource "aws_s3_bucket_notification" "example" {
  bucket = aws_s3_bucket.mybucket.id

}

# Data block to reference an existing SNS topic
data "aws_sns_topic" "codestar_notifications" {
  name = "codestar-notifications"
}
