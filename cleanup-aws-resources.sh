#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Variables
APP_NAME="hello-world-http-java"
ENV_NAME="hello-world-http-java-env"
REGION="us-east-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET="elasticbeanstalk-$REGION-$ACCOUNT_ID"

print_status "=== AWS Resource Cleanup Script ==="
print_warning "This script will delete all AWS resources created for this project."
print_warning "This action cannot be undone!"
echo ""

# Confirmation
read -p "Are you sure you want to continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    print_status "Cleanup cancelled."
    exit 0
fi

echo ""

# Step 1: Terminate Environment
print_status "Step 1: Terminating Elastic Beanstalk environment..."
ENV_EXISTS=$(aws elasticbeanstalk describe-environments \
    --application-name "$APP_NAME" \
    --region $REGION \
    --query "Environments[?EnvironmentName=='$ENV_NAME'] | length(@)" \
    --output text 2>/dev/null || echo "0")

if [ "$ENV_EXISTS" -gt 0 ]; then
    ENV_ID=$(aws elasticbeanstalk describe-environments \
        --application-name "$APP_NAME" \
        --environment-name "$ENV_NAME" \
        --region $REGION \
        --query "Environments[0].EnvironmentId" \
        --output text)
    
    aws elasticbeanstalk terminate-environment \
        --environment-id "$ENV_ID" \
        --region $REGION
    
    print_success "Environment termination initiated"
else
    print_status "Environment not found or already terminated"
fi
echo ""

# Step 2: Delete Application Versions
print_status "Step 2: Deleting application versions..."
VERSIONS=$(aws elasticbeanstalk describe-application-versions \
    --application-name "$APP_NAME" \
    --region $REGION \
    --query "ApplicationVersions[].VersionLabel" \
    --output text 2>/dev/null || echo "")

if [ ! -z "$VERSIONS" ]; then
    for version in $VERSIONS; do
        print_status "Deleting version: $version"
        aws elasticbeanstalk delete-application-version \
            --application-name "$APP_NAME" \
            --version-label "$version" \
            --delete-source-bundle \
            --region $REGION
    done
    print_success "Application versions deleted"
else
    print_status "No application versions found"
fi
echo ""

# Step 3: Delete Application
print_status "Step 3: Deleting Elastic Beanstalk application..."
if aws elasticbeanstalk describe-applications --region $REGION --query "Applications[?ApplicationName=='$APP_NAME']" 2>/dev/null | grep -q "$APP_NAME"; then
    aws elasticbeanstalk delete-application \
        --application-name "$APP_NAME" \
        --terminate-env-by-force \
        --region $REGION
    print_success "Application deleted"
else
    print_status "Application not found"
fi
echo ""

# Step 4: Delete S3 Objects
print_status "Step 4: Deleting S3 objects..."
if aws s3 ls "s3://$S3_BUCKET/" 2>/dev/null; then
    aws s3 rm "s3://$S3_BUCKET/" --recursive
    print_success "S3 objects deleted"
else
    print_status "S3 bucket is empty or doesn't exist"
fi
echo ""

# Step 5: Delete S3 Bucket
print_status "Step 5: Deleting S3 bucket..."
if aws s3 ls "s3://$S3_BUCKET" 2>/dev/null; then
    aws s3 rb "s3://$S3_BUCKET" --force
    print_success "S3 bucket deleted"
else
    print_status "S3 bucket doesn't exist"
fi
echo ""

# Step 6: Delete IAM Instance Profile
print_status "Step 6: Deleting IAM instance profile..."
if aws iam get-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role 2>/dev/null; then
    aws iam remove-role-from-instance-profile \
        --instance-profile-name aws-elasticbeanstalk-ec2-role \
        --role-name aws-elasticbeanstalk-ec2-role
    
    aws iam delete-instance-profile \
        --instance-profile-name aws-elasticbeanstalk-ec2-role
    
    print_success "Instance profile deleted"
else
    print_status "Instance profile doesn't exist"
fi
echo ""

# Step 7: Delete IAM Role
print_status "Step 7: Deleting IAM role..."
if aws iam get-role --role-name aws-elasticbeanstalk-ec2-role 2>/dev/null; then
    # Detach policies
    POLICIES=$(aws iam list-attached-role-policies \
        --role-name aws-elasticbeanstalk-ec2-role \
        --query "AttachedPolicies[].PolicyArn" \
        --output text 2>/dev/null || echo "")
    
    for policy in $POLICIES; do
        if [ ! -z "$policy" ]; then
            aws iam detach-role-policy \
                --role-name aws-elasticbeanstalk-ec2-role \
                --policy-arn "$policy"
        fi
    done
    
    aws iam delete-role --role-name aws-elasticbeanstalk-ec2-role
    print_success "IAM role deleted"
else
    print_status "IAM role doesn't exist"
fi
echo ""

# Step 8: Clean up EC2 instances (if any orphaned)
print_status "Step 8: Checking for orphaned EC2 instances..."
INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=*hello-world-http-java*" "Name=instance-state-name,Values=running,stopped" \
    --region $REGION \
    --query "Reservations[].Instances[].InstanceId" \
    --output text 2>/dev/null || echo "")

if [ ! -z "$INSTANCES" ]; then
    print_warning "Found orphaned EC2 instances: $INSTANCES"
    read -p "Do you want to terminate these instances? (yes/no): " terminate_instances
    
    if [ "$terminate_instances" = "yes" ]; then
        aws ec2 terminate-instances --instance-ids $INSTANCES --region $REGION
        print_success "EC2 instances terminated"
    else
        print_status "EC2 instances left running"
    fi
else
    print_status "No orphaned EC2 instances found"
fi
echo ""

# Step 9: Clean up Security Groups (if any orphaned)
print_status "Step 9: Checking for orphaned security groups..."
SECURITY_GROUPS=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=*hello-world-http-java*" \
    --region $REGION \
    --query "SecurityGroups[?GroupName!='default'].GroupId" \
    --output text 2>/dev/null || echo "")

if [ ! -z "$SECURITY_GROUPS" ]; then
    print_warning "Found security groups: $SECURITY_GROUPS"
    read -p "Do you want to delete these security groups? (yes/no): " delete_sg
    
    if [ "$delete_sg" = "yes" ]; then
        for sg in $SECURITY_GROUPS; do
            aws ec2 delete-security-group --group-id "$sg" --region $REGION 2>/dev/null || print_warning "Could not delete security group $sg"
        done
        print_success "Security groups deleted"
    else
        print_status "Security groups left in place"
    fi
else
    print_status "No orphaned security groups found"
fi
echo ""

print_success "=== CLEANUP COMPLETE ==="
print_status "All AWS resources have been cleaned up."
print_status "Note: Some resources may take a few minutes to be fully deleted."
echo ""
print_status "Resources cleaned up:"
echo "- Elastic Beanstalk environment"
echo "- Application versions"
echo "- Elastic Beanstalk application"
echo "- S3 bucket and objects"
echo "- IAM instance profile"
echo "- IAM role"
echo "- Orphaned EC2 instances (if confirmed)"
echo "- Orphaned security groups (if confirmed)" 