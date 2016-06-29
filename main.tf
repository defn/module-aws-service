provider "aws" { }

variable "az_count" {}
variable "app_name" {}
variable "service_name" {}

resource "aws_subnet" "subnet" {
  count = "${var.az_count}"

  vpc_id = "${data.terraform_remote_state.env.vpc_id}"

  availability_zone = "${element(data.terraform_remote_state.global.az_names,count.index)}"
  cidr_block = "${element(var.cidr_blocks, count.index)}"

  tags {
    "Provisioner" = "tf"
  }

  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_route_table" "rt" {
  vpc_id = "${data.terraform_remote_state.env.vpc_id}"

  tags {
    "Provisioner" = "tf"
  }
}

resource "aws_route_table_association" "rt_assoc" {
  count = "${var.az_count}"

  subnet_id = "${element(aws_subnet.subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.rt.id}"
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
}
