module "vpc" {
  source = "github.com/santhoshm-rapyder/terraform-aws-vpc-module.git?ref=main" # Replace "main" with the required branch or tag

  environment           = "develop-gp2"
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  availability_zones   = ["ap-south-1a"]
  create_nat_gateway   = true
}


module "security_group" {
  source          = "github.com/santhoshm-rapyder/terraform-aws-sg-module.git?ref=main"
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
  
}


# # ✅ SonarQube EC2 Instance
module "sonarqube_instance" {
  source            = "github.com/santhoshm-rapyder/terraform-aws-ec2-module.git?ref=main"
  ami_id            = "ami-0c94855ba95c71c99" # Amazon Linux 2 AMI
  instance_type     = "t2.medium"
  key_name          = "ec2-sonar-instance"
  security_group_id = module.security_group.security_group_id
}



module "api_gateway" {
  source              = "../../modules/api-gateway"
  environment         = "develop-gp2"
  stage_name          = "dev"
  security_group_id   = module.security_group.security_group_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  alb_arn             = module.alb.alb_arn 
}

module "iam" {
  source              = "../../modules/iam"
  environment         = "develop-gp2"
}

module "keypair" {
  source   = "github.com/santhoshm-rapyder/terraform-aws-keypair-module.git?ref=main"
  key_name = "develop-gp2"
}


module "ecs" {
  source               = "github.com/santhoshm-rapyder/terraform-aws-ecs-module.git?ref=main"
  cluster_name         = "develop-gp2-ecs-cluster"
  ami_id               = "ami-0c55b159cbfafe1f0"  # Update with a valid ECS-optimized AMI
  instance_type        = "t3.medium"
  key_name             = module.keypair.key_name
  ebs_volume_size      = 50
  iam_instance_profile = module.iam.ecs_instance_profile
  asg_min_size         = 0
  asg_max_size         = 5
  asg_desired_capacity = 1
  private_subnet_ids   = module.vpc.private_subnet_ids
  security_group_id    = module.security_group.security_group_id
  vpc_id               = module.vpc.vpc_id
 
}


module "ecr" {
  source            = "../../modules/ecr"
  repository_names    = ["configs", "documents", "gateway", "identity", "payment", "workspace", "marketing", "tenant", "webhook", "permitio"]
  image_tag_mutability = "MUTABLE"
  encryption_type   = "AES256"
  scan_on_push      = true
}


module "alb" {
  source            = "../../modules/alb"
  environment       = "develop-gp2"
  vpc_id            = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids = module.vpc.public_subnet_ids
  security_group_id = module.security_group.security_group_id
  container_port    = 80
  health_check_path  = "/health"

  gateway_target_group_arn         = module.alb.gateway_target_group_arn
  marketing_target_group_arn       = module.alb.marketing_target_group_arn
  webhook_target_group_arn         = module.alb.webhook_target_group_arn
  permitio_target_group_arn        = module.alb.permitio_target_group_arn
  frontend_tenant_target_group_arn = module.alb.frontend_tenant_target_group_arn

}


module "cloud_map" {
  source          = "../../modules/cloud-map"
  namespace_name  = module.ecs.cluster_name 
  vpc_id          = module.vpc.vpc_id
}

module "ecs_task_configs" {
  source              = "../../modules/ecs-task"
  family              = "develop-gp2-configs-task"
  container_name      = "develop-gp2-configs-container"
  ecr_repository_url  = module.ecr.repository_urls["configs"]
  execution_role_arn  = module.iam.ecs_task_role_arn
  task_role_arn       = module.iam.ecs_task_role_arn
  cpu                 = 512
  memory              = 1024
  container_port      = 5004
  aws_region          = "ap-south-1"
  network_mode        = "awsvpc"
  environment_variables = [
    { name = "ENV", value = "development" },
    { name = "SERVICE", value = "configs" }
  ]
}

module "ecs_task_documents" {
  source              = "../../modules/ecs-task"
  family              = "develop-gp2-documents-task"
  container_name      = "develop-gp2-documents-container"
  ecr_repository_url  = module.ecr.repository_urls["documents"]
  execution_role_arn  = module.iam.ecs_task_role_arn
  task_role_arn       = module.iam.ecs_task_role_arn
  cpu                 = 512
  memory              = 1024
  container_port      = 5008
  aws_region          = "ap-south-1"
  network_mode        = "awsvpc"
  environment_variables = [
    { name = "ENV", value = "development" },
    { name = "SERVICE", value = "documents" }
  ]
}

module "ecs_task_gateway" {
  source              = "../../modules/ecs-task"
  family              = "develop-gp2-gateway-task"
  container_name      = "develop-gp2-gateway-container"
  ecr_repository_url  = module.ecr.repository_urls["gateway"]
  execution_role_arn  = module.iam.ecs_task_role_arn
  task_role_arn       = module.iam.ecs_task_role_arn
  cpu                 = 512
  memory              = 1024
  container_port      = 5000
  aws_region          = "ap-south-1"
  network_mode        = "awsvpc"
  environment_variables = [
    { name = "ENV", value = "development" },
    { name = "SERVICE", value = "gateway" }
  ]
}

module "ecs_task_identity" {
  source              = "../../modules/ecs-task"
  family              = "develop-gp2-identity-task"
  container_name      = "develop-gp2-identity-container"
  ecr_repository_url  = module.ecr.repository_urls["identity"]
  execution_role_arn  = module.iam.ecs_task_role_arn
  task_role_arn       = module.iam.ecs_task_role_arn
  cpu                 = 512
  memory              = 1024
  container_port      = 5002
  aws_region          = "ap-south-1"
  network_mode        = "awsvpc"
  environment_variables = [
    { name = "ENV", value = "development" },
    { name = "SERVICE", value = "identity" }
  ]
}

module "ecs_task_payment" {
  source              = "../../modules/ecs-task"
  family              = "develop-gp2-payment-task"
  container_name      = "develop-gp2-payment-container"
  ecr_repository_url  = module.ecr.repository_urls["payment"]
  execution_role_arn  = module.iam.ecs_task_role_arn
  task_role_arn       = module.iam.ecs_task_role_arn
  cpu                 = 512
  memory              = 1024
  container_port      = 5003
  aws_region          = "ap-south-1"
  network_mode        = "awsvpc"
  environment_variables = [
    { name = "ENV", value = "development" },
    { name = "SERVICE", value = "payment" }
  ]
}

module "ecs_task_workspace" {
  source              = "../../modules/ecs-task"
  family              = "develop-gp2-workspace-task"
  container_name      = "develop-gp2-workspace-container"
  ecr_repository_url  = module.ecr.repository_urls["workspace"]
  execution_role_arn  = module.iam.ecs_task_role_arn
  task_role_arn       = module.iam.ecs_task_role_arn
  cpu                 = 512
  memory              = 1024
  container_port      = 5006
  aws_region          = "ap-south-1"
  network_mode        = "awsvpc"
  environment_variables = [
    { name = "ENV", value = "development" },
    { name = "SERVICE", value = "workspace" }
  ]
}

module "ecs_task_tenant" {
  source              = "../../modules/ecs-task"
  family              = "develop-gp2-tenant-task"
  container_name      = "develop-gp2-tenant-container"
  ecr_repository_url  = module.ecr.repository_urls["tenant"]
  execution_role_arn  = module.iam.ecs_task_role_arn
  task_role_arn       = module.iam.ecs_task_role_arn
  cpu                 = 512
  memory              = 1024
  container_port      = 3001
  aws_region          = "ap-south-1"
  network_mode        = "bridge"

  environment_variables = [
    { name = "ENV", value = "development" },
    { name = "SERVICE", value = "tenant" }
  ]
}

module "ecs_task_webhook" {
  source              = "../../modules/ecs-task"
  family              = "develop-gp2-webhook-task"
  container_name      = "develop-gp2-webhook-container"
  ecr_repository_url  = module.ecr.repository_urls["webhook"]
  execution_role_arn  = module.iam.ecs_task_role_arn
  task_role_arn       = module.iam.ecs_task_role_arn
  cpu                 = 512
  memory              = 1024
  container_port      = 5007
  aws_region          = "ap-south-1"
  network_mode        = "bridge"

  environment_variables = [
    { name = "ENV", value = "development" },
    { name = "SERVICE", value = "webhook" }
  ]
}

module "ecs_task_marketing" {
  source              = "../../modules/ecs-task"
  family              = "develop-gp2-marketing-task"
  container_name      = "develop-gp2-marketing-container"
  ecr_repository_url  = module.ecr.repository_urls["marketing"]
  execution_role_arn  = module.iam.ecs_task_role_arn
  task_role_arn       = module.iam.ecs_task_role_arn
  cpu                 = 512
  memory              = 1024
  container_port      = 3000
  aws_region          = "ap-south-1"
  network_mode        = "bridge"

  environment_variables = [
    { name = "ENV", value = "development" },
    { name = "SERVICE", value = "marketing" }
  ]
}

module "ecs_task_permitio" {
  source              = "../../modules/ecs-task"
  family              = "develop-gp2-permitio-task"
  container_name      = "develop-gp2-marketing-container"
  ecr_repository_url  = module.ecr.repository_urls["permitio"]
  execution_role_arn  = module.iam.ecs_task_role_arn
  task_role_arn       = module.iam.ecs_task_role_arn
  cpu                 = 512
  memory              = 1024
  container_port      = 3000
  aws_region          = "ap-south-1"
  network_mode        = "bridge"

  environment_variables = [
    { name = "ENV", value = "development" },
    { name = "SERVICE", value = "marketing" }
  ]
}

module "ecs_service_configs" {
  source                 = "../../modules/ecs-service"
  environment            = "develop-gp2-configs"
  cluster_id             = module.ecs.ecs_cluster_id
  task_definition_arn    = module.ecs_task_configs.ecs_task_definition_arn
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_group.security_group_id
  target_group_arn       = module.alb.target_group_arn
  container_name         = "develop-gp2-configs-container"
  container_port         = 5004
  service_connect_namespace = module.cloud_map.namespace_id  
  health_check_path      = "/configs/health"
  # Auto Scaling Configuration
  min_task_count       = 1
  max_task_count       = 5
  target_cpu_utilization = 50
  scale_in_cooldown    = 120
  scale_out_cooldown   = 300
}

module "ecs_service_documents" {
  source                 = "../../modules/ecs-service"
  environment            = "develop-gp2-documents"
  cluster_id             = module.ecs.ecs_cluster_id
  task_definition_arn    = module.ecs_task_documents.ecs_task_definition_arn
  desired_count          = 2
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_group.security_group_id
  target_group_arn       = module.alb.target_group_arn
  container_name         = "develop-gp2-documents-container"
  container_port         = 5008
  service_connect_namespace = module.cloud_map.namespace_id  
  health_check_path      = "/documents/health"
  
  # Auto Scaling Configuration
  min_task_count       = 1
  max_task_count       = 5
  target_cpu_utilization = 50
  scale_in_cooldown    = 120
  scale_out_cooldown   = 300
}

module "ecs_service_gateway" {
  source                 = "../../modules/ecs-service"
  environment            = "develop-gp2-gateway"
  cluster_id             = module.ecs.ecs_cluster_id
  task_definition_arn    = module.ecs_task_gateway.ecs_task_definition_arn
  desired_count          = 2
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_group.security_group_id
  target_group_arn       = module.alb.gateway_target_group_arn
  container_name         = "develop-gp2-gateway-container"
  container_port         = 5000
  service_connect_namespace = module.cloud_map.namespace_id  
  health_check_path      = "/gateway/health"
  # Auto Scaling Configuration
  min_task_count       = 1
  max_task_count       = 5
  target_cpu_utilization = 50
  scale_in_cooldown    = 120
  scale_out_cooldown   = 300
}

module "ecs_service_identity" {
  source                 = "../../modules/ecs-service"
  environment            = "develop-gp2-identity"
  cluster_id             = module.ecs.ecs_cluster_id
  task_definition_arn    = module.ecs_task_identity.ecs_task_definition_arn
  desired_count          = 2
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_group.security_group_id
  target_group_arn       = module.alb.target_group_arn
  container_name         = "develop-gp2-identity-container"
  container_port         =  5002
  service_connect_namespace = module.cloud_map.namespace_id  
  health_check_path      = "/identity/health"
  # Auto Scaling Configuration
  min_task_count       = 1
  max_task_count       = 5
  target_cpu_utilization = 50
  scale_in_cooldown    = 120
  scale_out_cooldown   = 300
}

module "ecs_service_payment" {
  source                 = "../../modules/ecs-service"
  environment            = "develop-gp2-payment"
  cluster_id             = module.ecs.ecs_cluster_id
  task_definition_arn    = module.ecs_task_payment.ecs_task_definition_arn
  desired_count          = 2
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_group.security_group_id
  target_group_arn       = module.alb.target_group_arn
  container_name         = "develop-gp2-payment-container"
  container_port         = 5003
  service_connect_namespace = module.cloud_map.namespace_id  
  health_check_path      = "/payment/health"
  # Auto Scaling Configuration
  min_task_count       = 1
  max_task_count       = 5
  target_cpu_utilization = 50
  scale_in_cooldown    = 120
  scale_out_cooldown   = 300
}

module "ecs_service_workspace" {
  source                 = "../../modules/ecs-service"
  environment            = "develop-gp2-workspace"
  cluster_id             = module.ecs.ecs_cluster_id
  task_definition_arn    = module.ecs_task_workspace.ecs_task_definition_arn
  desired_count          = 2
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_group.security_group_id
  target_group_arn       = module.alb.target_group_arn
  container_name         = "develop-gp2-workspace-container"
  container_port         = 5006
  service_connect_namespace = module.cloud_map.namespace_id  
  health_check_path      = "/workspace/health"
  # Auto Scaling Configuration
  min_task_count       = 1
  max_task_count       = 5
  target_cpu_utilization = 50
  scale_in_cooldown    = 120
  scale_out_cooldown   = 300
}

module "ecs_service_tenant" {
  source                 = "../../modules/ecs-service"
  environment            = "develop-gp2-tenant"
  cluster_id             = module.ecs.ecs_cluster_id
  task_definition_arn    = module.ecs_task_tenant.ecs_task_definition_arn
  desired_count          = 2
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_group.security_group_id
  target_group_arn       = module.alb.frontend_tenant_target_group_arn
  container_name         = "develop-gp2-tenant-container"
  container_port         = 3001
  service_connect_namespace = module.cloud_map.namespace_id  
  health_check_path      = "/tenant/health"
  # Auto Scaling Configuration
  min_task_count       = 1
  max_task_count       = 5
  target_cpu_utilization = 50
  scale_in_cooldown    = 120
  scale_out_cooldown   = 300
}

module "ecs_service_webhook" {
  source                 = "../../modules/ecs-service"
  environment            = "develop-gp2-webhook"
  cluster_id             = module.ecs.ecs_cluster_id
  task_definition_arn    = module.ecs_task_webhook.ecs_task_definition_arn
  desired_count          = 2
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_group.security_group_id
  target_group_arn       = module.alb.webhook_target_group_arn  
  container_name         = "develop-gp2-webhook-container"
  container_port         = 5007
  service_connect_namespace = module.cloud_map.namespace_id  
  health_check_path      = "/webhook/health"
  # Auto Scaling Configuration
  min_task_count       = 1
  max_task_count       = 5
  target_cpu_utilization = 50
  scale_in_cooldown    = 120
  scale_out_cooldown   = 300
}

module "ecs_service_marketing" {
  source                 = "../../modules/ecs-service"
  environment            = "develop-gp2-marketing"
  cluster_id             = module.ecs.ecs_cluster_id
  task_definition_arn    = module.ecs_task_marketing.ecs_task_definition_arn
  desired_count          = 2
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_group.security_group_id
  target_group_arn       = module.alb.target_group_arn
  container_name         = "develop-gp2-marketing-container"
  container_port         = 3000 
  service_connect_namespace = module.cloud_map.namespace_id  
  health_check_path      = "/marketing/health"
  # Auto Scaling Configuration
  min_task_count       = 1
  max_task_count       = 5
  target_cpu_utilization = 50
  scale_in_cooldown    = 120
  scale_out_cooldown   = 300

}

module "ecs_service_permitio" {
  source                 = "../../modules/ecs-service"
  environment            = "develop-gp2-permitio"
  cluster_id             = module.ecs.ecs_cluster_id
  task_definition_arn    = module.ecs_task_marketing.ecs_task_definition_arn
  desired_count          = 2
  private_subnet_ids     = module.vpc.private_subnet_ids
  security_group_id      = module.security_group.security_group_id
  target_group_arn       = module.alb.permitio_target_group_arn
  container_name         = "develop-gp2-marketing-container"
  container_port         = 3000 
  service_connect_namespace = module.cloud_map.namespace_id  
  health_check_path      = "/permitio/health"
  # Auto Scaling Configuration
  min_task_count       = 1
  max_task_count       = 5
  target_cpu_utilization = 50
  scale_in_cooldown    = 120
  scale_out_cooldown   = 300
}
