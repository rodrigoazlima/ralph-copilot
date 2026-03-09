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

# Clear console
try {
    clear
}
catch {}

$Script:Prompt = $Prompt
$Script:Max = $Max
$Script:Workdir = $Workdir
$Script:Model = $Model
$Script:prdJson = $prdJson
$Script:Force = $Force

function Get-UserStorystatus {
    $prdPath = $Script:prdPath

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
        $prdData = Get-Content -Path $prdPath -Raw | ConvertFrom-Json
        Write-Host $prdData -ForegroundColor DarkGreen
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

function Test-AllTasksComplete {
    return (Get-UserStorystatus).AllComplete
}

function GetPromptText {
    Write-Host "Loading prompt $Script:Prompt" -ForegroundColor White
    $promptPath = Join-Path -Path $Workdir -ChildPath [string]$Script:Prompt
    if (-not (Test-Path $promptPath)) {
        Write-Host "Using prompt: " -ForegroundColor White
        return [string]$Prompt
    }
    return Get-Content -Path $Script:prdPath -Raw
}

function Show-ExecutionReport {
    param(
        [TimeSpan]$TotalDuration,
        [int]$TotalAttempts,
        [int]$SuccessfulAttempts,
        [int]$FailedAttempts,
        [array]$AttemptTimings,
        [bool]$AllTasksComplete,
        [int]$FinalExitCode,
        [string]$Model,
        [int]$MaxAttempts
    )

    Write-Host "`n" -NoNewline
    Write-Host "================================================================================================" -ForegroundColor Cyan
    Write-Host "====================================== EXECUTION REPORT ========================================" -ForegroundColor Cyan
    Write-Host "================================================================================================" -ForegroundColor Cyan
    
    # Overall Status
    Write-Host "`n[OVERALL STATUS]" -ForegroundColor Cyan
    Write-Host "    Status:" -ForegroundColor Cyan
    if ($AllTasksComplete) {
        Write-Host "SUCCESS - All user stories completed" -ForegroundColor Cyan
    }
    elseif ($TotalAttempts -ge $MaxAttempts) {
        Write-Host "INCOMPLETE - Maximum attempts reached" -ForegroundColor Yellow
    }
    else {
        Write-Host "FAILED - Execution stopped early" -ForegroundColor Red
    }
    
    Write-Host "  Exit Code: $FinalExitCode" -ForegroundColor White

    # Execution Benchmarks
    Write-Host "`n[EXECUTION BENCHMARKS]" - ForegroundColor White
    Write-Host "  Total Duration: $($TotalDuration.Hours)h $($TotalDuration.Minutes)m $($TotalDuration.Seconds)s $($TotalDuration.Milliseconds)ms" -ForegroundColor Gray
    Write-Host "  Total Attempts: $TotalAttempts / $MaxAttempts" -ForegroundColor Gray
    Write-Host "  Successful Attempts: $SuccessfulAttempts" -ForegroundColor $(if ($SuccessfulAttempts -gt 0) { 'Green' } else { 'Gray' })
    Write-Host "  Failed Attempts: $FailedAttempts" -ForegroundColor $(if ($FailedAttempts -gt 0) { 'Red' } else { 'Gray' })
    if ($TotalAttempts -gt 0) {
        $avgTime = [timespan]::FromMilliseconds(($AttemptTimings | Measure-Object -Average).Average)
        $minTime = [timespan]::FromMilliseconds(($AttemptTimings | Measure-Object -Minimum).Minimum)
        $maxTime = [timespan]::FromMilliseconds(($AttemptTimings |  Measure-Object -Maximum).Maximum)
        Write-Host "  Average Attempt: $(SavgTime.Minutes)m $(SavgTime.Seconds)s $($avgTime.Milliseconds)ms" -ForegroundColor Gray
        Write-Host "  Fastest Attempt: $($minTime.Minutes)m $($minTime.Seconds)s $($minTime.Milliseconds)ms" -ForegroundColor Gray
        Write-Host "  Slowest Attempt: $($maxTime.Minutes)m $($maxTime.Seconds)s $($maxTime.Milliseconds)ms" -ForegroundColor Gray
    }

    # Model Configuration
    Write-Host "`n[CONFIGURATION]" -ForegroundColor White 
    Write-Host "  Model: $Model" -ForegroundColor Gray
    Write-Host "  Working Directory: $absoluteWorkDir" -ForegroundColor Gray

    # User Stories Status
    $storyStatus = Get-UserStoryStatus
    Write-Host "`n[USER STORIES]" -ForegroundColor White 
    Write-Host "  Total Stories: $($storyStatus.TotalStories)" -ForegroundColor Gray
    Write-Host "  Passed: $($storyStatus. PassedStories)" -ForegroundColor Green
    Write-Host "  Failed: $($storyStatus.FailedStories)" -ForegroundColor $(if ($storyStatus. FailedStories -gt 0) { 'Red' } else { 'Gray' })

    
    if ($storyStatus.TotalStories -gt 0) {
        $completionRate = [math]::Round(($storyStatus.PassedStories / $storyStatus.TotalStories) * 100, 2)
        Write-Host "  Completion Rate: $completionRate%" -ForegroundColor $(if ($completionRate -eq 100) { 'Green' } elseif ($completionRate -gt 50) { 'Yellow' } else { 'Red' })
        Write-Host "`n  Story Details:" -ForegroundColor Gray
        foreach ($story in $storyStatus.Stories) {
            $statusIcon = if ($story.Passes) { "[PASS]" } else { "[FAIL]" }
            $statusColor = if ($story.Passes) { 'Green' } else { 'Red' }
            Write-Host "$statusIcon"-NoNewline -ForegroundColor $statusColor
            Write-Host "$($story.Id); $($story.Title)" -ForegroundColor Gray
        }
    }
    Write-Host "`n================================================================================================" -ForegroundColor Cyan
    Write-Host ""
}
function ValidateCopilotExecutable {
    $invalidPattern = "vscode|visual studio code|intellij|jetbrains|pycharm|webstorm|rider|clion|goland"

    $copilotPaths = Get-ChildItem "$env:LOCALAPPDATA", "$env:PROGRAMFILES", "$env:PROGRAMFILES(x86)" -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "copilot" } |
    Select-Object -ExpandProperty FullName

    foreach ($path in $copilotPaths) {
        if ($path -match $invalidPattern) {
            Write-Error "Copilot installation detected inside an unsupported IDE path: $path"
            exit 1
        }
    }

    Write-Output "Copilot paths are acceptable."
}

function Main {
    # Validate current directory
    $absoluteWorkdir = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $Workdir))
    if (-not (Test-Path -Path $absoluteWorkdir)) {
        Write-Host "Workdir path not found at $absoluteWorkdir" -ForegroundColor Red
        exit 1
    }
    Write-Host "Set current directory to $absoluteWorkdir" -ForegroundColor White
    Set-Location -Path $absoluteWorkdir

    # Initialize global variables
    ValidateCopilotExecutable
    $cmd = Get-Command copilot -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host "ERROR: copilot executable not found" -ForegroundColor Red
        Write-Host "Please install GitHub Copilot CLI:" -ForegroundColor Yellow
        Write-Host "  npm install -g @github/copilot" -ForegroundColor Yellow
        exit 1
    }
    $Script:copilotModel = $Script:Model
    $Script:prdPath = Join-Path -Path $absoluteWorkdir -ChildPath $Script:prdJson

    # Validate prd.json
    if (-not (Test-Path -Path $Script:prdPath)) {
        Write-Host "prd.json not found at $($Script:prdPath)" -ForegroundColor Red
        exit 1
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
            exit 1
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
            exit 1
        }
    }

    # Set Copilot Prompt for use in the main loop
    try {
        $Script:copilotPrompt = GetPromptText
        Write-Host "Successfully set Copilot Prompt: $Script:copilotPrompt" -ForegroundColor White
    }
    catch {
        Write-Host "Failed to set Copilot Prompt: $_" -ForegroundColor Red
        exit 1
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
        -SuccessfulAttempts $successfulAttempts `
        -FailedAttempts $returnErrorCodeCounter `
        -AttemptTimings $attemptTimings `
        -AllTasksComplete $allTasksComplete `
        -FinalExitCode $returnCode `
        -Model $Script:copilotModel `
        -MaxAttempts $Script:Max

    exit 0
}

Main