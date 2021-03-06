provider "aws" { }

variable "app_name" {}
variable "service_name" {}
variable "app_service_name" {}

resource "aws_subnet" "subnet" {
  count = "${var.nat_count}"

  vpc_id = "${data.terraform_remote_state.env.vpc_id}"

  availability_zone = "${element(data.terraform_remote_state.global.az_names,count.index)}"
  cidr_block = "${element(var.cidr_blocks, count.index)}"

  tags {
    "Name" = "${var.context_org}-${var.context_env}-${var.app_service_name}-${element(data.terraform_remote_state.global.az_names,count.index)}"
    "Provisioner" = "tf"
  }
}

resource "aws_subnet" "pubnet" {
  count = "${var.igw_count}"

  vpc_id = "${data.terraform_remote_state.env.vpc_id}"

  availability_zone = "${element(data.terraform_remote_state.global.az_names,count.index)}"
  cidr_block = "${element(var.cidr_blocks, count.index)}"
  map_public_ip_on_launch = true

  tags {
    "Name" = "${var.context_org}-${var.context_env}-${var.app_service_name}-${element(data.terraform_remote_state.global.az_names,count.index)}"
    "Provisioner" = "tf"
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

  count = "${var.nat_count}"
}

resource "aws_route" "igw" {
  route_table_id = "${element(aws_route_table.rt.*.id,count.index)}"
  destination_cidr_block ="0.0.0.0/0"
  gateway_id = "${data.terraform_remote_state.env.igw}"

  count = "${var.igw_count}"
}

resource "aws_route_table_association" "rt_assoc" {
  count = "${var.az_count}"

  subnet_id = "${element(concat(aws_subnet.subnet.*.id,aws_subnet.pubnet.*.id), count.index)}"
  route_table_id = "${element(aws_route_table.rt.*.id,count.index)}"

  count = "${var.az_count}"
}

output "subnet_ids" {
  value = [ "${concat(aws_subnet.subnet.*.id,aws_subnet.pubnet.*.id)}" ]
}

resource "aws_security_group" "sg" {
  name = "${var.app_service_name}"
  description = "Service ${var.app_service_name}"

  vpc_id = "${data.terraform_remote_state.env.vpc_id}"

  tags {
    "Name" = "${var.context_org}-${var.context_env}-${var.app_service_name}"
    "App" = "${var.app_name}"
		"Service" = "${var.app_service_name}"
    "Provisioner" = "tf"
  }
}

output "sg_id" {
  value = "${aws_security_group.sg.id}"
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
  public_key = "${data.terraform_remote_state.global.public_key}"
}

data "template_cloudinit_config" "config" {
  gzip = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = "#cloud-config\npackage_upgrade: true\npackages: [ntp, curl, unzip, git, perl, ruby, language-pack-en, nfs-common, build-essential, dkms, lvm2, xfsprogs, xfsdump, bridge-utils, linux-generic]\nruncmd: [ reboot ]\n"
  }
}

resource "aws_launch_configuration" "lc" {
  name_prefix = "${var.context_org}-${var.context_env}-${var.app_service_name}-lc-"

  instance_type = "${var.lc_instance_type}"
  image_id = "${var.lc_image_id}"
  iam_instance_profile = "${aws_iam_instance_profile.iam_profile.name}"
  key_name = "${aws_key_pair.key_pair.key_name}"
  user_data = "$date.template_cloudinit_config.config.rendered}"

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

  subnets = [ "${concat(aws_subnet.subnet.*.id,aws_subnet.pubnet.*.id)}" ]

  tags {
    "App" = "${var.app_name}"
		"Service" = "${var.app_service_name}"
    "Provisioner" = "tf"
  }
}

output "instances" {
  value = [ "${aws_elb.lb.instances}" ]
}

resource "aws_route53_record" "elb" {
  zone_id = "${data.terraform_remote_state.env.zone_id}"
  name = "${var.app_service_name}"
  type = "A"

  alias {
    name = "${aws_elb.lb.dns_name}"
    zone_id = "${aws_elb.lb.zone_id}"
    evaluate_target_health = false
  }
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

output "elb_zone_id" {
  value = "${aws_elb.lb.zone_id}"
}

resource "aws_autoscaling_group" "asg" {
  name = "${var.context_org}-${var.context_env}-${var.app_service_name}-asg"
  launch_configuration = "${aws_launch_configuration.lc.name}"

  availability_zones = [ "${data.terraform_remote_state.global.az_names}" ]
  vpc_zone_identifier = [ "${concat(aws_subnet.subnet.*.id,aws_subnet.pubnet.*.id)}" ]

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

