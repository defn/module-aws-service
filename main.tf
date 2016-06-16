provider "aws" { }

resource "terraform_remote_state" "global" {
  backend = "s3"
  config {
    bucket = "${var.bucket_remote_state}"
    key = "${var.bucket_remote_state}/env-${var.context_org}-global.tfstate"
  }
}

resource "terraform_remote_state" "env" {
  backend = "s3"
  config {
    bucket = "${var.bucket_remote_state}"
    key = "${var.bucket_remote_state}/env-${var.context_org}-${var.context_env}.tfstate"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id = "${terraform_remote_state.env.vpc_id}"

  count = "${var.az_count}"
  availability_zone = "${element(split(" ",terraform_remote_state.global.az_names), count.index)}"
  cidr_block = "${element(split(" ", var.cidr_blocks), count.index)}"

  tags {
    "Provisioner" = "tf"
  }

  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_route_table" "rt" {
  vpc_id = "${terraform_remote_state.env.vpc_id}"

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
  value = "${join(" ", aws_subnet.subnet.*.id)}"
}
