
#vpc

  environment           = "develop-gp2"
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  availability_zones   = ["us-east-1a"]
  create_nat_gateway   = true

#security_group

  environment     = "develop-gp2"
  vpc_id          = module.vpc.vpc_id
  ingress_rules = [
    { from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "Allow SSH" },
    { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "Allow HTTP" },
    { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "Allow HTTPS" }
  ]

  egress_rules = [
    { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"], description = "Allow all outbound traffic" }
  ]
  
  # api_gateway

  environment         = "develop-gp2"
  stage_name          = "dev"
  security_group_id   = module.security_group.security_group_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  alb_arn             = module.alb.alb_arn 

# iam 

  source              = "../../modules/iam"
  environment         = "develop-gp2"

# ecs_cluster

  cluster_name         = "develop-gp2-ecs-cluster"
  ami_id               = "ami-0c55b159cbfafe1f0"  # Update with a valid ECS-optimized AMI
  instance_type        = "t3.medium"
  key_name             = "develop-gp2"
  ebs_volume_size      = 50
  iam_instance_profile = module.iam.ecs_instance_profile
  asg_min_size         = 0
  asg_max_size         = 5
  asg_desired_capacity = 1
  private_subnet_ids   = module.vpc.private_subnet_ids
  security_group_id    = module.security_group.security_group_id
  vpc_id               = module.vpc.vpc_id
 
# ecr_repository_private

  repository_name   = "develop-gp2"
  image_tag_mutability = "MUTABLE"
  encryption_type   = "AES256"
  scan_on_push      = true


# ecs_task

  family              = "develop-gp2-police-task"
  container_name      = "develop-gp2-police-container"
  ecr_repository_url  = module.ecr.repository_url
  execution_role_arn  = module.iam.ecs_task_role_arn
  task_role_arn       = module.iam.ecs_task_role_arn
  cpu                 = 512
  memory              = 1024
  container_port      = 80
  aws_region          = "us-east-1"

  environment_variables = [
    { name = "ENV", value = "development" },
    { name = "SERVICE", value = "police" }
  ]


 #alb

  environment       = "develop-gp2"
  vpc_id            = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  security_group_id = module.security_group.security_group_id
  container_port    = 80


module "cloud_map" {
  source          = "../../modules/cloud-map"
  namespace_name  = module.ecs.cluster_name  # Use the ECS cluster name
  vpc_id          = module.vpc.vpc_id
}


module "ecs_service" {
  source              = "../../modules/ecs-service"
  environment         = "develop-gp2"
  cluster_id          = module.ecs.ecs_cluster_id
  task_definition_arn = module.ecs_task.task_definition_arn
  desired_count       = 2
  private_subnet_ids  = module.vpc.private_subnet_ids
  security_group_id   = module.security_group.security_group_id
  target_group_arn     = module.alb.target_group_arn
  container_name      = "police-container"
  container_port      = 80
}


