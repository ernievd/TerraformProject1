// Set the provider
provider "aws" {
  region = "us-east-1"
  profile = "terraform-user"
}

/////////// Assign all the variables ////////////
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

variable "AsgAZs" {
  default = ["us-east-1a", "us-east-1b"]
}

variable "PublicSubnetIDs" {
  default = ["subnet-00b555b304d0a23ce", "subnet-01361c439ca4a48dd"]
}

variable "autoscaling_notification_arn" {
  default = "arn:aws:sns:us-east-1:499000881936:AutoScaling-Activity-Dashboard"
}

////////// End of Variables /////////////////

data "aws_elb_service_account" "main" {}

data "aws_iam_policy_document" "s3_lb_write" {
    policy_id = "s3_lb_write"

    statement = {
        actions             = ["s3:PutObject"]
        resources           = ["arn:aws:s3:::<my-bucket>/logs/*"]

        principals = {
            identifiers      = ["${data.aws_elb_service_account.main.arn}"]
            type = "AWS"
        }
    }
}

// Create the Application Load Balancer
resource "aws_lb" "productionApplication-AplicationLoadBalancer" {
  name                      = "Production-ALB--TF"
  internal                  = false
  load_balancer_type        = "application"
  security_groups           = ["${var.ExternalElbSGId}"]
  subnets                   = "${var.DMZSubnetIds}"
  enable_deletion_protection = false

//  access_logs {
//    bucket = "${var.MyBucket}"
//    prefix = "logs"
//    enabled = true
//  }
  tags = {
    Environment             = "production"
  }
}

// Create the load balancer target group
resource "aws_lb_target_group" "APP-TargGrp--TF" {
  name                      = "APP-TargGrp--TF"
  port                      = 80
  protocol                  = "HTTP"
  vpc_id                    = "${var.VPCID}"

  health_check {
    interval                = "30"
    path                    = "/"
    protocol                = "HTTP"
    healthy_threshold       = "2"
    unhealthy_threshold     = "5"
    timeout                 = "28"
    matcher                 = "200"
  }
}

// Create the load balancer listener
resource "aws_lb_listener" "APP-HTTP-Listener--TF" {
  load_balancer_arn         = "${aws_lb.productionApplication-AplicationLoadBalancer.arn}"
  port                      = "80"
  protocol                  = "HTTP"

  default_action {
    type                    = "forward"
    target_group_arn        = "${aws_lb_target_group.APP-TargGrp--TF.arn}"
  }
}

// Create the launch configuration for the load balancer
resource "aws_launch_configuration" "App_LC--TF" {
  name                      = "QA-App_LC--TF"
  image_id                  = "${var.amiId}"
  instance_type             = "t2.micro"
  iam_instance_profile      = "QA-EC2-Role--Dashboard"
  key_name                  = "udemy-ec2"
  ebs_optimized             = "false"
  enable_monitoring         = "false"
  security_groups           = ["sg-0b873c7f2a3b27a69"]
  user_data                 = "${file("${var.userDataPath}")}"

}

// Create the autoscaling group
resource "aws_autoscaling_group" "QA-Prod-autoscale-grp" {
  availability_zones = ["us-east-1a", "us-east-1b"]
  name                      = "QA-Prod-autoscale-grp--TF"
  max_size                  = 4
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 2
  launch_configuration      = "${aws_launch_configuration.App_LC--TF.name}"
  target_group_arns         = ["${aws_lb_target_group.APP-TargGrp--TF.arn}"]
  termination_policies      = ["OldestInstance"]
  vpc_zone_identifier       = "${var.PublicSubnetIDs}"
  tag {
    key                 = "Environment"
    value               = "Production"
    propagate_at_launch = true
  }
    tag {
    key = "Name"
    value = "QA_ASG--TF"
      propagate_at_launch = true
  }
}

// Create the notification
resource "aws_autoscaling_notification" "asg_activity_notification" {
  group_names = [
    "${aws_autoscaling_group.QA-Prod-autoscale-grp.name}"
  ]

  notifications = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"
  ]

  topic_arn = "${var.autoscaling_notification_arn}"
}

// Create the High CPU alarm
resource "aws_cloudwatch_metric_alarm" "High_Cpu_Alarm" {
  alarm_name = "App_High_Cpu_Alarm--TF"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "5"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "60"
  statistic = "Average"
  threshold = "80"
  alarm_description = "This metric monitors ec2 cpu utilization"
  alarm_actions          = ["${aws_autoscaling_policy.app_scaleup_policy.arn}"]
  dimensions = {
    AutoScalingGroupName = "${aws_autoscaling_group.QA-Prod-autoscale-grp.name}"
  }
}

// Create the autoscaling up policy
resource "aws_autoscaling_policy" "app_scaleup_policy" {
  name                   = "app_scaleup_policy--TF"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = "${aws_autoscaling_group.QA-Prod-autoscale-grp.name}"
}

// Create the Low CPU alarm
resource "aws_cloudwatch_metric_alarm" "Low_Cpu_Alarm" {
  alarm_name            = "App_Low_Cpu_Alarm--TF"
  comparison_operator   = "LessThanOrEqualToThreshold"
  evaluation_periods    = "5"
  metric_name           = "CPUUtilization"
  namespace             = "AWS/EC2"
  period                = "60"
  statistic             = "Average"
  threshold             = "30"
  alarm_description     = "This metric monitors ec2 cpu utilization"
  alarm_actions         = ["${aws_autoscaling_policy.app_scaledown_policy.arn}"]
  dimensions            = {
      AutoScalingGroupName = "${aws_autoscaling_group.QA-Prod-autoscale-grp.name}"
  }
}

// Create the autoscaling down policy
resource "aws_autoscaling_policy" "app_scaledown_policy" {
  name                   = "app_scaledown_policy--TF"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = "${aws_autoscaling_group.QA-Prod-autoscale-grp.name}"
}
