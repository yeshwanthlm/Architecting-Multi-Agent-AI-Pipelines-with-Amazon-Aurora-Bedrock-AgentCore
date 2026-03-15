##############################################################################
# VPC
##############################################################################

resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  instance_tenancy     = "default"

  tags = merge(local.common_tags, {
    Name = "electrify-vpc-${local.region}-${local.suffix}"
  })
}

##############################################################################
# Internet Gateway
##############################################################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "electrify-igw-${local.region}-${local.suffix}"
  })
}

##############################################################################
# Public Subnets
##############################################################################

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.sub_pub1_cidr
  availability_zone       = local.az1
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "electrify-pub-sub-1-${local.region}-${local.suffix}"
  })
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.sub_pub2_cidr
  availability_zone       = local.az2
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "electrify-pub-sub-2-${local.region}-${local.suffix}"
  })
}

resource "aws_subnet" "public_3" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.sub_pub3_cidr
  availability_zone       = local.az3
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "electrify-pub-sub-3-${local.region}-${local.suffix}"
  })
}

##############################################################################
# Private Subnets
##############################################################################

resource "aws_subnet" "private_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.sub_prv1_cidr
  availability_zone       = local.az1
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "electrify-prv-sub-1-${local.region}-${local.suffix}"
  })
}

resource "aws_subnet" "private_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.sub_prv2_cidr
  availability_zone       = local.az2
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "electrify-prv-sub-2-${local.region}-${local.suffix}"
  })
}

resource "aws_subnet" "private_3" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.sub_prv3_cidr
  availability_zone       = local.az3
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "electrify-prv-sub-3-${local.region}-${local.suffix}"
  })
}

##############################################################################
# Public Route Table
##############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "electrify-public-rtb-${local.region}-${local.suffix}"
  })
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_3" {
  subnet_id      = aws_subnet.public_3.id
  route_table_id = aws_route_table.public.id
}

##############################################################################
# NAT Gateway
##############################################################################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "electrify-nat-eip-${local.region}-${local.suffix}"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_2.id

  tags = merge(local.common_tags, {
    Name = "electrify-ngw-${local.region}-${local.suffix}"
  })

  depends_on = [aws_internet_gateway.main]
}

##############################################################################
# Private (NAT) Route Table
##############################################################################

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "electrify-nat-rtb-${local.region}-${local.suffix}"
  })
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_3" {
  subnet_id      = aws_subnet.private_3.id
  route_table_id = aws_route_table.private.id
}

##############################################################################
# VPC S3 Gateway Endpoint
##############################################################################

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.public.id,
    aws_route_table.private.id,
  ]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Principal = "*"
      Effect    = "Allow"
      Action    = "s3:*"
      Resource  = ["arn:aws:s3:::*", "arn:aws:s3:::*/*"]
    }]
  })

  tags = merge(local.common_tags, {
    Name = "electrify-s3-endpoint-${local.region}-${local.suffix}"
  })
}
