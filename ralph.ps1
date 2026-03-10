#requires -Version 5.1

param(
    [string]$Prompt = "prompt.md",
    [int]$Max = 50,
    [string]$Workdir = ".",
    [string]$Model = "gpt-5-mini",
    [string]$prdJson = "prd.json",
    [string]$CopilotArguments = "--yolo --no-ask-user --autopilot --allow-all-paths --allow-all-tools",
    [switch]$Force,
    [switch]$Debug
)

Write-Debug "[INIT] PowerShell version: $($PSVersionTable.PSVersion)"
Write-Debug "[INIT] Parameter values received:"
Write-Debug "  - Prompt: '$Prompt'"
Write-Debug "  - Max: $Max"
Write-Debug "  - Workdir: '$Workdir'"
Write-Debug "  - Model: '$Model'"
Write-Debug "  - prdJson: '$prdJson'"
Write-Debug "  - Force: $Force"

Set-StrictMode -Version Latest

# Clear console
try {
    Write-Debug "[INIT] Attempting to clear console"
    clear
    Write-Debug "[INIT] Console cleared successfully"
}
catch {
    Write-Debug "[INIT] Failed to clear console: $_"
}
if ($Debug) {
    $DebugPreference = "Continue"
}
Write-Debug "[INIT] Setting script-level variables"
$Script:Prompt = $Prompt
$Script:Max = $Max
$Script:Workdir = $Workdir
$Script:Model = $Model
$Script:prdJson = $prdJson
$Script:Force = $Force
$Script:CopilotArguments = "$CopilotArguments --add-dir $Workdir"

Write-Debug "[INIT] Script initialization complete. Script variables:"
Write-Debug "  - Script:Prompt: '$($Script:Prompt)'"
Write-Debug "  - Script:Max: $($Script:Max)"
Write-Debug "  - Script:Workdir: '$($Script:Workdir)'"
Write-Debug "  - Script:Model: '$($Script:Model)'"
Write-Debug "  - Script:prdJson: '$($Script:prdJson)'"
Write-Debug "  - Script:CopilotArguments: $($Script:CopilotArguments)"
Write-Debug "  - Script:Force: $($Script:Force)"

function Get-UserStorystatus {
    Write-Debug "[Get-UserStorystatus] Function called"
    $prdPath = $Script:prdPath
    Write-Debug "[Get-UserStorystatus] PRD Path: '$prdPath'"

    if (-not (Test-Path $prdPath)) {
        Write-Debug "[Get-UserStorystatus] PRD file not found at path"
        return @{
            Totalstories  = 0
            PassedStories = 0
            FailedStories = 0
            Stories       = @()
            AllComplete   = false 
        }
    }

    Write-Debug "[Get-UserStorystatus] PRD file exists, reading content"

    try {
        $prdData = Get-Content -Path $prdPath -Raw | ConvertFrom-Json
        Write-Host $prdData -ForegroundColor DarkGreen
        Write-Debug "[Get-UserStorystatus] Successfully parsed PRD JSON"
        Write-Debug "[Get-UserStorystatus] PRD Data: $($prdData | ConvertTo-Json)"
    }
    catch {
        Write-Debug "[Get-UserStorystatus] Failed to parse PRD JSON: $_"
        return @{
            Totalstories  = 0
            PassedStories = 0
            FailedStories = 0
            Stories       = @()
            AllComplete   = $false
        }
    }

    if (-not $prdData.userStories) {
        Write-Debug "[Get-UserStorystatus] No userStories found in PRD data"
        return @{
            TotalStories  = 0
            Passedstories = 0
            FailedStories = 0
            Stories       = @()
            AllComplete   = $false
        }
    }

    Write-Debug "[Get-UserStorystatus] Processing userStories. Count: $($prdData.userStories.Count)"

    $stories = @()
    $passed = 0
    $failed = 0
    
    Write-Debug "[Get-UserStorystatus] Starting story iteration loop"
    
    foreach ($story in $prdData.userStories) {
        Write-Debug "[Get-UserStorystatus] Processing story: Id=$($story.id), Title='$($story.title)'"
        
        $storyStatus = @{
            Id     = $story.id
            Title  = $story.title
            Passes = $story.passes -eq $true
        }
        Write-Debug "[Get-UserStorystatus] Story status: Passes=$($storyStatus.Passes)"
        
        $stories += $storyStatus

        if ($story.passes -eq $true) {
            $passed++
            Write-Debug "[Get-UserStorystatus] Story passed. Incrementing passed count to $passed"
        }
        else {
            $failed++
            Write-Debug "[Get-UserStorystatus] Story failed. Incrementing failed count to $failed"
        }
    }
    
    Write-Debug "[Get-UserStorystatus] Story iteration complete. Total stories: $($stories.Count), Passed: $passed, Failed: $failed"
    
    $totalStories = $stories.Count
    $allComplete = ($failed -eq 0 -and $totalStories -gt 0)
    
    Write-Debug "[Get-UserStorystatus] Returning result:"
    Write-Debug "  - TotalStories: $totalStories"
    Write-Debug "  - PassedStories: $passed"
    Write-Debug "  - FailedStories: $failed"
    Write-Debug "  - Stories Count: $($stories.Count)"
    Write-Debug "  - AllComplete: $allComplete"

    return @{
        Totalstories  = $totalStories
        PassedStories = $passed
        FailedStories = $failed
        Stories       = $stories
        AllComplete   = $allComplete
    }
}

function Test-AllTasksComplete {
    param(
        [string]$Workdir
    )
    
    Write-Debug "[Test-AllTasksComplete] Function called"
    $status = Get-UserStorystatus
    Write-Debug "[Test-AllTasksComplete] User story status: AllComplete=$($status.AllComplete), TotalStories=$($status.Totalstories)"
    return $status.AllComplete
}

function GetPromptText {
    Write-Debug "[GetPromptText] Function called"
    Write-Debug "[GetPromptText] Script:Prompt = '$($Script:Prompt)', Workdir = '$Workdir'"
    
    $promptPath = Join-Path -Path $Workdir -ChildPath [string]$Script:Prompt
    Write-Debug "[GetPromptText] Constructed prompt path: '$promptPath'"

    if (-not (Test-Path $promptPath)) {
        Write-Debug "[GetPromptText] Prompt file not found at '$promptPath', using inline prompt text"
        return [string]$Prompt
    }
    
    Write-Debug "[GetPromptText] Reading prompt from file: '$promptPath'"
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

    Write-Debug "[Show-ExecutionReport] Function called with parameters:"
    Write-Debug "  - TotalDuration: $($TotalDuration.ToString())"
    Write-Debug "  - TotalAttempts: $TotalAttempts"
    Write-Debug "  - SuccessfulAttempts: $SuccessfulAttempts"
    Write-Debug "  - FailedAttempts: $FailedAttempts"
    Write-Debug "  - AttemptTimings Count: $($AttemptTimings.Count)"
    Write-Debug "  - AllTasksComplete: $AllTasksComplete"
    Write-Debug "  - FinalExitCode: $FinalExitCode"
    Write-Debug "  - Model: '$Model'"
    Write-Debug "  - MaxAttempts: $MaxAttempts"

    Write-Host "`n" -NoNewline
    Write-Host "================================================================================================"
    Write-Host "====================================== EXECUTION REPORT ========================================"
    Write-Host "================================================================================================"
    
    # Overall Status
    Write-Host "`n[OVERALL STATUS]"
    if ($AllTasksComplete) {
        Write-Host "[SUCCESS] All user stories completed" -ForegroundColor Green
    }
    elseif ($TotalAttempts -ge $MaxAttempts) {
        Write-Host "[WARNING] Maximum attempts reached" -ForegroundColor Yellow
    }
    else {
        Write-Host "[ERROR] Execution stopped early" -ForegroundColor Red
    }
    
    Write-Host "  Exit Code: $FinalExitCode"

    # Execution Benchmarks
    Write-Debug "[Show-ExecutionReport] Calculating timing statistics"
    Write-Host "`n[EXECUTION BENCHMARKS]"
    Write-Host "  Total Duration: $($TotalDuration.Hours)h $($TotalDuration.Minutes)m $($TotalDuration.Seconds)s $($TotalDuration.Milliseconds)ms"
    Write-Debug "[Show-ExecutionReport] Total Duration: $($TotalDuration.TotalSeconds) seconds"
    Write-Host "  Total Attempts: $TotalAttempts / $MaxAttempts"
    Write-Debug "[Show-ExecutionReport] Attempts ratio: $TotalAttempts/$MaxAttempts"
    if ($SuccessfulAttempts -gt 0) {
        Write-Host "  Successful Attempts: $SuccessfulAttempts" -ForegroundColor Green
    }
    if ($FailedAttempts -gt 0) {
        Write-Host "  Failed Attempts: $FailedAttempts" -ForegroundColor Red
    }
    
    if ($TotalAttempts -gt 0) {
        $avgTime = [timespan]::FromMilliseconds(($AttemptTimings | Measure-Object -Average).Average)
        $minTime = [timespan]::FromMilliseconds(($AttemptTimings | Measure-Object -Minimum).Minimum)
        $maxTime = [timespan]::FromMilliseconds(($AttemptTimings |  Measure-Object -Maximum).Maximum)
        
        Write-Debug "[Show-ExecutionReport] Timing stats: Avg=$($avgTime.TotalSeconds)s, Min=$($minTime.TotalSeconds)s, Max=$($maxTime.TotalSeconds)s"
        Write-Host "  Average Attempt: $($avgTime.Minutes)m $($avgTime.Seconds)s $($avgTime.Milliseconds)ms"
        Write-Debug "[Show-ExecutionReport] Corrected average time format"
        Write-Host "  Fastest Attempt: $($minTime.Minutes)m $($minTime.Seconds)s $($minTime.Milliseconds)ms"
        Write-Host "  Slowest Attempt: $($maxTime.Minutes)m $($maxTime.Seconds)s $($maxTime.Milliseconds)ms"
    }

    # Model Configuration
    Write-Host "`n[CONFIGURATION]"
    Write-Host "  Model: $Model"
    Write-Host "  Working Directory: $absoluteWorkDir"

    # User Stories Status
    Write-Debug "[Show-ExecutionReport] Calling Get-UserStoryStatus"
    $storyStatus = Get-UserStoryStatus
    Write-Debug "[Show-ExecutionReport] Got user story status: Total=$($storyStatus.TotalStories), Passed=$($storyStatus.Passedstories), Failed=$($storyStatus.Failedstories)"
    Write-Host "`n[USER STORIES]"
    Write-Host "  Total Stories: $($storyStatus.TotalStories)"
    if ($storyStatus.PassedStories -gt 0) {
        Write-Host "  Passed: $($storyStatus.PassedStories)" -ForegroundColor Green
    }
    if ($storyStatus.FailedStories -gt 0) {
        Write-Host "  Failed: $($storyStatus.FailedStories)" -ForegroundColor Red
    }

    
    if ($storyStatus.TotalStories -gt 0) {
        $completionRate = [math]::Round(($storyStatus.PassedStories / $storyStatus.TotalStories) * 100, 2)
        Write-Host "  Completion Rate: $completionRate%"
        Write-Host "`n  Story Details:"
        foreach ($story in $storyStatus.Stories) {
            $statusIcon = if ($story.Passes) { "[PASS]" } else { "[FAIL]" }
            if ($story.Passes) {
                Write-Host "$statusIcon" -ForegroundColor Green
            } else {
                Write-Host "$statusIcon" -ForegroundColor Red
            }
            Write-Host "$($story.Id): $($story.Title)"
        }
    }
    Write-Host "`n================================================================================================"
    Write-Host ""
}

function Get-CopilotPath {
    [CmdletBinding()]
    param()

    $invalidPattern = "\\Code\\|vscode|visual studio code|intellij|jetbrains|pycharm|webstorm|rider|clion|goland"

    Write-Debug "Searching copilot command using where.exe"

    $paths = where.exe copilot 2>$null

    if (-not $paths) {
        Write-Debug "No copilot command returned by where.exe"
    }

    foreach ($p in $paths) {
        Write-Debug "Candidate path detected: $p"

        if ($p -match $invalidPattern) {
            Write-Debug "Rejected path (IDE plugin detected): $p"
            continue
        }

        Write-Debug "Accepted copilot path: $p"
        return $p
    }

    Write-Debug "No valid copilot command found after filtering"
    Write-Error "No valid Copilot command found outside IDE plugin paths."
    Write-Error "Please install GitHub Copilot CLI:"
    Write-Error "  > npm install -g @github/copilot"
    exit 1
}

function Main {
    Write-Debug "[Main] Function called"
    Write-Debug "[Main] Starting main function execution"

    Write-Host ""
    Write-Host "  _____       _       _        _____            _ _       _   "
    Write-Host " |  __ \     | |     | |      / ____|          (_) |     | |  "
    Write-Host " | |__) |__ _| |_ __ | |__   | |     ___  _ __  _| | ___ | |_ "
    Write-Host " |  _  // _` | | '_ \| '_ \ | |    / _ \| '_ \| | |/ _ \| __|"
    Write-Host " | | \ \ (_| | | |_) | | | | | |___| (_) | |_) | | | (_) | |_ "
    Write-Host " |_|  \_\__,_|_| .__/|_| |_|  \_____\___/| .__/|_|_|\___/ \__|"
    Write-Host "               | |                       | |                  "
    Write-Host "               |_|                       |_|                  "
    Write-Host ""

    Write-Host "================================================================================================"

    # Validate current directory
    Write-Debug "[Main] Validating working directory"
    $absoluteWorkdir = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $Workdir))
    Write-Debug "[Main] Absolute working directory: '$absoluteWorkdir'"
    
    if (-not (Test-Path -Path $absoluteWorkdir)) {
        Write-Host "[ERROR] Workdir path not found at '$absoluteWorkdir'" -ForegroundColor Red
        Write-Debug "[Main] Working directory validation FAILED"
        exit 1
    }
    
    Write-Host "[INFO] Changed working directory to: $absoluteWorkdir"
    Set-Location -Path $absoluteWorkdir
    Write-Debug "[Main] Current location set successfully"

    # Initialize variables
    Write-Debug "[Main] Getting Copilot path"

    try {
        $Script:copilotCmd = Get-CopilotPath
        Write-Host "[SUCCESS] GitHub Copilot CLI found at:" -ForegroundColor Green
        Write-Host "       $($Script:copilotCmd)"
        Write-Debug "[Main] Copilot command path: '$($Script:copilotCmd)'"
    }
    catch {
        Write-Host "[ERROR] Failed to locate GitHub Copilot CLI" -ForegroundColor Red
        Write-Host "[INFO] Please install with: npm install -g @github/copilot"
        exit 1
    }
    
    if (-not [string]::IsNullOrEmpty($Script:Model)) {
        Write-Host "[INFO] AI Model configured:"
        Write-Host "         $Script:Model"
        Write-Debug "[Main] Model configured: '$($Script:Model)'"
    }
    
    # Validate prd.json
    Write-Debug "[Main] Validating PRD JSON path"
    $Script:prdPath = Join-Path -Path $absoluteWorkdir -ChildPath $Script:prdJson
    Write-Debug "[Main] PRD path constructed: '$($Script:prdPath)'"
    
    if (-not (Test-Path -Path $Script:prdPath)) {
        Write-Host "[ERROR] PRD JSON file not found at '$($Script:prdPath)'" -ForegroundColor Red
        Write-Debug "[Main] PRD JSON validation FAILED - file not found"
        exit 1
    }
    
    Write-Host "[INFO] PRD JSON file:"
    Write-Host "       $($Script:prdPath)"
    Write-Debug "[Main] PRD JSON validation PASSED - file exists"

    # Ensure progress state files exist, if not create them
    Write-Debug "[Main] Setting up progress state files"
    $progressStatePath = Join-Path -Path $absoluteWorkdir -ChildPath "progress.txt"
    Write-Host "[INFO] Progress tracking file:"
    
    if ($Force) {
        Write-Debug "[Main] Force flag set, resetting progress state"
        Try {
            Remove-Item -Path $progressStatePath -Force -ErrorAction SilentlyContinue
            Write-Debug "[Main] Removed existing progress state file"
            New-Item -Path $progressStatePath -ItemType File -Force | Out-Null
            Write-Host "[WARNING] Progress tracking reset due to -Force flag" -ForegroundColor Yellow
            Write-Debug "[Main] Created new empty progress state file"
        }
        catch {
            Write-Host "[ERROR] Failed to reset progress state: $_" -ForegroundColor Red
            Write-Debug "[Main] Failed to reset progress state: $_"
            exit 1
        }
    }
    else {
        Write-Debug "[Main] Force flag not set, checking for existing progress state"
        Try {
            if (-not (Test-Path -Path $progressStatePath)) {
                New-Item -Path $progressStatePath -ItemType File -Force | Out-Null
                Write-Host "[SUCCESS] Progress tracking file created" -ForegroundColor Green
                Write-Debug "[Main] Created new progress state file"
            }
            else {
                Write-Debug "[Main] Progress state file already exists"
            }
        }
        catch {
            Write-Host "[ERROR] Failed to create state files: $_" -ForegroundColor Red
            Write-Debug "[Main] Failed to create state files: $_"
            exit 1
        }
    }

    # Set Copilot Prompt for use in the main loop
    Write-Debug "[Main] Setting Copilot prompt"
    
    try {
        $Script:copilotPrompt = GetPromptText
        Write-Host "[SUCCESS] Copilot prompt loaded successfully" -ForegroundColor Green
        if ($Script:copilotPrompt.Length -gt 60) {
            Write-Host "       Prompt preview: $($Script:copilotPrompt.Substring(0, 57))..."
        }
        else {
            Write-Host "       Prompt: $($Script:copilotPrompt)"
        }
        Write-Debug "[Main] Copilot prompt set successfully: '$($Script:copilotPrompt)'"
    }
    catch {
        Write-Host "[ERROR] Failed to set Copilot Prompt: $_" -ForegroundColor Red
        Write-Debug "[Main] Failed to set Copilot prompt: $_"
        exit 1
    }

    # Initialize execution tracking variables
    Write-Debug "[Main] Initializing execution tracking variables"
    $executionStartTime = Get-Date
    Write-Host "[INFO] Starting Ralph execution with $($Script:Max) maximum attempts"
    Write-Debug "[Main] Execution start time recorded: $($executionStartTime)"
    $returnCode = 0
    $returnErrorCodeCounter = 0
    $attempt = 0
    $successfulAttempts = 0
    $attemptTimings = @()
    Write-Debug "[Main] Tracking variables initialized. Max attempts: $($Script:Max)"

    # Main loop to interact with Copilot
    Write-Debug "[Main] Entering main execution loop"
    while ($attempt -lt $Script:Max) {
        Write-Debug "[Main] Loop condition check: attempt=$attempt, max=$($Script:Max)"
        
        $attempt++
        $progressPercent = [math]::Round(($attempt / $Script:Max) * 100)
        
        Write-Host ""
        Write-Host "================================================================================================"
        Write-Host "[ATTEMPT #$attempt / $($Script:Max)] ($progressPercent%)"
        Write-Host "--------------------------------------------------------------------------------------------"
        
        $attemptStartTime = Get-Date
        Write-Debug "[Main] Attempt start time recorded: $($attemptStartTime)"
        
        # Build argument array for this attempt
        Write-Debug "[Main] Building argument list for Copilot execution"
        $extraArgs = if ($Script:CopilotArguments) { $Script:CopilotArguments -split ' ' } else { @() }
        Write-Debug "[Main] Extra args: $($extraArgs -join ', ')"
        
        $argList = @('-p', $Script:copilotPrompt, '--model', $Script:Model) + $extraArgs
        Write-Debug "[Main] Full argument list: $($argList -join ' ')"

        # Execute Copilot command and capture output and errors
        try {
            Write-Host "[INFO] Executing Copilot with model '$($Script:Model)'"
            Write-Host "[INFO] Command line "
            Write-Host "    $Script:copilotCmd $($argList -join ' ')"
            & $Script:copilotCmd @argList
            $returnCode = $LASTEXITCODE
            
            if ($returnCode -eq 0) {
                Write-Host "[SUCCESS] Attempt #$attempt completed successfully" -ForegroundColor Green
                Write-Debug "[Main] Copilot command executed successfully, exit code: $returnCode"
                $successfulAttempts++
            }
            else {
                Write-Host "[WARNING] Attempt #$attempt failed with exit code: $returnCode" -ForegroundColor Yellow
                Write-Debug "[Main] Copilot command failed with exit code: $returnCode"
            }
        }
        catch {
            Write-Host "[ERROR] Failed to execute Copilot command: $_" -ForegroundColor Red
            Write-Debug "[Main] Exception during Copilot execution: $_"
            $returnCode = 1
        }

        # Track attempt timming
        $attemptEndTime = Get-Date
        $attemptDuration = [math]::Round(($attemptEndTime - $attemptStartTime).TotalMilliseconds)
    
        if ($attemptDuration -lt 1000) {
            Write-Host "[INFO] Attempt duration: ${attemptDuration}ms"
        }
        else {
            Write-Host "[INFO] Attempt duration: $([math]::Round($attemptDuration / 1000, 2))s"
        }
    
        if ($returnCode -eq 0) {
            Write-Debug "[Main] Return code 0, incrementing successful attempts count to $successfulAttempts"
        }
        else {
            $returnErrorCodeCounter++
            Write-Host "[WARNING] Error counter incremented to: $returnErrorCodeCounter" -ForegroundColor Yellow
            Write-Debug "[Main] Non-zero exit code ($returnCode), incrementing error counter to $returnErrorCodeCounter"
        }

        # Check if all tasks are complete
        if (Test-AllTasksComplete -Workdir $absoluteWorkdir) {
            Write-Host ""
            Write-Host "[SUCCESS] All user stories completed! Exiting main loop." -ForegroundColor Green
            break
        }
        
        # Show remaining attempts info
        $remaining = $Script:Max - $attempt
        if ($remaining -gt 0) {
            Write-Host "[INFO] Remaining attempts: $remaining"
        }
        
        Write-Debug "[Main] Loop iteration $attempt completed, continuing to next iteration"
        Start-Sleep -Seconds 10
    }

    # Calculate execution metrics
    $executionEndTime = Get-Date
    $totalDuration = [math]::Round(($executionEndTime - $executionStartTime).TotalSeconds)
    
    Write-Host ""
    Write-Host "================================================================================================"
    Write-Host "[EXECUTION COMPLETE]"
    Write-Host "------------------------------------------------------------------------------------------------"
    
    Write-Debug "[Main] Execution end time recorded: $($executionEndTime)"
    Write-Debug "[Main] Total duration calculated: $totalDuration seconds"
    Write-Debug "[Main] Successful attempts calculation: $successfulAttempts"
    
    Write-Host "Total Attempts:"
    Write-Host "  Executed:     $attempt"
    if ($successfulAttempts -gt 0) {
        Write-Host "  Successful:   $successfulAttempts" -ForegroundColor Green
    }
    if ($returnErrorCodeCounter -gt 0) {
        Write-Host "  Failed:       $returnErrorCodeCounter" -ForegroundColor Red
    }
    Write-Host ""
    
    if ($totalDuration -lt 60) {
        Write-Host "Total Duration:"
        Write-Host "  $totalDuration seconds"
    }
    else {
        $minutes = [math]::Floor($totalDuration / 60)
        $seconds = $totalDuration % 60
        Write-Host "Total Duration:"
        Write-Host "  $minutes min $seconds sec"
    }
    
    $allTasksComplete = Test-AllTasksComplete -Workdir $absoluteWorkdir
    
    Write-Debug "[Main] Final tasks completion status: $allTasksComplete"

    # Display comprehensive execution report
    Write-Host ""
    Write-Debug "[Main] Calling Show-ExecutionReport to display results"
    
    if ($allTasksComplete) {
        Write-Host "[SUCCESS] All user stories completed!" -ForegroundColor Green
    }
    elseif ($returnErrorCodeCounter -ge $Script:Max) {
        Write-Host "[WARNING] Maximum attempts reached" -ForegroundColor Yellow
    }
    else {
        Write-Host "[ERROR] Execution stopped early" -ForegroundColor Red
    }
    
    Show-ExecutionReport `
        -TotalDuration (New-TimeSpan -Seconds $totalDuration) `
        -TotalAttempts $attempt `
        -SuccessfulAttempts $successfulAttempts `
        -FailedAttempts $returnErrorCodeCounter `
        -AttemptTimings $attemptTimings `
        -AllTasksComplete $allTasksComplete `
        -FinalExitCode $returnCode `
        -Model $Script:Model `
        -MaxAttempts $Script:Max

    Write-Host ""
    Write-Host "================================================================================================"
    Write-Debug "[Main] Execution report displayed, exiting with code 0"
    exit 0
}

Main