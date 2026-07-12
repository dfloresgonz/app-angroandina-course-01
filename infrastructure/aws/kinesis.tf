resource "aws_kinesis_stream" "main" {
  name        = "${var.project_name}-stream"
  shard_count = 1
  tags        = local.tags
}
