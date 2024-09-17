module "ci_cd" {
  source = "./terraform-aws-cicd-module"
  codecommit_approval_template_name = "test-approval"

  ####CodeStar##########
  create_codestar_host = false // true if you want to use aws_codestarconnections_host
  connection_name = "my-github-connection"
  provider_type   = "GitHub"
  codestar_tags = {
    Name = "my-github-connection"
  }
  #######codebuild######
  codebuild_name      = "Adex-codebuild" //must be same with project name in build stage
  project_description = "Codebuild for deploying myapp"

  # Environment
  environment = {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:2.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }

  #cloudwatch log
  cloudwatch_logs = {
    group_name  = "adex-cicd-log"
    stream_name = "adex-cicd-stream"
    status      = "ENABLED"
  }

  s3_bucket_name = aws_s3_bucket.mybucket.bucket

  # Artifacts
  artifacts = {
    location            = aws_s3_bucket.mybucket.id
    type                = "CODEPIPELINE"
    path                = "/build"
    packaging           = "ZIP"
    bucket_owner_access = "READ_ONLY"
  }

  # Cache
  cache = {
    type     = "S3"
    location = "${aws_s3_bucket.mybucket.id}/cache"
  }

  # Logs
  s3_logs = {
    status              = "ENABLED"
    location            = "${aws_s3_bucket.mybucket.id}/build-log"
    bucket_owner_access = "READ_ONLY"
  }

 #######codeDeploy######

  # Create CodeDeploy Application
  create_app         = true
  codedeploy_name    = "sample-app" //must be same for app name and ApplicationName in deploy stage
  compute_platform   = "Server"
  codedeploy_sns_arn = data.aws_sns_topic.codestar_notifications.arn //sns topic arn for codebuild notifications
  # Create CodeDeploy Deployment Group
  create_deployment_group = true
  deployment_group_name   = "test-group" //must be same for app name and ApplicationName in deploy stage
  app_name                = "example-app" 
  deployment_config_name  = "MyCodeDeployDefault.OneAtATime"
  autoscaling_groups      = ["${aws_autoscaling_group.example_asg.id}"]
  deployment_style = {
    deployment_option = "WITH_TRAFFIC_CONTROL" //WITH_TRAFFIC_CONTROL orWITHOUT_TRAFFIC_CONTROL
    deployment_type   = "IN_PLACE"  //In place or Blue/Green
  }
 
  ec2_tag_filter = [{ //ec2 tag filter 
    key   = "Name"
    value = "example-asg"
    type  = "KEY_AND_VALUE"
  }]

  load_balancer_info = {   //Load balancer information for the deployment group
   target_group_info = {
     name = "example-tg"
   }
  }

  auto_rollback_configuration = {  //Auto rollback configuration
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  trigger_configuration = [  //Trigger configuration
    {
      trigger_events     = ["DeploymentFailure"]
      trigger_name       = "example-trigger"
      trigger_target_arn = data.aws_sns_topic.codestar_notifications.arn
    }
    // Add more trigger configurations as needed
  ]

  alarm_configuration = { //Add alarms to automatically stop deployments in this deployment group. 
    alarms  = ["my-alarm-name"]
    enabled = true
  }
  minimum_healthy_hosts = {
    type  = "HOST_COUNT" //HOST_COUNT or FLEET_PERCENT
    value = 1 //This depends on number of ec2 on asg 2 ec2 will be required to set vallue to 1
  }

  ########code pipeline#######
  ############################

  codepipeline_name = "Adex_pipeline"
  stages = [
    {
       name = "Source"
       action = [{
         name     = "Source"
         category = "Source"
         owner    = "AWS"
         provider = "CodeStarSourceConnection"
         version  = "1"
         configuration = {
           ConnectionArn        = module.ci_cd.codestar_connection_arn //codestar connection arn
           FullRepositoryId     = "baka126/aws-cicd"
           BranchName           = "master"
         }
         input_artifacts  = []
         output_artifacts = ["SourceArtifact"]
         run_order        = 1
       }]
     },
    {
      name = "Build"
      action = [{
        name             = "Build"
        category         = "Build"
        owner            = "AWS"
        provider         = "CodeBuild"
        input_artifacts  = ["SourceArtifact"]
        output_artifacts = ["BuildArtifact"]
        version          = "1"
        run_order        = 2
        configuration = {
          ProjectName = "Adex-codebuild"
        }
      }]
    },
    {
      name = "Deploy"
      action = [{
        name             = "Deploy"
        category         = "Deploy"
        owner            = "AWS"
        provider         = "CodeDeploy"
        version          = "1"
        input_artifacts  = ["BuildArtifact"]
        output_artifacts = []
        configuration = {
          ApplicationName     = "sample-app" //must be same for app name and ApplicationName in deploy stage
          DeploymentGroupName = "test-group"  //must be same for app name and ApplicationName in deploy stage
        }
        run_order = 3
      }]
    }
  ]
  kms_key_id = aws_kms_key.mykey.arn

  #####Notification For Each Stage#######
  notification_rules = [
    {
      detail_type    = "BASIC"
      event_type_ids = ["codebuild-project-build-state-failed", "codebuild-project-build-state-succeeded"]
      name           = "example-code-build-1"
      resource_arn   = module.ci_cd.codebuild_arn
      target_arn     = data.aws_sns_topic.codestar_notifications.arn
    },
    {
      detail_type    = "BASIC"
      event_type_ids = ["codepipeline-pipeline-pipeline-execution-succeeded", "codepipeline-pipeline-pipeline-execution-failed"]
      name           = "example-code-pipeline-1"
      resource_arn   = module.ci_cd.pipeline_arn
      target_arn     = data.aws_sns_topic.codestar_notifications.arn
    }
  ]
}
