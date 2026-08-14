# Creates the User Registration story in Jira project MA.
# Usage:
#   $env:JIRA_EMAIL = "your-atlassian-email@example.com"
#   $env:JIRA_TOKEN = "your-api-token"
#   .\scripts\create-jira-user-registration-story.ps1

param(
    [string]$ProjectKey = "MA",
    [string]$JiraBaseUrl = "https://milkfuldairyindia.atlassian.net"
)

$email = $env:JIRA_EMAIL
$token = $env:JIRA_TOKEN

if (-not $email -or -not $token) {
    Write-Error "Set JIRA_EMAIL and JIRA_TOKEN environment variables before running."
    exit 1
}

$pair = "${email}:${token}"
$base64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
$headers = @{
    Authorization = "Basic $base64"
    Accept        = "application/json"
    "Content-Type" = "application/json"
}

# Verify auth
try {
    $me = Invoke-RestMethod -Uri "$JiraBaseUrl/rest/api/3/myself" -Headers $headers -Method Get
    Write-Host "Authenticated as: $($me.displayName) ($($me.emailAddress))"
} catch {
    Write-Error "Jira authentication failed. Use the email tied to your API token."
    exit 1
}

$description = @"
h2. User Story

*As a* new Milkful customer,
*I want* to register using my mobile number (with OTP), optionally via email or social login, and set up my profile, delivery address, and preferences,
*So that* I can start ordering fresh dairy products with a verified account, serviceable delivery location, and a ready-to-use wallet.

h2. Module
Onboarding / Sign-Up

h2. Platform
Flutter (iOS & Android)

h2. Functional Requirements

* Mobile number + OTP verification (primary registration path)
* Optional email and social sign-up (Google / Apple)
* Capture full name
* Delivery address with geo-pin / map picker
* Pincode serviceability check (Inventory zones)
* Preferred delivery time slot selection
* Multiple saved addresses support
* Consent for Terms & Conditions, Privacy Policy, and push notifications
* Auto-create linked Wallet on successful registration

h2. Key Dependencies

* OTP/SMS API
* Maps / Geocoding API
* Serviceability (Inventory zones)
* Wallet service

h2. Acceptance Criteria

h3. AC-1: Mobile + OTP (Primary)
* Enter +91 mobile number with validation
* Send OTP via SMS API with resend timer
* Verify OTP; handle invalid/expired errors
* Redirect existing users to login

h3. AC-2: Email & Social (Optional)
* Google Sign-In (Android & iOS)
* Apple Sign-In (iOS)
* Secure token storage via flutter_secure_storage

h3. AC-3: Profile — Name
* Required full name with validation

h3. AC-4: Delivery Address
* Map picker with drag pin
* Address search / autocomplete
* Manual entry fallback
* Reverse geocoding

h3. AC-5: Serviceability
* Pincode/location check against inventory zones
* Block or waitlist if not serviceable

h3. AC-6: Delivery Time Slot
* Select from API-provided slots for user's zone

h3. AC-7: Multiple Addresses
* Save first address during registration (required)
* Support default/primary address flag

h3. AC-8: Consent
* Required T&C and Privacy Policy checkboxes with links
* Push notification consent + FCM/APNs permission

h3. AC-9: Wallet
* Auto-create wallet on registration via Wallet service
* Confirm wallet ready on success screen

h3. AC-10: Completion
* Auth tokens stored; navigate to home
* Resume onboarding if interrupted
* Analytics events for funnel tracking

h2. Flutter Sub-Tasks

# Project setup & onboarding routes
# Mobile sign-up UI + validation
# OTP verification screen + API
# Google Sign-In integration
# Apple Sign-In integration
# Profile name form
# Map & address picker (maps, geocoding)
# Serviceability API integration
# Delivery slot selector
# Address model & multi-address repository
# Consent screens (WebView + notification permission)
# Registration API orchestration
# Wallet provisioning confirmation
# Secure storage & auth state
# Onboarding persistence (resume flow)
# Unit, widget, and integration tests

h2. Screen Flow

Welcome → Sign Up → OTP → Name → Address (Map) → Serviceability → Slot → Consent → Success → Home

h2. Definition of Done

* All ACs pass on iOS and Android
* Staging API integration verified
* Error/empty states on all screens
* Code review + QA sign-off
"@

$body = @{
    fields = @{
        project = @{ key = $ProjectKey }
        summary = "User Registration — Mobile OTP, Social Login, Address & Wallet Setup (Flutter)"
        description = $description
        issuetype = @{ name = "Story" }
        labels = @("flutter", "mobile", "onboarding", "registration", "wallet")
    }
} | ConvertTo-Json -Depth 10

try {
    $response = Invoke-RestMethod -Uri "$JiraBaseUrl/rest/api/3/issue" -Headers $headers -Method Post -Body $body
    $issueKey = $response.key
    $issueUrl = "$JiraBaseUrl/browse/$issueKey"
    Write-Host "Created story: $issueKey"
    Write-Host $issueUrl
} catch {
    Write-Error "Failed to create issue: $($_.ErrorDetails.Message)"
    exit 1
}

# Create sub-tasks
$subtasks = @(
    "Flutter: Project setup & onboarding routing",
    "Flutter: Mobile sign-up UI & phone validation",
    "Flutter: OTP verification screen & SMS API",
    "Flutter: Google Sign-In integration",
    "Flutter: Apple Sign-In integration",
    "Flutter: Profile name capture form",
    "Flutter: Map picker & geocoding address entry",
    "Flutter: Pincode serviceability API integration",
    "Flutter: Delivery time slot selector",
    "Flutter: Multi-address model & repository",
    "Flutter: T&C, Privacy & notification consent",
    "Flutter: Registration API orchestration",
    "Flutter: Wallet auto-create confirmation",
    "Flutter: Secure auth storage & session",
    "Flutter: Onboarding resume persistence",
    "Flutter: Unit, widget & integration tests"
)

foreach ($summary in $subtasks) {
    $subBody = @{
        fields = @{
            project = @{ key = $ProjectKey }
            parent  = @{ key = $issueKey }
            summary = $summary
            issuetype = @{ name = "Sub-task" }
        }
    } | ConvertTo-Json -Depth 10

    try {
        $sub = Invoke-RestMethod -Uri "$JiraBaseUrl/rest/api/3/issue" -Headers $headers -Method Post -Body $subBody
        Write-Host "  Sub-task: $($sub.key) — $summary"
    } catch {
        Write-Warning "  Sub-task skipped ($summary): $($_.ErrorDetails.Message)"
    }
}

Write-Host "`nDone. View board: $JiraBaseUrl/jira/software/projects/$ProjectKey/boards/1"
