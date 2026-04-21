#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env if present
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

# Validate required env vars
for var in ANTHROPIC_API_KEY SCANNER_MCP_URL SCANNER_MCP_API_KEY SLACK_BOT_TOKEN SLACK_TEAM_ID SLACK_CHANNEL_NAME SLACK_CHANNEL_ID ABUSECH_AUTH_KEY OTX_API_KEY; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set. Create a .env file with your credentials." >&2
    exit 1
  fi
done

AWS_REGION="${AWS_REGION:-us-west-2}"
AWS_PROFILE="${AWS_PROFILE:?Set AWS_PROFILE in .env}"
TF_VARS=(
  -var="anthropic_api_key=$ANTHROPIC_API_KEY"
  -var="scanner_mcp_url=$SCANNER_MCP_URL"
  -var="scanner_mcp_api_key=$SCANNER_MCP_API_KEY"
  -var="slack_bot_token=$SLACK_BOT_TOKEN"
  -var="slack_team_id=$SLACK_TEAM_ID"
  -var="slack_channel_name=$SLACK_CHANNEL_NAME"
  -var="slack_channel_id=$SLACK_CHANNEL_ID"
  -var="abusech_auth_key=$ABUSECH_AUTH_KEY"
  -var="otx_api_key=$OTX_API_KEY"
)

# Step 1: Ensure ECR repo exists (targeted apply)
echo "==> Ensuring ECR repository exists..."
cd terraform
terraform init -input=false
terraform apply -target=aws_ecr_repository.triage "${TF_VARS[@]}" -auto-approve
ECR_REPO=$(terraform output -raw ecr_repository_url)
cd "$SCRIPT_DIR"

# Step 2: Build TypeScript
echo ""
echo "==> Building TypeScript..."
npm run build

# Step 3: Build Docker image
echo ""
echo "==> Building Docker image..."
docker build --platform linux/amd64 --provenance=false -t triage-agent .

# Step 4: Push to ECR
echo ""
echo "==> Logging into ECR..."
AWS_ACCOUNT=$(echo "$ECR_REPO" | cut -d. -f1)
aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" \
  | docker login --username AWS --password-stdin "${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "==> Pushing image to $ECR_REPO..."
docker tag triage-agent:latest "${ECR_REPO}:latest"
docker push "${ECR_REPO}:latest"

# Step 5: Full Terraform apply (ECS + VPC + EventBridge + everything else)
echo ""
echo "==> Running full Terraform apply..."
cd terraform
terraform apply "${TF_VARS[@]}" -auto-approve
cd "$SCRIPT_DIR"

echo ""
echo "==> Deploy complete!"
echo "    ECR: ${ECR_REPO}:latest"
echo "    ECS Cluster: soc-agents"
echo "    EventBridge: soc-threat-hunt-schedule (every 6 hours)"
echo "    Logs: /ecs/triage-agent"
echo ""
echo "Manually trigger a run with:"
echo "  aws ecs run-task \\"
echo "    --cluster soc-agents \\"
echo "    --task-definition triage-agent \\"
echo "    --launch-type FARGATE \\"
echo "    --network-configuration 'awsvpcConfiguration={subnets=[PRIVATE_SUBNET_ID],securityGroups=[SG_ID],assignPublicIp=DISABLED}' \\"
echo "    --profile $AWS_PROFILE --region $AWS_REGION"
echo ""
echo "WARNING: NAT gateway costs ~\$32/month. Run 'cd terraform && terraform destroy' when done."
