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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to cleanup on exit
cleanup() {
    print_warning "Cleaning up temporary files..."
    rm -f test.txt test.jar test-download.jar
}

# Set trap for cleanup
trap cleanup EXIT

# Step 1: Set Variables
APP_NAME="hello-world-http-java"
ENV_NAME="hello-world-http-java-env"
REGION="us-east-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
S3_BUCKET="elasticbeanstalk-$REGION-$ACCOUNT_ID"
JAR_FILE="HelloWorld.jar"
VERSION_LABEL="v-$(date +%Y%m%d%H%M%S)"
SOLUTION_STACK="64bit Amazon Linux 2023 v4.6.1 running Corretto 8"

print_status "=== AWS Elastic Beanstalk Setup Script ==="
print_status "This script intelligently sets up AWS resources:"
print_status "- Checks for existing resources and reuses them if usable"
print_status "- Only creates new resources when necessary"
print_status "- Ensures all required policies and attachments are in place"
echo ""
print_status "App Name: $APP_NAME"
print_status "Environment: $ENV_NAME"
print_status "Region: $REGION"
print_status "S3 Bucket: $S3_BUCKET"
print_status "Version: $VERSION_LABEL"
print_status "Solution Stack: $SOLUTION_STACK"
echo ""

# Step 2: Check prerequisites
print_status "Checking prerequisites..."

if ! command_exists aws; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

if ! command_exists java; then
    print_error "Java is not installed. Please install it first."
    exit 1
fi

if [ ! -f "$JAR_FILE" ]; then
    print_error "JAR file $JAR_FILE not found in current directory."
    exit 1
fi

print_success "Prerequisites check passed"
echo ""

# Step 3: Ensure S3 Bucket Exists
print_status "Step 3: Checking S3 bucket..."
if aws s3 ls "s3://$S3_BUCKET" 2>/dev/null; then
    print_success "S3 bucket already exists and is accessible"
else
    print_status "Creating S3 bucket..."
    aws s3 mb "s3://$S3_BUCKET" --region $REGION
    print_success "S3 bucket created"
fi
echo ""

# Step 4: Upload JAR to S3
print_status "Step 4: Uploading JAR to S3..."
aws s3 cp "$JAR_FILE" "s3://$S3_BUCKET/$JAR_FILE" --force
print_success "JAR uploaded to S3"
echo ""

# Step 5: Create IAM Role and Instance Profile
print_status "Step 5: Checking IAM role and instance profile..."

# Check if role exists and has required policies
if aws iam get-role --role-name aws-elasticbeanstalk-ec2-role 2>/dev/null; then
    print_success "IAM role already exists"
    
    # Check if required policy is attached
    if aws iam list-attached-role-policies --role-name aws-elasticbeanstalk-ec2-role --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier']" --output text 2>/dev/null | grep -q "AWSElasticBeanstalkWebTier"; then
        print_success "Required policy already attached"
    else
        print_status "Attaching required policy to existing role..."
        aws iam attach-role-policy \
            --role-name aws-elasticbeanstalk-ec2-role \
            --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier
        print_success "Policy attached"
    fi
else
    print_status "Creating IAM role..."
    aws iam create-role \
        --role-name aws-elasticbeanstalk-ec2-role \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "ec2.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }'
    
    aws iam attach-role-policy \
        --role-name aws-elasticbeanstalk-ec2-role \
        --policy-arn arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier
    
    print_success "IAM role created with required policy"
fi

# Check if instance profile exists and has the role
if aws iam get-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role 2>/dev/null; then
    print_success "Instance profile already exists"
    
    # Check if role is attached to instance profile
    if aws iam get-instance-profile --instance-profile-name aws-elasticbeanstalk-ec2-role --query "InstanceProfile.Roles[?RoleName=='aws-elasticbeanstalk-ec2-role']" --output text 2>/dev/null | grep -q "aws-elasticbeanstalk-ec2-role"; then
        print_success "Role already attached to instance profile"
    else
        print_status "Attaching role to existing instance profile..."
        aws iam add-role-to-instance-profile \
            --instance-profile-name aws-elasticbeanstalk-ec2-role \
            --role-name aws-elasticbeanstalk-ec2-role
        print_success "Role attached to instance profile"
    fi
else
    print_status "Creating instance profile..."
    aws iam create-instance-profile \
        --instance-profile-name aws-elasticbeanstalk-ec2-role
    
    aws iam add-role-to-instance-profile \
        --instance-profile-name aws-elasticbeanstalk-ec2-role \
        --role-name aws-elasticbeanstalk-ec2-role
    
    print_success "Instance profile created with role"
fi
echo ""

# Step 6: Create Beanstalk Application
print_status "Step 6: Checking Beanstalk application..."
if aws elasticbeanstalk describe-applications --region $REGION --query "Applications[?ApplicationName=='$APP_NAME']" 2>/dev/null | grep -q "$APP_NAME"; then
    print_success "Application already exists"
else
    print_status "Creating Beanstalk application..."
    aws elasticbeanstalk create-application --application-name "$APP_NAME" --region $REGION
    print_success "Application created"
fi
echo ""

# Step 7: Create Application Version
print_status "Step 7: Creating application version..."
aws elasticbeanstalk create-application-version \
    --application-name "$APP_NAME" \
    --version-label "$VERSION_LABEL" \
    --source-bundle "S3Bucket=$S3_BUCKET,S3Key=$JAR_FILE" \
    --region $REGION
print_success "Application version created"
echo ""

# Step 8: Wait for Version Processing
print_status "Step 8: Waiting for version to be processed..."
sleep 10

VERSION_STATUS=$(aws elasticbeanstalk describe-application-versions \
    --application-name "$APP_NAME" \
    --version-labels "$VERSION_LABEL" \
    --region $REGION \
    --query "ApplicationVersions[0].Status" \
    --output text)

if [ "$VERSION_STATUS" = "PROCESSED" ]; then
    print_success "Version processed successfully"
else
    print_warning "Version status: $VERSION_STATUS (may still be processing)"
fi
echo ""

# Step 9: Create Environment
print_status "Step 9: Checking environment..."
ENV_EXISTS=$(aws elasticbeanstalk describe-environments \
    --application-name "$APP_NAME" \
    --region $REGION \
    --query "Environments[?EnvironmentName=='$ENV_NAME'] | length(@)" \
    --output text 2>/dev/null || echo "0")

if [ "$ENV_EXISTS" -eq 0 ]; then
    print_status "Creating new environment..."
    aws elasticbeanstalk create-environment \
        --application-name "$APP_NAME" \
        --environment-name "$ENV_NAME" \
        --solution-stack-name "$SOLUTION_STACK" \
        --version-label "$VERSION_LABEL" \
        --option-settings \
            "Namespace=aws:autoscaling:launchconfiguration,OptionName=InstanceType,Value=t2.micro" \
            "Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=aws-elasticbeanstalk-ec2-role" \
        --region $REGION
    print_success "Environment created"
else
    # Check if environment is in a usable state
    ENV_STATUS=$(aws elasticbeanstalk describe-environments \
        --application-name "$APP_NAME" \
        --environment-name "$ENV_NAME" \
        --region $REGION \
        --query "Environments[0].Status" \
        --output text 2>/dev/null || echo "Unknown")
    
    if [ "$ENV_STATUS" = "Ready" ] || [ "$ENV_STATUS" = "Updating" ]; then
        print_status "Environment exists and is usable (Status: $ENV_STATUS), updating to new version..."
        aws elasticbeanstalk update-environment \
            --application-name "$APP_NAME" \
            --environment-name "$ENV_NAME" \
            --version-label "$VERSION_LABEL" \
            --region $REGION
        print_success "Environment updated"
    else
        print_warning "Environment exists but is in state: $ENV_STATUS"
        print_status "Terminating existing environment and creating new one..."
        ENV_ID=$(aws elasticbeanstalk describe-environments \
            --application-name "$APP_NAME" \
            --environment-name "$ENV_NAME" \
            --region $REGION \
            --query "Environments[0].EnvironmentId" \
            --output text)
        
        aws elasticbeanstalk terminate-environment \
            --environment-id "$ENV_ID" \
            --region $REGION
        
        # Wait for termination
        print_status "Waiting for environment termination..."
        sleep 30
        
        # Create new environment
        aws elasticbeanstalk create-environment \
            --application-name "$APP_NAME" \
            --environment-name "$ENV_NAME" \
            --solution-stack-name "$SOLUTION_STACK" \
            --version-label "$VERSION_LABEL" \
            --option-settings \
                "Namespace=aws:autoscaling:launchconfiguration,OptionName=InstanceType,Value=t2.micro" \
                "Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=aws-elasticbeanstalk-ec2-role" \
            --region $REGION
        print_success "New environment created"
    fi
fi
echo ""

# Step 10: Wait for Environment
print_status "Step 10: Waiting for environment to be ready..."
print_status "This may take 5-10 minutes..."

aws elasticbeanstalk wait environment-exists \
    --application-name "$APP_NAME" \
    --environment-names "$ENV_NAME" \
    --region $REGION

aws elasticbeanstalk wait environment-updated \
    --application-name "$APP_NAME" \
    --environment-names "$ENV_NAME" \
    --region $REGION

print_success "Environment is ready"
echo ""

# Step 11: Get Environment URL
print_status "Step 11: Getting environment URL..."
ENV_URL=$(aws elasticbeanstalk describe-environments \
    --application-name "$APP_NAME" \
    --environment-name "$ENV_NAME" \
    --region $REGION \
    --query "Environments[0].CNAME" \
    --output text)

print_success "Environment URL: $ENV_URL"
echo ""

# Step 12: Health Check
print_status "Step 12: Performing health check..."
sleep 30

if curl -f "http://$ENV_URL" > /dev/null 2>&1; then
    print_success "Health check passed!"
    print_success "🎉 Your Java app is now running at: http://$ENV_URL"
else
    print_warning "Health check failed. The app might still be starting up."
    print_warning "Try accessing: http://$ENV_URL"
fi
echo ""

# Step 13: Display Summary
print_status "=== DEPLOYMENT SUMMARY ==="
echo "Application: $APP_NAME"
echo "Environment: $ENV_NAME"
echo "Version: $VERSION_LABEL"
echo "URL: http://$ENV_URL"
echo "Region: $REGION"
echo "Instance Type: t2.micro (Free Tier)"
echo ""
print_status "📋 GitHub Secrets to add to your repository:"
echo "BEANSTALK_S3_BUCKET=$S3_BUCKET"
echo "BEANSTALK_APP_NAME=$APP_NAME"
echo "BEANSTALK_ENV_NAME=$ENV_NAME"
echo "BEANSTALK_ENV_URL=$ENV_URL"
echo "AWS_REGION=$REGION"
echo ""
print_status "🔗 AWS Console Links:"
echo "Elastic Beanstalk: https://console.aws.amazon.com/elasticbeanstalk/home?region=$REGION"
echo "S3 Bucket: https://s3.console.aws.amazon.com/s3/buckets/$S3_BUCKET"
echo ""
print_success "✅ Setup complete!" 