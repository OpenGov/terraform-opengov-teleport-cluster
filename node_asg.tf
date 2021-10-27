// Node auto scaling group supports multiple
// teleport nodes joining the cluster,
// Setup for demo/testing purposes.
resource "aws_autoscaling_group" "node" {
  name                      = "${var.cluster_name}-node"
  count                     = 0
  max_size                  = 1000
  min_size                  = 0
  health_check_grace_period = 300
  health_check_type         = "EC2"
  desired_capacity          = 0
  force_delete              = false
  launch_configuration      = aws_launch_configuration.node[0].name
  vpc_zone_identifier       = [for subnet in aws_subnet.node : subnet.id]

  tag {
    key                 = "TeleportCluster"
    value               = var.cluster_name
    propagate_at_launch = true
  }

  tag {
    key                 = "TeleportRole"
    value               = "node"
    propagate_at_launch = true
  }

  // external autoscale algos can modify these values,
  // so ignore changes to them
  lifecycle {
    ignore_changes = [
      desired_capacity,
      max_size,
      min_size,
    ]
  }
}

resource "aws_kms_grant" "node" {
  name              = "teleport_node"
  count             = var.ami_kms_key_arn != "" ? 1 : 0
  key_id            = var.ami_kms_key_arn
  grantee_principal = aws_autoscaling_group.node[0].service_linked_role_arn
  operations        = ["Encrypt", "Decrypt", "ReEncryptFrom", "ReEncryptTo", "GenerateDataKey", "GenerateDataKeyWithoutPlaintext", "DescribeKey", "CreateGrant"]
  retire_on_delete  = false
}

resource "aws_launch_configuration" "node" {
  lifecycle {
    create_before_destroy = true
  }
  name_prefix                 = "${var.cluster_name}-node-"
  count                       = 0
  image_id                    = var.ami_id
  instance_type               = var.node_instance_type
  user_data                   = templatefile(
    "${path.module}/node-user-data.tpl",
    {
      region           = data.aws_region.current.name
      cluster_name     = var.cluster_name
      telegraf_version = var.telegraf_version
      auth_server_addr = aws_lb.auth.dns_name
      influxdb_addr    = "http://${aws_lb.monitor.dns_name}:8086"
      use_acm          = var.use_acm
    }
  )
  key_name                    = var.key_name
  associate_public_ip_address = false
  security_groups             = [aws_security_group.node.id]
  iam_instance_profile        = aws_iam_instance_profile.node.id
}
