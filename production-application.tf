// Set teh provider
provider "aws" {
  region = "us-east-1"
  profile = "terraform-user"
}

// Assign all the variables
variable "ExternalElbSGId" {
  default = "sg-0b834fef36203ccc9"
}

variable "DMZSubnetIds" {
  default = [
    "subnet-04e4a2c0a7a625f3c",
    "subnet-0e3c9ee5d0bba879b"]
}

variable "amiId" {
  default = "ami-035be7bafff33b6b6"
}

variable "userDataPath" {
  default = "//home//ernie//TerraformProject1//userdata.txt"
}

variable "MyBucket" {
  default = "ernie-bucket"
}

variable "VPCID" {
  default = "vpc-08e37afc3b2d79e41"
}


data "aws_elb_service_account" "main" {}

data "aws_iam_policy_document" "s3_lb_write" {
    policy_id = "s3_lb_write"

    statement = {
        actions = ["s3:PutObject"]
        resources = ["arn:aws:s3:::<my-bucket>/logs/*"]

        principals = {
            identifiers = ["${data.aws_elb_service_account.main.arn}"]
            type = "AWS"
        }
    }
}

// Create the Application Load Balancer
resource "aws_lb" "productionApplication-AplicationLoadBalancer" {
  name = "Production-ALB--TF"
  internal = false
  load_balancer_type = "application"
  security_groups = [
    "${var.ExternalElbSGId}"]
  subnets = "${var.DMZSubnetIds}"
  enable_deletion_protection = true

//  access_logs {
//    bucket = "${var.MyBucket}"
//    prefix = "logs"
//    enabled = true
//  }
  tags = {
    Environment = "production"
  }
}

// Create the load balancer target group
resource "aws_lb_target_group" "APP-TargGrp--TF" {
  name = "APP-TargGrp--TF"
  port = 80
  protocol = "HTTP"
  vpc_id = "${var.VPCID}"

  health_check {
    interval = "30"
    path = "/"
    protocol = "HTTP"
    healthy_threshold = "2"
    unhealthy_threshold = "5"
    timeout = "28"
    matcher = "200"
  }
}

// Create the load balancer listener
resource "aws_lb_listener" "APP-HTTP-Listener--TF" {
  load_balancer_arn = "${aws_lb.productionApplication-AplicationLoadBalancer.arn}"
  port = "80"
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = "${aws_lb_target_group.APP-TargGrp--TF.arn}"
  }
}


// Create the launch configuration for the laod balancer
resource "aws_launch_configuration" "App_LC--TF" {
  name          = "QA-App_LC--TF"
  image_id      = "${var.amiId}"
  instance_type = "t2.micro"
  iam_instance_profile = "QA-EC2-Role--Dashboard"
  key_name = "udemy-ec2"
  ebs_optimized = "false"
  enable_monitoring = "false"
  security_groups = ["sg-0b873c7f2a3b27a69"]
  user_data = "${file("${var.userDataPath}")}"
}
