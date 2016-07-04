provider "aws" { }

variable "app_name" {}
variable "service_name" {}
variable "app_service_name" {}

resource "aws_subnet" "subnet" {
  count = "${var.az_count}"

  vpc_id = "${data.terraform_remote_state.env.vpc_id}"

  availability_zone = "${element(data.terraform_remote_state.global.az_names,count.index)}"
  cidr_block = "${element(var.cidr_blocks, count.index)}"

  tags {
    "Name" = "${var.context_org}-${var.context_env}-${var.app_service_name}-${element(data.terraform_remote_state.global.az_names,count.index)}"
    "Provisioner" = "tf"
  }

  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_route_table" "rt" {
  vpc_id = "${data.terraform_remote_state.env.vpc_id}"

  tags {
    "Name" = "${var.context_org}-${var.context_env}-${var.app_service_name}-${element(data.terraform_remote_state.global.az_names,count.index)}"
    "Provisioner" = "tf"
  }

  count = "${var.az_count}"
}

resource "aws_route" "nat" {
  route_table_id = "${element(aws_route_table.rt.*.id,count.index)}"
  destination_cidr_block ="0.0.0.0/0"
  nat_gateway_id = "${element(data.terraform_remote_state.nat.nat_ids,count.index)}"

  count = "${var.az_count}"
}

resource "aws_route_table_association" "rt_assoc" {
  count = "${var.az_count}"

  subnet_id = "${element(aws_subnet.subnet.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.rt.*.id,count.index)}"

  count = "${var.az_count}"
}

output "subnet_ids" {
  value = [ "${aws_subnet.subnet.*.id}" ]
}

resource "aws_security_group" "sg" {
  name = "${var.app_service_name}"
  description = "Service ${var.app_service_name}"

  vpc_id = "${data.terraform_remote_state.env.vpc_id}"

  lifecycle {
    create_before_destroy = true
  }

  tags {
    "Name" = "${var.context_org}-${var.context_env}-${var.app_service_name}"
    "App" = "${var.app_name}"
		"Service" = "${var.app_service_name}"
    "Provisioner" = "tf"
  }
}

variable "elb_internal" { default = "true" }

variable "asg_max" { default = 0 }
variable "asg_min" { default = 0 }

variable "lc_image_id" { default = "ami-11286c71" }
variable "lc_instance_type" { default = "m3.medium" }
variable "lc_root_volume_size" { default = "100"}
variable "lc_security_groups" { default = [] }

resource "aws_iam_role" "iam_role" {
  	name = "${var.context_org}-${var.context_env}-${var.app_service_name}"
    path = "/"
    assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {"AWS": "*"},
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_instance_profile" "iam_profile" {
  name = "${aws_iam_role.iam_role.name}"
  roles = ["${aws_iam_role.iam_role.name}"]
}

resource "aws_key_pair" "key_pair" {
  key_name = "${var.context_org}-${var.context_env}-${var.app_service_name}"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQColj57cnyn+68sfzRFU/XrzeJ20mfIkRE+tfdV7uE3IxHmDil7u/XLumkX0//R1hVyIyFgm75e4w6hd6R91sMADFE+Ye7Z0ncZXLYZWF1lMFqp+sAupr8a+1xIsYDFSZRRAa7KwdorfM8hWA3gTIk2p5b7Dn/vovtBJdSOoQPJ0TLDxhIK98/JctAWBvct6S3E68/74Go3qumM7o3npLSjjdlVDp/1Qa60Mkljh8YEKL2CcCtba0DPrpkQ1vJDaZOMEV52SzdyK54XjvvqVH8uQXiBkFpn+V6WcrTWHcCwB1TCPfq0WG2SUKPG1uPNxmMj/pBvaUqt8G2IcyqnSbGx ${var.app_service_name}"
}

resource "aws_launch_configuration" "lc" {
  name_prefix = "${var.context_org}-${var.context_env}-${var.app_service_name}-lc-"

  instance_type = "${var.lc_instance_type}"
  image_id = "${var.lc_image_id}"
  iam_instance_profile = "${aws_iam_instance_profile.iam_profile.name}"
  key_name = "${aws_key_pair.key_pair.key_name}"

  security_groups = [ "${var.lc_security_groups}", "${aws_security_group.sg.id}" ]

  root_block_device {
    volume_type = "gp2"
    volume_size = "${var.lc_root_volume_size}"
  }

  ephemeral_block_device {
    device_name = "/dev/sdb"
    virtual_name = "ephemeral0"
  }
  ephemeral_block_device {
    device_name = "/dev/sdc"
    virtual_name = "ephemeral01"
  }
  ephemeral_block_device {
    device_name = "/dev/sdd"
    virtual_name = "ephemeral2"
  }
  ephemeral_block_device {
    device_name = "/dev/sde"
    virtual_name = "ephemeral3"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elb" "lb" {
  name = "${var.context_org}-${var.context_env}-${var.app_service_name}-elb"

  internal = "${var.elb_internal}"

  listener {
    instance_port = 80
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }

  cross_zone_load_balancing = true

  subnets = [ "${aws_subnet.subnet.*.id}" ]

  tags {
    "App" = "${var.app_name}"
		"Service" = "${var.app_service_name}"
    "Provisioner" = "tf"
  }
}

resource "aws_route53_record" "elb" {
  zone_id = "${data.terraform_remote_state.env.zone_id}"
  name = "${var.app_service_name}"
  type = "ALIAS"
  ttl = 60
  records = [ "${aws_elb.lb.dns_name}" ]
}

output "elb_dns_name" {
  value = "${aws_elb.lb.dns_name}"
}

output "service_dns_name" {
  value = "${aws_route53_record.elb.fqdn}"
}

output "zone_id" {
  value = "${data.terraform_remote_state.env.zone_id}"
}

resource "aws_autoscaling_group" "asg" {
  name = "${var.context_org}-${var.context_env}-${var.app_service_name}-asg"
  launch_configuration = "${aws_launch_configuration.lc.name}"

  availability_zones = [ "${data.terraform_remote_state.global.az_names}" ]
  vpc_zone_identifier = [ "${aws_subnet.subnet.*.id}" ]

  load_balancers = [ "${aws_elb.lb.name}" ]

  max_size = "${var.asg_max}"
  min_size = "${var.asg_min}"
  termination_policies = [ "OldestInstance" ]
  
  tag {
    key = "App" 
    value = "${var.app_name}"
    propagate_at_launch = true
  }
  tag {
    key = "Service" 
    value = "${var.app_service_name}"
    propagate_at_launch = true
  }
  tag {
    key = "Provisioner"
    value = "tf"
    propagate_at_launch = true
  }
  tag {
    key = "Agency"
    value = "asg"
    propagate_at_launch = true
  }
}

resource "aws_sns_topic" "asg_topic" {
  name = "${aws_autoscaling_group.asg.name}-topic"
}

resource "aws_autoscaling_notification" "asg_notice" {
  depends_on = [ "aws_autoscaling_group.asg" ]

  group_names = [
    "${aws_autoscaling_group.asg.name}"
  ]
  notifications  = [
    "autoscaling:EC2_INSTANCE_LAUNCH",
    "autoscaling:EC2_INSTANCE_TERMINATE",
    "autoscaling:EC2_INSTANCE_LAUNCH_ERROR",
    "autoscaling:EC2_INSTANCE_TERMINATE_ERROR"
  ]
  topic_arn = "${aws_sns_topic.asg_topic.arn}"
}

resource "aws_sns_topic_subscription" "asg_sub" {
  topic_arn = "${aws_sns_topic.asg_topic.arn}"
  protocol = "sqs"
  endpoint = "${data.terraform_remote_state.env.asg_arn}"
}

