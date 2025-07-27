# Hello World HTTP Java

A minimal Java HTTP server that serves "Hello World!" on port 8080.

## Quick Start

### Local Development
```bash
# Build the application
./build.sh

# Run the application
java -jar HelloWorld.jar
```

The server will be available at `http://localhost:8080`

### AWS Deployment

This project is configured for deployment to AWS Elastic Beanstalk using GitHub Actions CI/CD.

#### Prerequisites
- AWS CLI configured with appropriate credentials
- Java 8 or higher

#### Setup AWS Resources
```bash
# Run the setup script to create AWS resources
./setup-aws-elasticbeanstalk.sh
```

#### Cleanup AWS Resources
```bash
# Clean up AWS resources when done
./cleanup-aws-resources.sh
```

## Project Structure

- `HelloWorld.java` - Main application code
- `build.sh` - Build script
- `setup-aws-elasticbeanstalk.sh` - AWS setup script
- `cleanup-aws-resources.sh` - AWS cleanup script
- `.github/workflows/cicd.yml` - GitHub Actions CI/CD pipeline

## CI/CD Pipeline

The GitHub Actions pipeline automatically:
1. Builds the Java application
2. Uploads to AWS S3
3. Deploys to Elastic Beanstalk
4. Performs health checks

## License

MIT License - see LICENSE file for details.
