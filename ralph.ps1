#!/usr/bin/env pwsh

param(
    [string]$Prompt = "prompt.md",
    [int]$Max = 50,
    [string]$Workdir = ".",
    [string]$Model = "gpt-5-mini",
    [string]$prdJson = "prd.json",
    [string]$CopilotArguments = "--yolo --no-ask-user --autopilot --allow-all-paths --allow-all-tools",
    [switch]$Force,
    [switch]$Debug,
    [string]$LogFile = "ralph.log"
)

# Logging configuration
$Script:LogFilePath = $LogFile

# Log function for centralized logging
function Log {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Message,

        [ValidateSet('Info', 'Warn', 'Error', 'Fatal', 'Success')]
        [string]$Level = 'Info',

        [int]$stack = 1
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $caller = (Get-PSCallStack)[$stack]  # [0] = this function, [1] = who called us

    $function = if ($caller) { $caller.FunctionName } else { '<Script>' }
    $line = if ($caller) { $caller.ScriptLineNumber } else { '?' }

    $prefix = switch ($Level) {
        'Info' { 'INFO ' }
        'Success' { 'INFO' }
        'Warn' { 'WARN ' }
        'Error' { 'ERROR' }
        'Fatal' { 'FATAL' }
        default { '     ' }
    }

    $color = switch ($Level) {
        'Info' { 'White' }
        'Success' { 'Green' }
        'Warn' { 'Yellow' }
        'Error' { 'Red' }
        'Fatal' { 'Magenta' }
        default { 'Cyan' }
    }
    $consolePrefix = "$timestamp [$prefix] $($function):$($line) - "
    Add-Content -Path $LogFile -Value "$consolePrefix$Message"
    Write-Host $consolePrefix -ForegroundColor $Color -NoNewline
    Write-Host $Message -ForegroundColor $color
}

function logInfo($msg, $l = 'Info') { Log $msg -Level $l -stack 2 }
function LogSuccess($msg, $l = 'Success') { Log $msg -Level $l -stack 2 }
function LogDebug($msg, $l = 'Debug') { 
    Write-Debug $msg 
    Add-Content -Path $Script:LogFilePath  -Value "$msg"
    
}
function LogError($msg, $l = 'Error') { Log $msg -Level $l -stack 2 }
function LogWarn($msg, $l = 'Warn') { Log $msg -Level $l -stack 2 }
function LogFatal($msg, $l = 'Fatal') { Log $msg -Level $l -stack 2 }

LogDebug "PowerShell version: $($PSVersionTable.PSVersion)" -Debug
LogDebug "Parameter values received:" -Debug 
LogDebug "  - Prompt: '$Prompt'" -Debug 
LogDebug "  - Max: $Max" -Debug 
LogDebug "  - Workdir: '$Workdir'" -Debug 
LogDebug "  - Model: '$Model'" -Debug 
LogDebug "  - prdJson: '$prdJson'" -Debug 
LogDebug "  - Force: $Force" -Debug 

# Clear console
try {
    LogDebug "Attempting to clear console"
    clear
    LogDebug "Console cleared successfully"
}
catch {
    LogDebug "Failed to clear console: $_"
}
if ($Debug) {
    $DebugPreference = "Continue"
}
LogDebug "Setting script-level variables"
$Script:Prompt = $Prompt
$Script:Max = $Max
$Script:Workdir = $Workdir
$Script:Model = $Model
$Script:prdJson = $prdJson
$Script:Force = $Force
$Script:CopilotArguments = "$CopilotArguments --add-dir $Workdir"

LogDebug "Script initialization complete. Script-level variables:"
LogDebug "  - Script:Prompt: '$($Script:Prompt)'"
LogDebug "  - Script:Max: $($Script:Max)"
LogDebug "  - Script:Workdir: '$($Script:Workdir)'"
LogDebug "  - Script:Model: '$($Script:Model)'"
LogDebug "  - Script:prdJson: '$($Script:prdJson)'"
LogDebug "  - Script:CopilotArguments: $($Script:CopilotArguments)"
LogDebug "  - Script:Force: $($Script:Force)"

function Get-UserStorystatus {
    LogDebug "Function called"
    $prdPath = $Script:prdPath
    LogDebug "PRD Path: '$prdPath'"

    if (-not (Test-Path $prdPath)) {
        LogDebug "PRD file not found at path"
        return @{
            TotalStories  = 0
            PassedStories = 0
            FailedStories = 0
            Stories       = @()
            AllComplete   = $false
        }
    }

    LogDebug "PRD file exists, reading content"

    try {
        $prdData = Get-Content -Path $prdPath -Raw | ConvertFrom-Json
        Log "$prdData"  -Color DarkGreen
        LogDebug "Successfully parsed PRD JSON"
        LogDebug "PRD Data: $($prdData | ConvertTo-Json)"
    }
    catch {
        LogDebug "Failed to parse PRD JSON: $_"
        return @{
            TotalStories  = 0
            PassedStories = 0
            FailedStories = 0
            Stories       = @()
            AllComplete   = $false
        }
    }

    if (-not $prdData.userStories) {
        LogDebug "No userStories found in PRD data"
        return @{
            TotalStories  = 0
            PassedStories = 0
            FailedStories = 0
            Stories       = @()
            AllComplete   = $false
        }
    }

    LogDebug "Processing userStories. Count: $($prdData.userStories.Count)"

    $stories = @()
    $passed = 0
    $failed = 0
    
    LogDebug "Starting story iteration loop"
    
    foreach ($story in $prdData.userStories) {
        LogDebug "Processing story: Id=$($story.id), Title='$($story.title)'"
        
        $storyStatus = @{
            Id     = $story.id
            Title  = $story.title
            Passes = $story.passes -eq $true
        }
        LogDebug "Story status: Passes=$($storyStatus.Passes)"
        
        $stories += $storyStatus

        if ($story.passes -eq $true) {
            $passed++
            LogDebug "Story passed. Incrementing passed count to $passed"
        }
        else {
            $failed++
            LogDebug "Story failed. Incrementing failed count to $failed"
        }
    }
    
    LogDebug "Story iteration complete. Total stories: $($stories.Count), Passed: $passed, Failed: $failed"
    
    $totalStories = $stories.Count
    $allComplete = ($failed -eq 0 -and $totalStories -gt 0)
    
    LogDebug "Returning result:"
    LogDebug "  - TotalStories: $totalStories"
    LogDebug "  - PassedStories: $passed"
    LogDebug "  - FailedStories: $failed"
    LogDebug "  - Stories Count: $($stories.Count)"
    LogDebug "  - AllComplete: $allComplete"

    return @{
        TotalStories  = $totalStories
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
    
    LogDebug "Function called"
    $status = Get-UserStorystatus
    LogDebug "User story status: AllComplete=$($status.AllComplete), TotalStories=$($status.TotalStories)"
    return $status.AllComplete
}

function GetPromptText {
    LogDebug "Function called"
    LogDebug "Script:Prompt = '$($Script:Prompt)', Workdir = '$Workdir'"
    
    $promptPath = Join-Path -Path $Workdir -ChildPath [string]$Script:Prompt
    LogDebug "Constructed prompt path: '$promptPath'"

    if (-not (Test-Path $promptPath)) {
        LogDebug "Prompt file not found at '$promptPath', using inline prompt text"
        return [string]$Script:Prompt
    }
    
    LogDebug "Reading prompt from file: '$promptPath'"
    return Get-Content -Path $promptPath -Raw
}

# Color constants for logging
$Script:ColorInfo = [ConsoleColor]::Cyan
$Script:ColorSuccess = [ConsoleColor]::Green
$Script:ColorWarning = [ConsoleColor]::Yellow
$Script:ColorError = [ConsoleColor]::Red

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

    LogDebug "Function called"
    LogDebug "SuccessfulAttempts: $SuccessfulAttempts"
    LogDebug "FailedAttempts: $FailedAttempts"
    LogDebug "AttemptTimings Count: $($AttemptTimings.Count)"
    LogDebug "AllTasksComplete: $AllTasksComplete"
    LogDebug "FinalExitCode: $FinalExitCode"
    LogDebug "Model: '$Model'"
    LogDebug "MaxAttempts: $MaxAttempts"

    Log "" 
    Log "================================================================================================" 
    Log "====================================== EXECUTION REPORT =======================================" 
    Log "================================================================================================" 
    
    # Overall Status
    Log "" 
    Log "====================================== EXECUTION REPORT =======================================" 
    Log "================================================================================================" 
    
    Log "OVERALL STATUS" 
    if ($AllTasksComplete) {
        LogSuccess "All user stories completed" 
    }
    elseif ($TotalAttempts -ge $MaxAttempts) {
        LogWarn "Maximum attempts reached" 
    }
    else {
        LogError "Execution stopped early" 
    }
    
    Log "  Exit Code: $FinalExitCode" 

    # Execution Benchmarks
    Log "EXECUTION BENCHMARKS" 
    Log "  Total Duration: $($TotalDuration.Hours)h $($TotalDuration.Minutes)m $($TotalDuration.Seconds)s $($TotalDuration.Milliseconds)ms" 
    Log "  Total Attempts: $TotalAttempts / $MaxAttempts" 
    if ($SuccessfulAttempts -gt 0) {
        LogSuccess "  Successful Attempts: $SuccessfulAttempts" 
    }
    if ($FailedAttempts -gt 0) {
        LogError "  Failed Attempts: $FailedAttempts" 
    }
    
    if ($TotalAttempts -gt 0) {
        $avgTime = [timespan]::FromMilliseconds(($AttemptTimings | Measure-Object -Average).Average)
        $minTime = [timespan]::FromMilliseconds(($AttemptTimings | Measure-Object -Minimum).Minimum)
        $maxTime = [timespan]::FromMilliseconds(($AttemptTimings |  Measure-Object -Maximum).Maximum)
        
        LogDebug "Timing stats: Avg=$($avgTime.TotalSeconds)s, Min=$($minTime.TotalSeconds)s, Max=$($maxTime.TotalSeconds)s"
        Log "  Average Attempt: $($avgTime.Minutes)m $($avgTime.Seconds)s $($avgTime.Milliseconds)ms" 
        Log "  Fastest Attempt: $($minTime.Minutes)m $($minTime.Seconds)s $($maxTime.Milliseconds)ms" 
        Log "  Slowest Attempt: $($maxTime.Minutes)m $($maxTime.Seconds)s $($maxTime.Milliseconds)ms" 
    }

    # Model Configuration
    Log "CONFIGURATION" 
    Log "  Model: $Model" 
    Log "  Working Directory: $Workdir" 

    # User Stories Status
    Log "USER STORIES" 
    if ($storyStatus -and $storyStatus.TotalStories) {
        Log "  Total Stories: $($storyStatus.TotalStories)" 
        if ($storyStatus.PassedStories -gt 0) {
            LogSuccess "  Passed: $($storyStatus.PassedStories)" 
        }
        if ($storyStatus.FailedStories -gt 0) {
            LogError "  Failed: $($storyStatus.FailedStories)" 
        }
        
        if ($storyStatus.TotalStories -gt 0) {
            $completionRate = [math]::Round(($storyStatus.PassedStories / $storyStatus.TotalStories) * 100, 2)
            Log "  Completion Rate: $completionRate%" 
            Log "  Story Details:" 
            foreach ($story in $storyStatus.Stories) {
                $statusIcon = if ($story.Passes) { "PASS" } else { "FAIL" }
                if ($story.Passes) {
                    LogSuccess "$statusIcon" 
                }
                else {
                    LogError "$statusIcon" 
                }
                Log "$($story.Id): $($story.Title)" 
            }
        }
    }
    Log "`n================================================================================================" 
}

function ValidateCopilotPath {
    [CmdletBinding()]
    param()

    $invalidPattern = "\\Code\\|vscode|visual studio code|intellij|jetbrains|pycharm|webstorm|rider|clion|goland"

    LogDebug "Searching copilot command using where.exe"

    $paths = where.exe copilot 2>$null

    if (-not $paths) {
        LogDebug "No copilot command returned by where.exe"
        return
    }

    foreach ($p in $paths) {
        LogDebug "Candidate path detected: $p"

        if ($p -match $invalidPattern) {
            LogDebug "Rejected path (IDE plugin detected): $p"
            continue
        }

        LogDebug "Accepted copilot path: $p"
        return $p
    }

    LogDebug "No valid copilot command found after filtering"
}

function Main {
    LogDebug "Function called"
    LogDebug "Starting main function execution"

    Log "" 
    Log "  _____       _       _        _____            _ _       _   " 
    Log " |  __ \     | |     | |      / ____|          (_) |     | |  " 
    Log " | |__) |__ _| |_ __ | |__   | |     ___  _ __  _| | ___ | |_ " 
    Log " |  _  // _` | | '_ \| '_ \ | |    / _ \| '_ \| | |/ _ \| __ |" 
    Log " | | \ \ (_| | | |_) | | | | | |___| (_) | |_) | | | (_) | |_ " 
    Log " |_|  \_\__,_|_| .__/|_| |_|  \_____\___/| .__/|_|_|\___/ \__|" 
    Log "               | |                       | |                  " 
    Log "               |_|                       |_|                  " 

    Log "" 
    Log "================================================================================================" 

    # Validate current directory
    LogDebug "Validating working directory"
    $absoluteWorkdir = [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $Workdir))
    LogDebug "Absolute working directory: '$absoluteWorkdir'"
    
    if (-not (Test-Path -Path $absoluteWorkdir)) {
        LogError "Workdir path not found at '$absoluteWorkdir'" 
        LogDebug "Working directory validation FAILED"
        exit 1
    }
    
    Log "Changed working directory to: $absoluteWorkdir" 
    Set-Location -Path $absoluteWorkdir
    LogDebug "Current location set successfully"

    # Initialize variables
    LogDebug "Getting Copilot path"

    try {
        $copilotCmd = ValidateCopilotPath
        if ($copilotCmd) {
            Log "GitHub Copilot CLI found at:" 
            Log "       $($Script:copilotCmd)" 
        }
        else {
            LogError "No valid Copilot command found outside IDE plugin paths." 
            LogWarn "Please install with: npm install -g @github/copilot" 
            exit 1
        }
        
        if (-not [string]::IsNullOrEmpty($Script:Model)) {
            Log "AI Model configured:" 
            Log "         $Script:Model" 
            LogDebug "Model configured: '$($Script:Model)'"
        }
    }
    catch {
        LogError "Failed to locate GitHub Copilot CLI" 
        LogWarn "Please install with: npm install -g @github/copilot" 
        exit 1
    }
    
    # Validate prd.json
    LogDebug "Validating PRD JSON path"
    $Script:prdPath = Join-Path -Path $absoluteWorkdir -ChildPath $Script:prdJson
    LogDebug "PRD path constructed: '$($Script:prdPath)'"
    
    if (-not (Test-Path -Path $Script:prdPath)) {
        LogError "PRD JSON file not found at '$($Script:prdPath)'" 
        LogDebug "PRD JSON validation FAILED - file not found"
        exit 1
    }
    
    Log "PRD JSON file:" 
    Log "       $($Script:prdPath)" 
    LogDebug "PRD JSON validation PASSED - file exists"

    # Ensure progress state files exist, if not create them
    LogDebug "Setting up progress state files"
    $progressStatePath = Join-Path -Path $absoluteWorkdir -ChildPath "progress.txt"
    Log "Progress tracking file:" 
    
    if ($Force) {
        LogDebug "Force flag set, resetting progress state"
        Try {
            Remove-Item -Path $progressStatePath -Force -ErrorAction SilentlyContinue
            LogDebug "Removed existing progress state file"
            New-Item -Path $progressStatePath -ItemType File -Force | Out-Null
            LogWarn "Progress tracking reset due to -Force flag" 
            LogDebug "Created new empty progress state file"
        }
        catch {
            LogError "Failed to reset progress state: $_" 
            LogDebug "Failed to reset progress state: $_"
            exit 1
        }
    }
    else {
        LogDebug "Force flag not set, checking for existing progress state"
        Try {
            if (-not (Test-Path -Path $progressStatePath)) {
                New-Item -Path $progressStatePath -ItemType File -Force | Out-Null
                LogSuccess "Progress tracking file created" 
                LogDebug "Created new progress state file"
            }
            else {
                LogDebug "Progress state file already exists"
            }
        }
        catch {
            LogError "Failed to create state files: $_" 
            LogDebug "Failed to create state files: $_"
            exit 1
        }
    }

    # Set Copilot Prompt for use in the main loop
    LogDebug "Setting Copilot prompt"
    
    try {
        $Script:copilotPrompt = GetPromptText
        LogSuccess "Copilot prompt loaded successfully" 
        if ($Script:copilotPrompt.Length -gt 60) {
            Log "       Prompt preview: $($Script:copilotPrompt.Substring(0, 57))..." 
        }
        else {
            Log "       Prompt: $($Script:copilotPrompt)" 
        }
        LogDebug "Copilot prompt set successfully: '$($Script:copilotPrompt)'"
    }
    catch {
        LogError "Failed to set Copilot Prompt: $_" 
        LogDebug "Failed to set Copilot prompt: $_"
        exit 1
    }

    # Initialize execution tracking variables
    LogDebug "Initializing execution tracking variables"
    $executionStartTime = Get-Date
    Log "Starting Ralph execution with $($Script:Max) maximum attempts" 
    LogDebug "Execution start time recorded: $($executionStartTime)"
    $returnCode = 0
    $returnErrorCodeCounter = 0
    $attempt = 0
    $successfulAttempts = 0
    $attemptTimings = @()
    LogDebug "Tracking variables initialized. Max attempts: $($Script:Max)"

    # Main loop to interact with Copilot
    LogDebug "Entering main execution loop"
    while ($attempt -lt $Script:Max) {
        LogDebug "Loop condition check: attempt=$attempt, max=$($Script:Max)"
        
        $attempt++
        $progressPercent = [math]::Round(($attempt / $Script:Max) * 100)
        
        Log "" 
        Log "================================================================================================" 
        Log "Attempt #$attempt / $($Script:Max)] ($progressPercent%)" 
        Log "--------------------------------------------------------------------------------------------" 
        
        $attemptStartTime = Get-Date
        LogDebug "Attempt start time recorded: $($attemptStartTime)"
        
        # Build argument array for this attempt
        LogDebug "Building argument list for Copilot execution"
        $extraArgs = if ($Script:CopilotArguments) { $Script:CopilotArguments -split ' ' } else { @() }
        LogDebug "Extra args: $($extraArgs -join ', ')"
        
        $argList = @('-p', $Script:copilotPrompt, '--model', $Script:Model) + $extraArgs
        LogDebug "Full argument list: $($argList -join ' ')"

        # Execute Copilot command and capture output and errors
        try {
            Log "Executing Copilot with model '$($Script:Model)'" 
            Log "Command line:" 
            Log "    copilot $($argList -join ' ')" 
            & copilot @argList
            $returnCode = $LASTEXITCODE
            
            if ($returnCode -eq 0) {
                LogSuccess "Attempt #$attempt completed successfully" 
                LogDebug "Copilot command executed successfully, exit code: $returnCode"
                $successfulAttempts++
            }
            else {
                LogWarn "Attempt #$attempt failed with exit code: $returnCode" 
                LogDebug "Copilot command failed with exit code: $returnCode"
            }
        }
        catch {
            LogError "Failed to execute Copilot command: $_" 
            LogDebug "Exception during Copilot execution: $_"
            $returnCode = 1
        }

        # Track attempt timing
        $attemptEndTime = Get-Date
        $attemptDuration = [math]::Round(($attemptEndTime - $attemptStartTime).TotalMilliseconds)
        $attemptTimings += $attemptDuration
    
        if ($attemptDuration -lt 1000) {
            Log "Attempt duration: ${attemptDuration}ms" 
        }
        else {
            Log "Attempt duration: $([math]::Round($attemptDuration / 1000, 2))s" 
        }
    
        if ($returnCode -eq 0) {
            LogDebug "Return code 0, incrementing successful attempts count to $successfulAttempts"
        }
        else {
            $returnErrorCodeCounter++
            LogWarn "Error counter incremented to: $returnErrorCodeCounter" 
            LogDebug "Non-zero exit code ($returnCode), incrementing error counter to $returnErrorCodeCounter"
        }

        # Check if all tasks are complete
        if (Test-AllTasksComplete -Workdir $absoluteWorkdir) {
            Log "" 
            LogSuccess "All user stories completed! Exiting main loop." 
            break
        }
        
        # Show remaining attempts info
        $remaining = $Script:Max - $attempt
        if ($remaining -gt 0) {
            Log "Remaining attempts: $remaining" 
        }
        
        LogDebug "Loop iteration $attempt completed, continuing to next iteration"
        Start-Sleep -Seconds 10
    }

    # Calculate execution metrics
    $executionEndTime = Get-Date
    $totalDuration = [math]::Round(($executionEndTime - $executionStartTime).TotalSeconds)
    
    Log "" 
    Log "================================================================================================" 
    Log "EXECUTION COMPLETE" 
    Log "------------------------------------------------------------------------------------------------" 
    
    LogDebug "Execution end time recorded: $($executionEndTime)"
    LogDebug "Total duration calculated: $totalDuration seconds"
    LogDebug "Successful attempts calculation: $successfulAttempts"
    
    Log "Total Attempts:" 
    Log "  Executed:     $attempt" 
    if ($successfulAttempts -gt 0) {
        LogSuccess "  Successful:   $successfulAttempts" 
    }
    if ($returnErrorCodeCounter -gt 0) {
        LogError "  Failed:       $returnErrorCodeCounter" 
    }
    Log "" 
    
    if ($totalDuration -lt 60) {
        Log "Total Duration:" 
        Log "  $totalDuration seconds" 
    }
    else {
        $minutes = [math]::Floor($totalDuration / 60)
        $seconds = $totalDuration % 60
        Log "Total Duration:" 
        Log "  $minutes min $seconds sec" 
    }
    
    $allTasksComplete = Test-AllTasksComplete -Workdir $absoluteWorkdir
    
    LogDebug "Final tasks completion status: $allTasksComplete"

    # Display comprehensive execution report
    Log "" 
    $storyStatus = Get-UserStorystatus
    
    LogDebug "Calling Show-ExecutionReport to display results"
    
    if ($allTasksComplete) {
        LogSuccess "All user stories completed!" 
    }
    elseif ($returnErrorCodeCounter -ge $Script:Max) {
        LogWarn "Maximum attempts reached" 
    }
    else {
        LogError "Execution stopped early" 
    }
    
    Show-ExecutionReport `
        -TotalDuration (New-TimeSpan -Seconds $totalDuration) `
        -TotalAttempts $attempt `
        -SuccessfulAttempts $successfulAttempts `
        -FailedAttempts $returnErrorCodeCounter `
        -AttemptTimings @($attemptTimings) `
        -AllTasksComplete $allTasksComplete `
        -FinalExitCode $returnCode `
        -Model $Script:Model `
        -MaxAttempts $Script:Max

    Log "" 
    Log "================================================================================================" 
    LogDebug "Execution report displayed, exiting with code 0"
    exit 0
}

Main