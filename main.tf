provider "aws" { }

data "terraform_remote_state" "global" {
  backend = "s3"
  config {
    bucket = "${var.bucket_remote_state}"
    key = "${var.bucket_remote_state}/env-${var.context_org}-global.tfstate"
  }
}

data "terraform_remote_state" "env" {
  backend = "s3"
  config {
    bucket = "${var.bucket_remote_state}"
    key = "${var.bucket_remote_state}/env-${var.context_org}-${var.context_env}.tfstate"
  }
}

variable "az_count" { }

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
