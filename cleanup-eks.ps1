# Cleanup EKS Cluster
# PowerShell Script

param(
    [string]$StackName = "argocd-eks-stack",
    [string]$Region = "eu-west-1"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "EKS Cluster Cleanup Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if stack exists
Write-Host "Checking if stack exists..." -ForegroundColor Yellow
try {
    $stackStatus = aws cloudformation describe-stacks `
        --stack-name $StackName `
        --region $Region `
        --query "Stacks[0].StackStatus" `
        --output text 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Stack '$StackName' not found in region '$Region'" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[OK] Stack found: $stackStatus" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Error checking stack: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "WARNING: This will delete the entire EKS cluster and all associated resources!" -ForegroundColor Red
Write-Host "  Stack: $StackName" -ForegroundColor Yellow
Write-Host "  Region: $Region" -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Are you sure you want to continue? Type 'DELETE' to confirm"
if ($confirm -ne 'DELETE') {
    Write-Host "Cleanup cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deleting CloudFormation Stack..." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Delete stack
try {
    aws cloudformation delete-stack `
        --stack-name $StackName `
        --region $Region
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to initiate stack deletion" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[OK] Stack deletion initiated" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Error deleting stack: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Waiting for stack deletion to complete..." -ForegroundColor Yellow
Write-Host "This may take 10-15 minutes..." -ForegroundColor Gray
Write-Host ""

# Wait for stack deletion
$startTime = Get-Date
$timeout = 20 # minutes
$checkInterval = 30 # seconds

while ($true) {
    Start-Sleep -Seconds $checkInterval
    
    $stackStatus = aws cloudformation describe-stacks `
        --stack-name $StackName `
        --region $Region `
        --query "Stacks[0].StackStatus" `
        --output text 2>&1
    
    $elapsed = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
    
    # Stack not found means deletion is complete
    if ($LASTEXITCODE -ne 0 -or $stackStatus -match "does not exist") {
        Write-Host ""
        Write-Host "[OK] Stack deleted successfully!" -ForegroundColor Green
        break
    }
    
    Write-Host "[$elapsed min] Stack status: $stackStatus" -ForegroundColor Cyan
    
    if ($stackStatus -match "DELETE_FAILED") {
        Write-Host ""
        Write-Host "[ERROR] Stack deletion failed!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Checking stack events for errors..." -ForegroundColor Yellow
        aws cloudformation describe-stack-events `
            --stack-name $StackName `
            --region $Region `
            --query "StackEvents[?ResourceStatus=='DELETE_FAILED'].[LogicalResourceId,ResourceStatusReason]" `
            --output table
        Write-Host ""
        Write-Host "You may need to manually delete some resources before retrying." -ForegroundColor Yellow
        exit 1
    }
    
    if ($elapsed -gt $timeout) {
        Write-Host ""
        Write-Host "[ERROR] Timeout waiting for stack deletion ($timeout minutes)" -ForegroundColor Red
        Write-Host "  Current status: $stackStatus" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Cleanup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "All resources have been deleted." -ForegroundColor White
Write-Host ""