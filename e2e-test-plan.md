# Smashcut E2E Test Plan

Flows tested by the e2e test runner. Each flow takes screenshots at key checkpoints.

## Flow 1: App Launch
- Launch app on simulator
- Screenshot: project list (empty or with projects)

## Flow 2: New Project Creation
- Tap "New Project" / "+" button
- Fill in project title
- Fill in script idea
- Tap "Next"
- Screenshot: Script Workshop view

## Flow 3: Script Refinement (requires API key)
- Tap "Refine with Claude"
- Wait for refinement to complete
- Screenshot: Refined script with sections
- Tap "Accept & Continue"
- Screenshot: Section Manager with sections listed

## Flow 4: Section Manager
- Verify sections are listed with correct status badges
- Screenshot: Section Manager overview
- Tap "Open Timeline"
- Screenshot: Timeline view
- Navigate back

## Flow 5: Recording Flow
- Tap "Record" on a section
- Screenshot: Teleprompter recording view
- Dismiss recording view
- Screenshot: Back to section manager

## Flow 6: Settings
- Tap Settings gear icon
- Screenshot: Settings view with API key field
- Dismiss settings

## Run Protocol
After each flow, the runner saves a screenshot to `reports/screenshots/` and logs pass/fail.
The final report is generated at `reports/e2e-report.md` with all screenshots embedded.
