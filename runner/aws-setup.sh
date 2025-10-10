#!/usr/bin/env bash
set -euo pipefail

# === Inputs (export these or edit inline) =====================================
# Required:
ORG="${ORG:-}"             # your GitHub org/user, e.g. "my-org"
REPO="${REPO:-}"           # your repo name, e.g. "homelab"
REGION="${REGION:-}"       # e.g. "us-east-2"

# Optional (sensible defaults if omitted):
ROLE_NAME="${ROLE_NAME:-github-oidc-terraform}"
TABLE="${TABLE:-tfstate-locks}"

# If BUCKET is empty, we generate a unique one: <org>-<repo>-tfstate-<rand>
BUCKET="${BUCKET:-}"

# =============================================================================

# Validate required inputs
[[ -n "$ORG" ]]    || { echo "Set ORG (your GitHub org/user)"; exit 1; }
[[ -n "$REPO" ]]   || { echo "Set REPO (your repo name)"; exit 1; }
[[ -n "$REGION" ]] || { echo "Set REGION (e.g. us-east-2)"; exit 1; }

# Generate a bucket if none provided
if [[ -z "$BUCKET" ]]; then
  RAND="$(openssl rand -hex 4 2>/dev/null || date +%s)"
  BUCKET="$(echo "${ORG}-${REPO}-tfstate-${RAND}" | tr '[:upper:]' '[:lower:]')"
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "Account: $ACCOUNT_ID"
echo "Region:  $REGION"
echo "Bucket:  $BUCKET"
echo "Table:   $TABLE"
echo "Repo:    $ORG/$REPO"
echo

OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

# 1) Ensure OIDC provider exists
if aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text | grep -q "$OIDC_ARN"; then
  echo "OIDC provider exists: $OIDC_ARN"
else
  echo "Creating OIDC provider..."
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
fi

# 2) Render trust/policy from templates in runner/
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRUST_TMPL="${ROOT_DIR}/runner/trust.json.tmpl"
POLICY_TMPL="${ROOT_DIR}/runner/policy-tfstate.json.tmpl"

mkdir -p "${ROOT_DIR}/runner/build"
TRUST_JSON="${ROOT_DIR}/runner/build/trust.json"
POLICY_JSON="${ROOT_DIR}/runner/build/policy.json"

sed -e "s/__ACCOUNT_ID__/${ACCOUNT_ID}/g" \
    -e "s#__ORG__#${ORG}#g" \
    -e "s#__REPO__#${REPO}#g" \
    "$TRUST_TMPL" > "$TRUST_JSON"

# 3) Create or update role
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  echo "Updating trust policy on role: $ROLE_NAME"
  aws iam update-assume-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-document "file://${TRUST_JSON}"
else
  echo "Creating role: $ROLE_NAME"
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://${TRUST_JSON}"
fi

# 4) Create/verify backend resources (S3 + DynamoDB)
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Bucket exists: $BUCKET"
else
  echo "Creating bucket: $BUCKET"
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET"
  else
    aws s3api create-bucket --bucket "$BUCKET" \
      --create-bucket-configuration LocationConstraint="$REGION" \
      --region "$REGION"
  fi
  aws s3api put-public-access-block --bucket "$BUCKET" --region "$REGION" \
    --public-access-block-configuration '{"BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true}'
  aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled --region "$REGION"
  aws s3api put-bucket-encryption --bucket "$BUCKET" --region "$REGION" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
fi

if aws dynamodb describe-table --table-name "$TABLE" --region "$REGION" >/dev/null 2>&1; then
  echo "DynamoDB table exists: $TABLE"
else
  echo "Creating DynamoDB table: $TABLE"
  aws dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"
  aws dynamodb wait table-exists --table-name "$TABLE" --region "$REGION"
fi

# 5) Render & attach inline policy bound to your bucket/region/account/table
sed -e "s/__ACCOUNT_ID__/${ACCOUNT_ID}/g" \
    -e "s/__REGION__/${REGION}/g" \
    -e "s#__BUCKET__#${BUCKET}#g" \
    -e "s#__TABLE__#${TABLE}#g" \
    "$POLICY_TMPL" > "$POLICY_JSON"

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name tfstate-access \
  --policy-document "file://${POLICY_JSON}"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
cat <<EOF

=== Outputs ===
AWS_ROLE_ARN=${ROLE_ARN}
TF_BACKEND_BUCKET=${BUCKET}
TF_BACKEND_TABLE=${TABLE}
TF_BACKEND_PREFIX=lab   # change if you want
AWS_REGION=${REGION}

Next:
  1) Set those as GitHub Repository Variables
  2) Commit the workflow & backend files
  3) Run the "terraform-apply" workflow

EOF
