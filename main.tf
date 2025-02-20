provider "aws" {
  region = "us-east-1"  # Cambia según tu región
}

# ✅ VPC
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "main-vpc" }
}

# ✅ Subnet pública (EC2 con acceso a Internet)
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = { Name = "public-subnet" }
}

# ✅ Subnets privadas para RDS (Alta disponibilidad)
resource "aws_subnet" "private_subnet_1" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.5.0/24" # CIDR cambiado a 10.0.5.0/24
  map_public_ip_on_launch = false
  availability_zone       = "us-east-1a"
  tags = { Name = "private-subnet-1" }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.4.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "us-east-1b"
  tags = { Name = "private-subnet-2" }
}

# ✅ Internet Gateway para acceso externo
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main_vpc.id
  tags   = { Name = "main-igw" }
}

# ✅ Route Table para Internet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  tags   = { Name = "public-route-table" }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ✅ Grupo de Seguridad para EC2
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.main_vpc.id
  tags   = { Name = "ec2-security-group" }
}

resource "aws_security_group_rule" "allow_ssh" {
  security_group_id = aws_security_group.ec2_sg.id
  type             = "ingress"
  from_port        = 22
  to_port          = 22
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]  # Restringe en producción
}
resource "aws_security_group_rule" "allow_http_outbound" {
  type             = "egress"
  security_group_id = aws_security_group.ec2_sg.id
  from_port        = 80
  to_port          = 80
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "allow_https_outbound" {
  type             = "egress"
  security_group_id = aws_security_group.ec2_sg.id
  from_port        = 443
  to_port          = 443
  protocol         = "tcp"
  cidr_blocks      = ["0.0.0.0/0"]
}
# ✅ Grupo de Seguridad para RDS
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.main_vpc.id
  tags   = { Name = "rds-security-group" }
}

resource "aws_security_group_rule" "allow_rds_from_ec2" {
  security_group_id        = aws_security_group.rds_sg.id
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ec2_sg.id
}

# ✅ Instancia EC2
resource "aws_instance" "inventory_instance" {
  ami                    = "ami-053a45fff0a704a47"  # AMI compatible con x86_64
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true

  tags = { Name = "inventory-ec2" }
}

# ✅ RDS PostgreSQL (Alta Disponibilidad)
resource "aws_db_instance" "inventory_db" {
  allocated_storage      = 20
  engine                = "postgres"
  engine_version        = "15.7"
  instance_class        = "db.t3.micro"
  identifier            = "inventory-db"
  username              = "CCPDB"
  password              = "projectccp2025"
  publicly_accessible   = false
  db_subnet_group_name  = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot = true

  tags = { Name = "inventory-rds" }
}

# ✅ Subnet Group para RDS
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  tags       = { Name = "rds-subnet-group" }
}

# ✅ Cola SQS
resource "aws_sqs_queue" "inventory_queue" {
  name                        = "inventory-queue"
  visibility_timeout_seconds  = 30
}

# ✅ IAM Role para acceso de EC2 a SQS
resource "aws_iam_role" "ec2_sqs_role" {
  name = "EC2SQSRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "sqs_access_policy" {
  name = "SQSAccessPolicy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sqs:SendMessage", "sqs:ReceiveMessage"]
      Resource  = aws_sqs_queue.inventory_queue.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_sqs_attach" {
  role       = aws_iam_role.ec2_sqs_role.name
  policy_arn = aws_iam_policy.sqs_access_policy.arn
}



