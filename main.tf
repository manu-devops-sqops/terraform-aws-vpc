# Declaration of local variables with values that can be passed in the VPC module
locals {
  azs                   = length(var.availability_zones)
  public_subnets_native = var.public_subnet_enabled ? length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : [for netnum in range(0, local.azs) : cidrsubnet(var.vpc_cidr, 8, netnum)] : []
  secondary_public_subnets = var.public_subnet_enabled && var.secondry_cidr_enabled ? [
    for cidr_block in var.secondary_cidr_blocks : [
      for netnum in range(0, local.azs) : cidrsubnet(cidr_block, 8, netnum)
    ]
  ] : []
  public_subnets       = concat(local.public_subnets_native, flatten(local.secondary_public_subnets))
  intra_subnets_native = var.intra_subnet_enabled ? length(var.intra_subnet_cidrs) > 0 ? var.intra_subnet_cidrs : [for netnum in range(local.azs * 3, local.azs * 4) : cidrsubnet(var.vpc_cidr, 8, netnum)] : []
  secondary_intra_subnets = var.intra_subnet_enabled && var.secondry_cidr_enabled ? [
    for cidr_block in var.secondary_cidr_blocks : [
      for netnum in range(local.azs * 3, local.azs * 4) : cidrsubnet(cidr_block, 8, netnum)
    ]
  ] : []
  intra_subnets          = concat(local.intra_subnets_native, flatten(local.secondary_intra_subnets))
  private_subnets_native = var.private_subnet_enabled ? length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [for netnum in range(local.azs, local.azs * 2) : cidrsubnet(var.vpc_cidr, 4, netnum)] : []
  secondary_private_subnets = var.private_subnet_enabled && var.secondry_cidr_enabled ? [
    for cidr_block in var.secondary_cidr_blocks : [
      for netnum in range(local.azs, local.azs * 2) : cidrsubnet(cidr_block, 4, netnum)
    ]
  ] : []
  private_subnets         = concat(local.private_subnets_native, flatten(local.secondary_private_subnets))
  database_subnets_native = var.database_subnet_enabled ? length(var.database_subnet_cidrs) > 0 ? var.database_subnet_cidrs : [for netnum in range(local.azs * 2, local.azs * 3) : cidrsubnet(var.vpc_cidr, 8, netnum)] : []
  secondary_database_subnets = var.database_subnet_enabled && var.secondry_cidr_enabled ? [
    for cidr_block in var.secondary_cidr_blocks : [
      for netnum in range(local.azs * 2, local.azs * 3) : cidrsubnet(cidr_block, 8, netnum)
    ]
  ] : []
  database_subnets                     = concat(local.database_subnets_native, flatten(local.secondary_database_subnets))
  single_nat_gateway                   = var.one_nat_gateway_per_az == true ? false : true
  create_database_subnet_route_table   = var.database_subnet_enabled
  create_flow_log_cloudwatch_log_group = var.flow_log_enabled == true || var.flow_log_cloudwatch_log_group_skip_destroy == true ? true : false
  is_supported_arch                    = data.aws_ec2_instance_type.arch.supported_architectures[0] == "arm64" ? false : true # for VPN Instance
  nacl_allow_vpc_access_rule = [{
    rule_no    = 97
    action     = "allow"
    from_port  = 0
    to_port    = 0
    protocol   = "-1"
    cidr_block = var.vpc_cidr
    }

  ]
  enable_ipv6                                     = var.ipv6_enabled
  ipv6_only                                       = var.ipv6_enabled && var.ipv6_only ? true : false
  public_subnet_assign_ipv6_address_on_creation   = var.public_subnet_assign_ipv6_address_on_creation == true && var.ipv6_enabled == true ? true : false
  private_subnet_assign_ipv6_address_on_creation  = var.private_subnet_assign_ipv6_address_on_creation == true && var.ipv6_enabled == true ? true : false
  database_subnet_assign_ipv6_address_on_creation = var.database_subnet_assign_ipv6_address_on_creation == true && var.ipv6_enabled == true ? true : false
  intra_subnet_assign_ipv6_address_on_creation    = var.intra_subnet_assign_ipv6_address_on_creation == true && var.ipv6_enabled == true ? true : false

  public_subnet_ipv6_prefixes   = var.public_subnet_enabled ? [for i in range(local.azs) : i] : []
  private_subnet_ipv6_prefixes  = var.private_subnet_enabled ? [for i in range(local.azs) : i + length(data.aws_availability_zones.available.names)] : []
  database_subnet_ipv6_prefixes = var.database_subnet_enabled ? [for i in range(local.azs) : i + 2 * length(data.aws_availability_zones.available.names)] : []
  intra_subnet_ipv6_prefixes    = var.intra_subnet_enabled ? [for i in range(local.azs) : i + 3 * length(data.aws_availability_zones.available.names)] : []
}

# Data source for fetching available AWS availability zones
data "aws_availability_zones" "available" {}
# Data source for fetching information about the VPN sever EC2 instance type
data "aws_ec2_instance_type" "arch" {
  instance_type = var.vpn_server_instance_type
}

# Module block for creating a VPC using terraform-aws-modules/vpc/aws module
module "vpc" {
  source                                          = "terraform-aws-modules/vpc/aws"
  version                                         = "5.19.0"
  name                                            = format("%s-%s-vpc", var.environment, var.name)
  cidr                                            = var.vpc_cidr # CIDR FOR VPC
  azs                                             = var.availability_zones
  use_ipam_pool                                   = var.ipam_enabled ? true : false
  ipv4_ipam_pool_id                               = var.ipam_enabled && var.create_ipam_pool ? aws_vpc_ipam_pool.ipam_pool[0].id : null
  ipv4_netmask_length                             = var.ipam_enabled ? var.ipv4_netmask_length : null
  create_database_subnet_group                    = length(local.database_subnets) > 1 && var.enable_database_subnet_group ? true : false
  intra_subnets                                   = local.intra_subnets
  public_subnets                                  = local.public_subnets
  private_subnets                                 = local.private_subnets
  database_subnets                                = local.database_subnets
  enable_flow_log                                 = var.flow_log_enabled
  enable_nat_gateway                              = length(local.private_subnets) > 0 && !var.ipv6_only ? true : false
  single_nat_gateway                              = local.single_nat_gateway
  enable_vpn_gateway                              = false
  enable_dns_hostnames                            = true
  flow_log_traffic_type                           = "ALL"
  secondary_cidr_blocks                           = var.secondry_cidr_enabled ? var.secondary_cidr_blocks : []
  one_nat_gateway_per_az                          = var.one_nat_gateway_per_az
  map_public_ip_on_launch                         = var.auto_assign_public_ip
  flow_log_destination_type                       = "cloud-watch-logs"
  manage_default_network_acl                      = true
  default_network_acl_ingress                     = concat(local.nacl_allow_vpc_access_rule, var.default_network_acl_ingress)
  manage_default_security_group                   = true
  default_security_group_ingress                  = [] # Enforcing no rules being present in the default security group.
  default_security_group_egress                   = []
  create_database_nat_gateway_route               = false
  create_database_subnet_route_table              = local.create_database_subnet_route_table
  create_flow_log_cloudwatch_iam_role             = var.flow_log_enabled
  create_flow_log_cloudwatch_log_group            = local.create_flow_log_cloudwatch_log_group
  flow_log_max_aggregation_interval               = var.flow_log_max_aggregation_interval
  flow_log_cloudwatch_log_group_skip_destroy      = var.flow_log_cloudwatch_log_group_skip_destroy
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_cloudwatch_log_group_retention_in_days
  flow_log_cloudwatch_log_group_kms_key_id        = var.flow_log_cloudwatch_log_group_kms_key_arn
  enable_ipv6                                     = local.enable_ipv6
  public_subnet_ipv6_native                       = local.ipv6_only
  private_subnet_ipv6_native                      = local.ipv6_only
  database_subnet_ipv6_native                     = local.ipv6_only
  intra_subnet_ipv6_native                        = local.ipv6_only
  #assign_ipv6_address_on_creation = local.assign_ipv6_address_on_creation
  public_subnet_assign_ipv6_address_on_creation   = local.public_subnet_assign_ipv6_address_on_creation
  private_subnet_assign_ipv6_address_on_creation  = local.private_subnet_assign_ipv6_address_on_creation
  database_subnet_assign_ipv6_address_on_creation = local.database_subnet_assign_ipv6_address_on_creation
  intra_subnet_assign_ipv6_address_on_creation    = local.intra_subnet_assign_ipv6_address_on_creation
  public_subnet_ipv6_prefixes                     = local.public_subnet_ipv6_prefixes
  private_subnet_ipv6_prefixes                    = local.private_subnet_ipv6_prefixes
  database_subnet_ipv6_prefixes                   = local.database_subnet_ipv6_prefixes
  intra_subnet_ipv6_prefixes                      = local.intra_subnet_ipv6_prefixes


  # TAGS TO BE ASSOCIATED WITH EACH RESOURCE

  tags = tomap(
    {
      "Name"        = format("%s-%s-vpc", var.environment, var.name)
      "Environment" = var.environment
    },
  )

  public_subnet_tags = tomap({
    "Name"                   = "${var.environment}-${var.name}-public-subnet"
    "Subnet-group"           = "public"
    "kubernetes.io/role/elb" = 1
  })

  public_route_table_tags = tomap({
    "Name" = "${var.environment}-${var.name}-public-route-table"
  })

  private_subnet_tags = tomap({
    "Name"                            = "${var.environment}-${var.name}-private-subnet"
    "Subnet-group"                    = "private"
    "kubernetes.io/role/internal-elb" = 1
  })

  private_subnet_tags_per_az = { for az in var.availability_zones : az => {
    "Karpenter" = "${var.name}-${az}"
  } }

  private_route_table_tags = tomap({
    "Name" = "${var.environment}-${var.name}-private-route-table"
  })

  database_subnet_tags = tomap({
    "Name"         = "${var.environment}-${var.name}-database-subnet"
    "Subnet-group" = "database"
  })

  database_route_table_tags = tomap({
    "Name" = "${var.environment}-${var.name}-database-route-table"
  })

  intra_subnet_tags = tomap({
    "Name"         = "${var.environment}-${var.name}-intra-subnet"
    "Subnet-group" = "intra"
  })

  intra_route_table_tags = tomap({
    "Name" = "${var.environment}-${var.name}-intra-route-table"
  })

  igw_tags = tomap({
    "Name" = "${var.environment}-${var.name}-igw"
  })

  nat_gateway_tags = tomap({
    "Name" = "${var.environment}-${var.name}-nat"
  })

  default_network_acl_name = format("%s-%s-nacl", var.environment, var.name)
  default_network_acl_tags = {
    "Name"        = format("%s-%s-nacl", var.environment, var.name)
    "Environment" = var.environment
  }
}

# Module block for creating a VPN server
module "vpn_server" {
  count                    = var.vpn_server_enabled && local.is_supported_arch ? 1 : 0
  depends_on               = [module.vpc]
  source                   = "./modules/vpn"
  name                     = var.name
  vpc_id                   = module.vpc.vpc_id
  vpc_cidr                 = var.vpc_cidr
  environment              = var.environment
  vpn_key_pair             = var.vpn_key_pair_name
  public_subnet            = module.vpc.public_subnets[0]
  vpn_server_instance_type = var.vpn_server_instance_type
  kms_key_arn              = var.kms_key_arn
}

# Define an AWS VPC IP Address Management (IPAM) resource
resource "aws_vpc_ipam" "ipam" {
  count = var.ipam_enabled && var.create_ipam_pool ? 1 : 0
  operating_regions {
    region_name = var.region
  }


}

# Define an AWS VPC IP Address Management (IPAM) pool resource
resource "aws_vpc_ipam_pool" "ipam_pool" {
  count                             = var.ipam_enabled && var.create_ipam_pool ? 1 : 0
  description                       = "IPv4 pool"
  address_family                    = "ipv4"
  ipam_scope_id                     = aws_vpc_ipam.ipam[0].private_default_scope_id
  locale                            = var.region
  allocation_default_netmask_length = 16
}

# Define an AWS VPC IP Address Management (IPAM) pool CIDR resource
resource "aws_vpc_ipam_pool_cidr" "ipam_pool_cidr" {
  count        = var.ipam_enabled ? 1 : 0
  ipam_pool_id = var.create_ipam_pool ? aws_vpc_ipam_pool.ipam_pool[0].id : var.ipam_pool_id
  cidr         = var.create_ipam_pool ? var.vpc_cidr : var.existing_ipam_managed_cidr
}

# Define a data source to fetch AWS Route Tables for private routes
data "aws_route_tables" "aws_private_routes" {
  count      = var.vpc_s3_endpoint_enabled ? 1 : 0
  depends_on = [module.vpc]
  vpc_id     = module.vpc.vpc_id
  tags = {
    Name = "${var.environment}-${var.name}-private-route-table"
  }
}

# Define an AWS VPC endpoint for S3
resource "aws_vpc_endpoint" "private-s3" {
  count             = var.vpc_s3_endpoint_enabled ? 1 : 0
  depends_on        = [data.aws_route_tables.aws_private_routes]
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  route_table_ids   = data.aws_route_tables.aws_private_routes[0].ids
  vpc_endpoint_type = "Gateway"
  policy            = <<POLICY
{
    "Statement": [
        {
            "Action": "*",
            "Effect": "Allow",
            "Resource": "*",
            "Principal": "*"
        }
    ]
}
POLICY
  tags = {
    Name = "${var.environment}-${var.name}-endpoint"
  }
}

# Allow access  to ECR repo at port 443
resource "aws_security_group" "vpc_endpoints" {
  count       = var.vpc_ecr_endpoint_enabled ? 1 : 0
  name_prefix = "${var.environment}-vpc-endpoints"
  description = "Associated to ECR/s3 VPC Endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow Nodes to pull images from ECR via VPC endpoints"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = [var.vpc_cidr]
  }
}

# private links for ECR.dkr
resource "aws_vpc_endpoint" "private-ecr-dkr" {
  count               = var.vpc_ecr_endpoint_enabled ? 1 : 0
  depends_on          = [data.aws_route_tables.aws_private_routes]
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.ecr.dkr"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  policy              = <<POLICY
{
    "Statement": [
        {
            "Action": "*",
            "Effect": "Allow",
            "Resource": "*",
            "Principal": "*"
        }
    ]
}
POLICY
  tags = {
    Name = "${var.environment}-${var.name}-ecr-dkr-endpoint"
  }
}

# private links for ECR.api

resource "aws_vpc_endpoint" "private-ecr-api" {
  count               = var.vpc_ecr_endpoint_enabled ? 1 : 0
  depends_on          = [data.aws_route_tables.aws_private_routes]
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnets
  service_name        = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  policy              = <<POLICY
{
    "Statement": [
        {
            "Action": "ecr.api",
            "Effect": "Allow",
            "Resource": "*",
            "Principal": "*"
        }
    ]
}
POLICY
  tags = {
    Name = "${var.environment}-${var.name}-ecr-api-endpoint"
  }
}
