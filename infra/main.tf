terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

resource "tls_private_key" "okd_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.okd_ssh.private_key_pem
  filename        = "${path.module}/okd-key.pem"
  file_permission = "0600"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "okd-vpc"
  cidr = "10.0.0.0/16"

  azs            = ["eu-north-1a"]
  public_subnets = ["10.0.1.0/24"]
  
  enable_nat_gateway = false
  enable_vpn_gateway = false
}

module "security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  name   = "okd-sg"
  vpc_id = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["https-443-tcp", "http-80-tcp", "ssh-tcp", "all-icmp"]
  ingress_with_cidr_blocks = [
    {
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 22623
      to_port     = 22623
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 30000
      to_port     = 32767
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
  
  egress_rules = ["all-all"]
}

module "key_pair" {
  source  = "terraform-aws-modules/key-pair/aws"
  version = "2.0.2"

  key_name   = "okd-key"
  public_key = tls_private_key.okd_ssh.public_key_openssh
}

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.6.0"

  name = "okd-single-node"

  instance_type          = "m5.xlarge"
  key_name               = module.key_pair.key_pair_name
  vpc_security_group_ids = [module.security_group.security_group_id]
  subnet_id              = module.vpc.public_subnets[0]
  
  ami = data.aws_ami.rhcos.id
  
  root_block_device = [
    {
      volume_type = "gp3"
      volume_size = 80
    }
  ]

  associate_public_ip_address = true
  
  user_data = templatefile("${path.module}/install-okd.sh", {
    ssh_key = tls_private_key.okd_ssh.public_key_openssh
  })
}

data "aws_ami" "rhcos" {
  most_recent = true
  owners      = ["125523088429"]

  filter {
    name   = "name"
    values = ["fedora-coreos-*-x86_64"]
  }
}

resource "null_resource" "get_kubeconfig" {
  depends_on = [module.ec2_instance]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for OKD installation to complete (45 mins)..."
      sleep 2700
      scp -o StrictHostKeyChecking=no -i ${local_file.private_key.filename} core@${module.ec2_instance.public_ip}:/home/core/okd-install/auth/kubeconfig ./kubeconfig
      echo "Kubeconfig downloaded to ./kubeconfig"
      echo "Run: export KUBECONFIG=./kubeconfig"
    EOT
  }
}

output "instance_ip" {
  value = module.ec2_instance.public_ip
}

output "ssh_command" {
  value = "ssh -i okd-key.pem core@${module.ec2_instance.public_ip}"
}

output "kubeconfig_command" {
  value = "export KUBECONFIG=./kubeconfig"
}
