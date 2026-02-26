# macOS 15 Sequoia STIG Compliance Tool — V1R6

Automated compliance checker and remediation script for the **DISA STIG for Apple macOS 15 (Sequoia) — Version 1, Release 6** (January 2026).

Based on the original baseline by [cocopuff2u](https://github.com/cocopuff2u/MacOS_GOV_Scripts), updated to full V1R6 coverage.

---

## Coverage

- **160 STIG rules** — complete V1R6 coverage
- Severities: 11 CAT I (High), 147 CAT II (Medium), 2 CAT III (Low)
- Supports Apple Silicon and Intel Macs
- Checks and optional auto-remediation

---

## Requirements

- macOS 15 Sequoia
- `sudo` / root privileges
- Terminal access

---

## Usage

### Check only (no changes made)
```bash
sudo bash MacOS_15_Sequoia_V1R6_Compliance_Tool.sh -c
```

### Apply fixes
```bash
sudo bash MacOS_15_Sequoia_V1R6_Compliance_Tool.sh -f
```

### Help
```bash
sudo bash MacOS_15_Sequoia_V1R6_Compliance_Tool.sh -h
```

---

## Output

Log files are written to `/var/log/` by default:

| File | Contents |
|------|----------|
| `sequoia_stig_scan_passed.log` | Passed checks |
| `sequoia_stig_scan_failed.log` | Failed checks |
| `sequoia_stig_scan_manual_check.log` | Checks requiring manual review |
| `sequoia_stig_scan_summary.log` | Combined pass/fail summary |
| `sequoia_stig_scan_results_combined.csv` | Machine-readable CSV of all results |
| `sequoia_stig_scan_command_output.log` | Raw command output for each check |

---

## What Changed from V1R1 → V1R6

| Rule | Change | Description |
|------|--------|-------------|
| `APPL-15-004022` | **Added** | sudo must require reauthentication (`timestamp_timeout=0`) |
| `APPL-15-004060` | **Added** | sudoers timestamp type must be `tty` |
| `APPL-15-999999` | **Added** | Security updates must be installed within 30 days *(manual review)* |
| `APPL-15-002130` | **Removed** | CD/DVD sharing check — dropped from V1R6 STIG |

---

## Manual Review Checks

The following rules cannot be fully automated and require human verification:

- `APPL-15-000012` — Login banner content
- `APPL-15-002022` — Full Disk Access (requires FDA)
- `APPL-15-003001` — Organizational account management policy
- `APPL-15-003013` — Intel-specific firmware check
- `APPL-15-003050` / `003051` / `003052` — Physical/environmental controls
- `APPL-15-005120` — Apple Silicon / MDM supervised mode
- `APPL-15-999999` — Confirm latest macOS security update is installed

---

## Script Configuration

Key variables near the top of the script you can adjust before running:

```bash
EXECUTE_FIX=false           # Set true to apply fixes automatically
CLEAR_LOGS=true             # Clear old logs before each run
LOG_PATH=""                 # Override log directory (default: /var/log/)
LOG_TO_SINGLE_FILE=false    # Combine pass/fail into one log
```

To skip specific checks, add APPL IDs to the `General_Skip_Checks` array:
```bash
General_Skip_Checks=("APPL-15-002022" "APPL-15-005120")
```

---

## References

- [DISA STIG Downloads (cyber.mil)](https://public.cyber.mil/stigs/downloads/)
- [Apple macOS 15 Sequoia STIG V1R6](https://public.cyber.mil/stigs/downloads/?_dl_facet_stigs=operating-systems%2Cmac-os)
- [cocopuff2u/MacOS_GOV_Scripts](https://github.com/cocopuff2u/MacOS_GOV_Scripts)
