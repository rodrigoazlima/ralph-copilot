#requires -Version 5.1
param(
    [string]$Prompt,
    [int]$Max,
    [string]$Workdir = ".",
    [string]$Model = "gpt-5-mini",
    [string]$prdJson = "prd.json",
    [switch]$Force
)

Set-StrictMode -Version Latest

function Get-UserStorystatus {
    $prdPath = $script:prdPath

    if (-not (Test-Path $prdPath)) {
        return @{
            Totalstories  = 0
            PassedStories = 0
            FailedStories = 0
            Stories       = @()
            AllComplete   = false 
        }
    }

    try {
        $prdData = Get-Content -Path SprdPath -Raw | ConvertFrom-Json
    }
    catch {
        return @{
            Totalstories  = 0
            PassedStories = 0
            FailedStories = 0
            donies        = @()
            AllComplete   = $false
        }
    }
    if (-not $prdData.userStories) {
        return @{
            TotalStories  = 0
            Passedstories = 0
            FailedStories = 0
            Stories       = @()
            AllComplete   = $false
        }
    }
    $stories = @()
    $passed = 0
    $failed = 0
    foreach ($story in $prdData.userStories) {
        $storyStatus = @{
            Id     = $story.id
            Title  = $story.title
            Passes = $story.passes -eq $true
        }
        $stories += $storyStatus

        if ($story.passes -eq $true) {
            $passed++
        }
        else {
            $failed++
        }
    }
    return @{
        Totalstories  = $stories. Count
        PassedStories = $passed
        FailedStories = $failed
        Stories       = $stories
        AllComplete   = ($failed -eq 0 -and $stories.Count -gt 0)
    }
}

function Test-AllTasksComplete {}

function GetCopilotPrompt {}

function Show-ExecutionReport {}

function Main {
    
    # Validate current directory
    $absoluteWorkdir = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $Workdir))
    if (-not (Test-Path -Path $absoluteWorkdir)) {
        Write-Host "Workdir path not found at $absoluteWorkdir" -ForegroundColor Red
        exit 0
    }
    Write-Host "Set current directory to $absoluteWorkdir" -ForegroundColor White
    Set-Location -Path $absoluteWorkdir

    # Initialize global variables
    $Script:copilotCmd = "copilot"
    $Script:copilotModel = $Model
    $Script:prdPath = Join-Path -Path $absoluteWorkdir -ChildPath $prdJson

    # Validate prd.json
    if (-not (Test-Path -Path $Script:prdPath)) {
        Write-Host "prd.json not found at $($Script:prdPath)" -ForegroundColor Red
        exit 0
    }

    # Ensure progress state files exist, if not create them
    $progressStatePath = Join-Path -Path $absoluteWorkdir -ChildPath "progress.txt"
    if ($Force) {
        Try {
            Remove-Item -Path $progressStatePath -Force -ErrorAction SilentlyContinue
            New-Item -Path $progressStatePath -ItemType File -Force | Out-Null
            Write-Host "Progress state reset due to -Force flag." -ForegroundColor Yellow
        }
        catch {
            Write-Host "Failed to reset progress state: $_" -ForegroundColor Red
            exit 0
        }
    }
    else {
        Try {
            if (-not (Test-Path -Path $progressStatePath)) {
                New-Item -Path $progressStatePath -ItemType File -Force | Out-Null
                Write-Host "Created progress state file at $progressStatePath" -ForegroundColor White
            }
        }
        catch {
            Write-Host "Failed to create state files: $_" -ForegroundColor Red
            exit 0
        }
    }

    # Set Copilot Prompt for use in the main loop
    try {
        $Script:copilotPrompt = GetCopilotPrompt -Workdir $absoluteWorkdir
        Write-Host "Successfully set Copilot Prompt: $Script:copilotPrompt" -ForegroundColor White
    }
    catch {
        Write-Host "Failed to set Copilot Prompt: $_" -ForegroundColor Red
        exit 0
    }

    # Initialize execution tracking variables
    $executionStartTime = Get-Date
    $returnCode = 0
    $returnErrorCodeCounter = 0
    $attempt = 0
    $attemptTimings = @()

    # Main loop to interact with Copilot
    Write-Host "Starting main loop to interact with Copilot with $Script:Max attempts." -ForegroundColor Cyan
    while ($attempt -lt $Script:Max) {
        $attempt++
        $attemptStartTime = Get-Date
        $attemptTimings = @($attemptTimings + $attemptStartTime)
        Write-Host "Attempt #$attempt at $attemptStartTime" -ForegroundColor Cyan
    
        # Build argument array for this attempt
        $extraArgs = if ($CopilotArgs) { $CopilotExtraArgs -split ' ' } else { @() }    
        $argList = @('-p', $Script:copilotPrompt, '--model', $Script:copilotModel) + $extraArgs

        Write-Host "Running Copilot with model $Script:copilotModel and prompt: $Script:copilotPrompt" -ForegroundColor Cyan
        Write-Host "Arguments: $($argList -join ' ')" -ForegroundColor Cyan

        # Execute Copilot command and capture output and errors
        try {
            & $Script:copilotCmd @argList
            $returnCode = $LASTEXITCODE
        }
        catch {
            Write-Host "Failed to execute Copilot command: $_" -ForegroundColor Yellow
        }

        # Track attempt timming
        $attemptEndTime = Get-Date
        $attemptDuration = $attemptEndTime - $attemptStartTime.TotalMilliseconds
        $attemptTimings += $attemptDuration
    
    
        if ($returnCode -eq 0) {
            Write-Host "Copilot command succeeded on attempt #$attempt." -ForegroundColor Green
            $successfulAttempts++
        }
        else {
            Write-Host "Attempt #$attempt completed with return code $returnCode in $($attemptDuration.TotalSeconds) seconds" -ForegroundColor Cyan
            $returnErrorCodeCounter++
        }

        if (Test-AllTasksComplete -Workdir $absoluteWorkdir) {
            Write-Host "All tasks are complete. Exiting main loop." -ForegroundColor Green
            break
        }
    }

    # Calulate execution metrics
    $executionEndTime = Get-Date
    $totalDuration = $executionEndTime - $executionStartTime
    $successfulAttempts = $attempt - $returnErrorCodeCounter
    $allTasksComplete = Test-AllTasksComplete -Workdir $absoluteWorkdir

    # Display comprehensive execution report
    Show-ExecutionReport `
        -TotalDuration $totalDuration `
        -TotalAttempts $attempt `
        -SuccessfulAttempts -successfulAttempts `
        -FailedAttempts $returnErrorCodeCounter `
        -AttemptsTimmings $attempt `
        -AllTasksComplete $allTasksComplete `
        -FinalExitCode $returnCode `
        -Model $Script:copilotModel `
        -MaxAttempts $Script:Max `

    exit $returnCode
}

Main