# One-Click EKS Cluster Deployment for ArgoCD Tutorial
# PowerShell Script

param(
    [string]$ClusterName = "argocd-tutorial-cluster",
    [string]$Region = "eu-west-1",
    [string]$StackName = "argocd-eks-stack",
    [string]$NodeInstanceType = "t3.small",
    [int]$DesiredNodes = 2
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "EKS Cluster Deployment Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

# Check AWS CLI
try {
    $awsVersion = aws --version 2>&1
    Write-Host "[OK] AWS CLI found: $awsVersion" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] AWS CLI not found. Please install AWS CLI first." -ForegroundColor Red
    Write-Host "  Download from: https://aws.amazon.com/cli/" -ForegroundColor Yellow
    exit 1
}

# Check kubectl
try {
    $kubectlVersion = kubectl version --client --short 2>&1
    Write-Host "[OK] kubectl found: $kubectlVersion" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] kubectl not found. Please install kubectl first." -ForegroundColor Red
    Write-Host "  Download from: https://kubernetes.io/docs/tasks/tools/" -ForegroundColor Yellow
    exit 1
}

# Check AWS credentials
Write-Host ""
Write-Host "Checking AWS credentials..." -ForegroundColor Yellow
try {
    $identity = aws sts get-caller-identity --output json 2>&1 | ConvertFrom-Json
    Write-Host "[OK] AWS credentials configured" -ForegroundColor Green
    Write-Host "  Account: $($identity.Account)" -ForegroundColor Gray
    Write-Host "  User/Role: $($identity.Arn)" -ForegroundColor Gray
} catch {
    Write-Host "[ERROR] AWS credentials not configured. Please run 'aws configure' first." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Deployment Configuration:" -ForegroundColor Cyan
Write-Host "  Stack Name: $StackName" -ForegroundColor White
Write-Host "  Cluster Name: $ClusterName" -ForegroundColor White
Write-Host "  Region: $Region" -ForegroundColor White
Write-Host "  Node Type: $NodeInstanceType" -ForegroundColor White
Write-Host "  Desired Nodes: $DesiredNodes" -ForegroundColor White
Write-Host ""

$confirm = Read-Host "Continue with deployment? (y/n)"
if ($confirm -ne 'y') {
    Write-Host "Deployment cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Creating or Updating CloudFormation Stack..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check if stack already exists
$existing = aws cloudformation describe-stacks --stack-name $StackName --region $Region 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[INFO] Stack already exists — updating instead..." -ForegroundColor Yellow
    aws cloudformation update-stack `
        --stack-name $StackName `
        --template-body file://eks-cluster.yaml `
        --parameters `
            ParameterKey=ClusterName,ParameterValue=$ClusterName `
            ParameterKey=NodeInstanceType,ParameterValue=$NodeInstanceType `
            ParameterKey=NodeGroupDesiredSize,ParameterValue=$DesiredNodes `
        --capabilities CAPABILITY_NAMED_IAM `
        --region $Region
} else {
    aws cloudformation create-stack `
        --stack-name $StackName `
        --template-body file://eks-cluster.yaml `
        --parameters `
            ParameterKey=ClusterName,ParameterValue=$ClusterName `
            ParameterKey=NodeInstanceType,ParameterValue=$NodeInstanceType `
            ParameterKey=NodeGroupDesiredSize,ParameterValue=$DesiredNodes `
        --capabilities CAPABILITY_NAMED_IAM `
        --region $Region
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to create or update stack" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Stack operation initiated" -ForegroundColor Green
Write-Host ""
Write-Host "Waiting for stack operation to complete..." -ForegroundColor Yellow
Write-Host "This will take approximately 15–20 minutes..." -ForegroundColor Gray
Write-Host ""

# Wait for stack completion
$startTime = Get-Date
$timeout = 30 # minutes
$checkInterval = 30 # seconds

while ($true) {
    Start-Sleep -Seconds $checkInterval
    
    $stackStatus = aws cloudformation describe-stacks `
        --stack-name $StackName `
        --region $Region `
        --query "Stacks[0].StackStatus" `
        --output text 2>&1
    
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    
    Write-Host "[$elapsed min] Stack status: $stackStatus" -ForegroundColor Cyan
    
    if ($stackStatus -eq "CREATE_COMPLETE" -or $stackStatus -eq "UPDATE_COMPLETE") {
        Write-Host ""
        Write-Host "[OK] Stack operation completed successfully!" -ForegroundColor Green
        break
    } elseif ($stackStatus -match "ROLLBACK|FAILED") {
        Write-Host ""
        Write-Host "[ERROR] Stack operation failed with status: $stackStatus" -ForegroundColor Red
        aws cloudformation describe-stack-events `
            --stack-name $StackName `
            --region $Region `
            --query "StackEvents[?ResourceStatus=='CREATE_FAILED'].[LogicalResourceId,ResourceStatusReason]" `
            --output table
        exit 1
    }
    
    if ($elapsed -gt $timeout) {
        Write-Host ""
        Write-Host "[ERROR] Timeout waiting for stack operation ($timeout minutes)" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuring kubectl..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Update kubeconfig
aws eks update-kubeconfig --region $Region --name $ClusterName

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] kubeconfig updated successfully" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Failed to update kubeconfig" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Verifying cluster access..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

try {
    $nodes = kubectl get nodes --no-headers 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Cluster is accessible" -ForegroundColor Green
        Write-Host ""
        Write-Host "Current nodes:" -ForegroundColor Cyan
        kubectl get nodes
    } else {
        Write-Host "[WARNING] Could not verify cluster access yet. Nodes may still be initializing." -ForegroundColor Yellow
        Write-Host "  Try running: kubectl get nodes" -ForegroundColor Gray
    }
} catch {
    Write-Host "[WARNING] Could not verify cluster access: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Cluster Information:" -ForegroundColor Cyan
Write-Host "  Name: $ClusterName" -ForegroundColor White
Write-Host "  Region: $Region" -ForegroundColor White
Write-Host "  Stack: $StackName" -ForegroundColor White
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Verify cluster: kubectl get nodes" -ForegroundColor White
Write-Host "  2. Install ArgoCD:" -ForegroundColor White
Write-Host "     kubectl create namespace argocd" -ForegroundColor Gray
Write-Host "     kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml" -ForegroundColor Gray
Write-Host "  3. Expose ArgoCD server:" -ForegroundColor White
Write-Host "     kubectl patch svc argocd-server -n argocd -p '{""spec"":{""type"":""LoadBalancer""}}'" -ForegroundColor Gray
Write-Host ""
Write-Host "Happy learning, 🚀" -ForegroundColor Green
