# Microsoft Defender (MDE) — Definitions Update + Phone Home

A small, self-healing Jamf Pro workflow that forces **Microsoft Defender for
Endpoint** to update its virus definitions (security intelligence), waits until
the endpoint reports current, then reports the result back into Jamf inventory.

The idea is borrowed from the classic Trellix/McAfee "loop the agent until it
checks in" trick, but retargeted to Defender's `mdatp` CLI. Trellix's
`cmdagent` is **not** used here — this is Defender-only.

## Why

Stale definitions are a common cause of endpoints getting flagged or quarantined
by a security stack. This closes the loop: **update → verify → report**, so a
machine that falls behind fixes itself and drops out of your "stale" list
without anyone chasing it.

## Files

| File | Role |
|------|------|
| `update_mde_definitions.sh` | Jamf **policy** script (silent). Triggers `mdatp definitions update`, polls until `definitions_status` is `up_to_date` (or times out), then runs `jamf recon`. Best for scheduled, hands-off remediation. |
| `update_mde_definitions_gui.sh` | Same logic with a **swiftDialog progress window** for **Self Service**. Live-updates the definitions version/status and phones home when done. swiftDialog is auto-installed if missing (Team ID verified). |
| `mde_definitions_status_ea.sh` | Jamf **Extension Attribute** script. Records Defender's current definitions status into inventory. This is what makes "am I up to date?" visible and Smart-Group-able. |
| `validate_mdatp_fields.sh` | **Read-only** pre-deployment diagnostic. Run once on a test Mac (`sudo zsh validate_mdatp_fields.sh`) to dump the exact `mdatp health` field names/values the scripts rely on and confirm `definitions_status` returns `up_to_date`. Makes no changes. |

### Which script to use

- **Scheduled/automated fleet remediation** → `update_mde_definitions.sh` (silent), scoped to the stale Smart Group on a Recurring Check-in trigger.
- **A Self Service "Update Antivirus Definitions" button** users can click with visible progress → `update_mde_definitions_gui.sh`. Requires [swiftDialog](https://github.com/swiftDialog/swiftDialog) (auto-installed).

Both end the same way: `jamf recon`, so the Extension Attribute / Smart Group reflect the new state.

## Setup (the closed loop)

1. **Extension Attribute** — Computers > Extension Attributes > New.
   Data Type `String`, Input Type `Script`, paste `mde_definitions_status_ea.sh`.
2. **Script** — Settings > Scripts > New. Paste `update_mde_definitions.sh`.
   Optional parameter labels: `$4 = Log path`, `$5 = Max wait (seconds)`.
3. **Smart Computer Group** — criteria: your new EA **is not** `up_to_date`.
   This group is your at-risk list; an empty group means a healthy fleet.
4. **Policy** — scope it to that Smart Group; trigger **Recurring Check-in**;
   frequency **Ongoing**; payload = the script.
   Add **Self Service** as a trigger too if you want a one-click "fix my
   definitions" button for spot troubleshooting.

**Self-heal flow:** stale machine checks in → runs the update → `jamf recon`
rewrites the EA → the machine re-evaluates and leaves the Smart Group. No manual
follow-up.

## Before you trust it at scale

- **Validate the `mdatp` fields on your build.** Run `validate_mdatp_fields.sh`
  (read-only) on a test Mac and confirm `definitions_status` returns
  `up_to_date` when current. If your build reports a different value, adjust the
  status comparisons in `update_mde_definitions.sh` and
  `update_mde_definitions_gui.sh`.
- **Running `mdatp` as root.** Jamf runs scripts and EAs as root, and `mdatp`
  generally behaves as root. If your build rejects a command as root, run just
  that line as the console user via
  `launchctl asuser "$(stat -f%Su /dev/console)" ...`.
- **Egress.** `mdatp definitions update` pulls from Microsoft's cloud. On
  limited-connectivity endpoints, confirm the Defender update endpoints are
  reachable; otherwise the script's timeout will log "still stale" and recon
  will surface it (which is itself useful signal).

## Optional: target by staleness instead of status

If you'd rather remediate only when definitions are older than a grace window
(e.g. > 3 days) instead of on every transient `could_be_older`, use an
**Integer** Extension Attribute built from `definitions_updated_minutes_ago`:

```zsh
#!/bin/zsh
mdatp="/usr/local/bin/mdatp"
[[ -x "$mdatp" ]] || { echo "<result>-1</result>"; exit 0; }
mins=$("$mdatp" health --field definitions_updated_minutes_ago 2>/dev/null | tr -d '"')
# Report age in whole days for easy Smart Group math
echo "<result>$(( ${mins:-0} / 1440 ))</result>"
```

Then Smart Group on `... Days greater than 3`.
