#!/bin/bash
# ==============================================================================
# macOS 15 Sequoia STIG V1R6 — CKL Generator
# ==============================================================================
# Converts compliance scan CSV output + XCCDF XML into a STIG Viewer .ckl file.
#
# Usage:
#   sudo bash generate_ckl.sh
#   sudo bash generate_ckl.sh --csv /var/log/sequoia_stig_scan_results_combined.csv
#   sudo bash generate_ckl.sh --xccdf /path/to/xccdf.xml --output ~/Desktop/results.ckl
#
# Defaults:
#   --csv     /var/log/sequoia_stig_scan_results_combined.csv
#   --xccdf   ./U_Apple_macOS_15_V1R6_STIG_Manual-xccdf.xml (same dir as script)
#   --output  ./sequoia_stig_v1r6_<timestamp>.ckl
# ==============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

# ── Defaults ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"

CSV_FILE="/var/log/sequoia_stig_scan_results_combined.csv"
XCCDF_FILE="${SCRIPT_DIR}/U_Apple_macOS_15_V1R6_STIG_Manual-xccdf.xml"
OUTPUT_FILE="${SCRIPT_DIR}/sequoia_stig_v1r6_${TIMESTAMP}.ckl"

# ── Argument parsing ──────────────────────────────────────────────────────────
usage() {
    echo "Usage: sudo bash $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --csv FILE      Path to scan CSV (default: /var/log/sequoia_stig_scan_results_combined.csv)"
    echo "  --xccdf FILE    Path to V1R6 XCCDF XML (default: script dir)"
    echo "  --output FILE   Output .ckl path (default: timestamped file in script dir)"
    echo "  -h, --help      Show this help"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --csv)    CSV_FILE="$2";    shift 2 ;;
        --xccdf)  XCCDF_FILE="$2";  shift 2 ;;
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; usage ;;
    esac
done

# ── Dependency check ──────────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    echo -e "${RED}Error: python3 not found.${NC}"
    exit 1
fi

# ── Header ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}macOS 15 Sequoia STIG V1R6 — CKL Generator${NC}"
echo "=================================================="

# ── Validate XCCDF ────────────────────────────────────────────────────────────
if [[ ! -f "$XCCDF_FILE" ]]; then
    echo -e "${RED}Error: XCCDF file not found: $XCCDF_FILE${NC}"
    echo "Copy the V1R6 XCCDF XML into the STIG/ folder or pass --xccdf /path/to/file.xml"
    exit 1
fi
echo -e "  XCCDF:  ${BLUE}${XCCDF_FILE}${NC}"

# ── System info ───────────────────────────────────────────────────────────────
HOST_NAME="$(hostname -s 2>/dev/null || echo "")"
HOST_FQDN="$(hostname 2>/dev/null || echo "")"
HOST_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")"
HOST_MAC="$(ifconfig en0 2>/dev/null | awk '/ether/{print $2}' || echo "")"
SCAN_DATE="$(date +"%Y-%m-%d %H:%M:%S")"
echo -e "  Host:   ${BLUE}${HOST_NAME}${NC} (${HOST_IP})"

# ── Temp workspace ────────────────────────────────────────────────────────────
TMPDIR_CKL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_CKL"' EXIT

# ── Step 1: Parse XCCDF ───────────────────────────────────────────────────────
echo "  Parsing XCCDF rules..."

python3 - "$XCCDF_FILE" "$TMPDIR_CKL" << 'PYEOF'
import sys, json, re
import xml.etree.ElementTree as ET

xccdf_path = sys.argv[1]
tmpdir     = sys.argv[2]
NS = {'xccdf': 'http://checklists.nist.gov/xccdf/1.1'}

tree = ET.parse(xccdf_path)
root = tree.getroot()

# Benchmark metadata
pt = root.find('.//xccdf:plain-text', NS)
bench_meta = {
    'title':        root.findtext('xccdf:title', '', NS),
    'description':  root.findtext('xccdf:description', '', NS) or '',
    'version':      root.findtext('xccdf:version', '1', NS),
    'release_info': pt.text.strip() if pt is not None and pt.text else '',
    'benchmark_id': root.get('id', 'Apple_macOS_15_STIG'),
}
with open(f"{tmpdir}/bench_meta.json", 'w') as f:
    json.dump(bench_meta, f)

# Rules
rules = []
for group in root.findall('.//xccdf:Group', NS):
    vuln_num    = group.get('id', '')
    group_title = group.findtext('xccdf:title', '', NS)
    for rule in group.findall('xccdf:Rule', NS):
        appl_id  = rule.findtext('xccdf:version', '', NS)
        severity = rule.get('severity', 'medium')
        title    = rule.findtext('xccdf:title', '', NS)
        rule_id  = rule.get('id', '')

        vuln_discuss = ''
        desc_el = rule.find('xccdf:description', NS)
        if desc_el is not None and desc_el.text:
            m = re.search(r'<VulnDiscussion>(.*?)</VulnDiscussion>', desc_el.text, re.DOTALL)
            vuln_discuss = m.group(1).strip() if m else desc_el.text.strip()

        check_content = next(
            (c.text.strip() for c in rule.findall('.//xccdf:check-content', NS) if c.text), ''
        )
        fix_text = next(
            (f.text.strip() for f in rule.findall('.//xccdf:fixtext', NS) if f.text), ''
        )
        cci_refs = [
            i.text.strip() for i in rule.findall('xccdf:ident', NS)
            if i.text and 'cci' in (i.get('system', '') or '').lower()
        ]

        rules.append({
            'appl_id': appl_id, 'vuln_num': vuln_num, 'rule_id': rule_id,
            'severity': severity, 'group_title': group_title, 'title': title,
            'vuln_discuss': vuln_discuss, 'check_content': check_content,
            'fix_text': fix_text, 'cci_refs': cci_refs,
        })

with open(f"{tmpdir}/rules.json", 'w') as f:
    json.dump(rules, f)

print(f"  Loaded {len(rules)} rules from XCCDF")
PYEOF

# ── Step 2: Parse CSV ─────────────────────────────────────────────────────────
if [[ -f "$CSV_FILE" ]]; then
    echo -e "  CSV:    ${BLUE}${CSV_FILE}${NC}"
    python3 - "$CSV_FILE" "${TMPDIR_CKL}/csv_results.json" << 'PYEOF'
import sys, csv, json
results = {}
try:
    with open(sys.argv[1], newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            appl_id = row.get('STIG ID', '').strip()
            if appl_id:
                results[appl_id] = {
                    'pass_fail': row.get('Pass/Fail', '').strip(),
                    'output':    row.get('Result', '').strip().strip('"'),
                }
    print(f"  Loaded {len(results)} scan results from CSV")
except FileNotFoundError:
    print("  CSV not found")
with open(sys.argv[2], 'w') as f:
    json.dump(results, f)
PYEOF
else
    echo -e "${YELLOW}  Warning: CSV not found at ${CSV_FILE}${NC}"
    echo    "  All rules will be marked Not_Reviewed — run the compliance script first."
    echo '{}' > "${TMPDIR_CKL}/csv_results.json"
fi

# ── Step 3: Build CKL header ──────────────────────────────────────────────────
echo "  Generating CKL..."

# Read benchmark metadata
BENCH_TITLE="$(python3   -c "import json; print(json.load(open('${TMPDIR_CKL}/bench_meta.json'))['title'])")"
BENCH_DESC="$(python3    -c "import json; print(json.load(open('${TMPDIR_CKL}/bench_meta.json'))['description'])")"
BENCH_VER="$(python3     -c "import json; print(json.load(open('${TMPDIR_CKL}/bench_meta.json'))['version'])")"
RELEASE="$(python3       -c "import json; print(json.load(open('${TMPDIR_CKL}/bench_meta.json'))['release_info'])")"
BENCH_ID="$(python3      -c "import json; print(json.load(open('${TMPDIR_CKL}/bench_meta.json'))['benchmark_id'])")"
BENCH_UUID="$(python3    -c "import uuid; print(uuid.uuid4())")"
STIG_REF="${BENCH_TITLE} :: Version ${BENCH_VER}, ${RELEASE}"

xml_esc() { python3 -c "
import sys
s=sys.argv[1]
s=s.replace('&','&amp;').replace('<','&lt;').replace('>','&gt;').replace('\"','&quot;')
print(s,end='')
" "$1"; }

cat > "$OUTPUT_FILE" << XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<!--DISA STIG Viewer :: 3.x-->
<CHECKLIST>
  <ASSET>
    <ROLE>Workstation</ROLE>
    <ASSET_TYPE>Computing</ASSET_TYPE>
    <HOST_NAME>$(xml_esc "$HOST_NAME")</HOST_NAME>
    <HOST_IP>$(xml_esc "$HOST_IP")</HOST_IP>
    <HOST_MAC>$(xml_esc "$HOST_MAC")</HOST_MAC>
    <HOST_FQDN>$(xml_esc "$HOST_FQDN")</HOST_FQDN>
    <TARGET_COMMENT></TARGET_COMMENT>
    <TECH_AREA></TECH_AREA>
    <TARGET_KEY>5402</TARGET_KEY>
    <WEB_OR_DATABASE>false</WEB_OR_DATABASE>
    <WEB_DB_SITE></WEB_DB_SITE>
    <WEB_DB_INSTANCE></WEB_DB_INSTANCE>
  </ASSET>
  <STIGS>
    <iSTIG>
      <STIG_INFO>
        <SI_DATA><SID_NAME>version</SID_NAME><SID_DATA>$(xml_esc "$BENCH_VER")</SID_DATA></SI_DATA>
        <SI_DATA><SID_NAME>classification</SID_NAME><SID_DATA>UNCLASSIFIED</SID_DATA></SI_DATA>
        <SI_DATA><SID_NAME>customname</SID_NAME><SID_DATA></SID_DATA></SI_DATA>
        <SI_DATA><SID_NAME>stigid</SID_NAME><SID_DATA>$(xml_esc "$BENCH_ID")</SID_DATA></SI_DATA>
        <SI_DATA><SID_NAME>description</SID_NAME><SID_DATA>$(xml_esc "$BENCH_DESC")</SID_DATA></SI_DATA>
        <SI_DATA><SID_NAME>filename</SID_NAME><SID_DATA>U_Apple_macOS_15_V1R6_STIG_Manual-xccdf.xml</SID_DATA></SI_DATA>
        <SI_DATA><SID_NAME>releaseinfo</SID_NAME><SID_DATA>$(xml_esc "$RELEASE")</SID_DATA></SI_DATA>
        <SI_DATA><SID_NAME>title</SID_NAME><SID_DATA>$(xml_esc "$BENCH_TITLE")</SID_DATA></SI_DATA>
        <SI_DATA><SID_NAME>uuid</SID_NAME><SID_DATA>$(xml_esc "$BENCH_UUID")</SID_DATA></SI_DATA>
        <SI_DATA><SID_NAME>notice</SID_NAME><SID_DATA>terms-of-use</SID_DATA></SI_DATA>
        <SI_DATA><SID_NAME>source</SID_NAME><SID_DATA>STIG.DOD.MIL</SID_DATA></SI_DATA>
      </STIG_INFO>
XMLEOF

# ── Step 4: Write VULN entries ────────────────────────────────────────────────
python3 - "$TMPDIR_CKL" "$OUTPUT_FILE" "$STIG_REF" "$SCAN_DATE" << 'PYEOF'
import sys, json, uuid

tmpdir    = sys.argv[1]
out_path  = sys.argv[2]
stig_ref  = sys.argv[3]
scan_date = sys.argv[4]

with open(f"{tmpdir}/rules.json") as f:
    rules = json.load(f)
with open(f"{tmpdir}/csv_results.json") as f:
    scan_results = json.load(f)

STATUS_MAP = {'Passed': 'NotAFinding', 'Failed': 'Open', 'Manual Check': 'Not_Reviewed'}

def esc(s):
    if not s: return ''
    return (str(s).replace('&','&amp;').replace('<','&lt;')
                  .replace('>','&gt;').replace('"','&quot;'))

passed = failed = manual = not_reviewed = 0
lines = []

for r in sorted(rules, key=lambda x: x['appl_id']):
    appl_id = r['appl_id']
    scan    = scan_results.get(appl_id, {})
    pf      = scan.get('pass_fail', '')
    status  = STATUS_MAP.get(pf, 'Not_Reviewed')
    output  = scan.get('output', '')

    if status == 'NotAFinding': passed += 1
    elif status == 'Open':      failed += 1
    elif pf == 'Manual Check':  manual += 1
    else:                       not_reviewed += 1

    finding_details = f"Command output: {output}" if output else ''
    comments = (f"Auto-generated by compliance scan on {scan_date}"
                if scan else "Not scanned — run MacOS_15_Sequoia_V1R6_STIG_Compliance_Tool.sh first")

    lines.append('      <VULN>')
    for attr, data in [
        ('Vuln_Num',    r['vuln_num']),    ('Severity',    r['severity']),
        ('Group_Title', r['group_title']), ('Rule_ID',     r['rule_id']),
        ('Rule_Ver',    appl_id),          ('Rule_Title',  r['title']),
        ('Vuln_Discuss', r['vuln_discuss']), ('IA_Controls', ''),
        ('Check_Content', r['check_content']), ('Fix_Text', r['fix_text']),
        ('False_Positives',''), ('False_Negatives',''),
        ('Documentable','false'), ('Mitigations',''),
        ('Potential_Impact',''), ('Third_Party_Tools',''),
        ('Mitigation_Control',''), ('Responsibility',''),
        ('Security_Override_Guidance',''), ('Check_Content_Ref','M'),
        ('Weight','10.0'), ('Class','Unclass'),
        ('STIGRef', stig_ref), ('TargetKey','5402'),
        ('STIG_UUID', str(uuid.uuid4())),
    ]:
        lines += ['        <STIG_DATA>',
                  f'          <VULN_ATTRIBUTE>{attr}</VULN_ATTRIBUTE>',
                  f'          <ATTRIBUTE_DATA>{esc(data)}</ATTRIBUTE_DATA>',
                  '        </STIG_DATA>']

    for cci in r.get('cci_refs', []):
        lines += ['        <STIG_DATA>',
                  '          <VULN_ATTRIBUTE>CCI_REF</VULN_ATTRIBUTE>',
                  f'          <ATTRIBUTE_DATA>{esc(cci)}</ATTRIBUTE_DATA>',
                  '        </STIG_DATA>']

    lines += [
        f'        <STATUS>{status}</STATUS>',
        f'        <FINDING_DETAILS>{esc(finding_details)}</FINDING_DETAILS>',
        f'        <COMMENTS>{esc(comments)}</COMMENTS>',
        '        <SEVERITY_OVERRIDE></SEVERITY_OVERRIDE>',
        '        <SEVERITY_JUSTIFICATION></SEVERITY_JUSTIFICATION>',
        '      </VULN>',
    ]

with open(out_path, 'a') as f:
    f.write('\n'.join(lines) + '\n')

with open(f"{tmpdir}/summary.json", 'w') as f:
    json.dump({'passed': passed, 'failed': failed, 'manual': manual,
               'not_reviewed': not_reviewed, 'total': len(rules)}, f)
PYEOF

# ── Step 5: Close CKL ────────────────────────────────────────────────────────
cat >> "$OUTPUT_FILE" << 'XMLEOF'
    </iSTIG>
  </STIGS>
</CHECKLIST>
XMLEOF

# ── Summary ───────────────────────────────────────────────────────────────────
PASSED="$(python3  -c "import json; print(json.load(open('${TMPDIR_CKL}/summary.json'))['passed'])")"
FAILED="$(python3  -c "import json; print(json.load(open('${TMPDIR_CKL}/summary.json'))['failed'])")"
MANUAL="$(python3  -c "import json; m=json.load(open('${TMPDIR_CKL}/summary.json')); print(m['manual']+m['not_reviewed'])")"
TOTAL="$(python3   -c "import json; print(json.load(open('${TMPDIR_CKL}/summary.json'))['total'])")"

echo ""
echo -e "${BOLD}Results summary:${NC}"
echo -e "  ${GREEN}NotAFinding  (Passed):       ${PASSED}${NC}"
echo -e "  ${RED}Open         (Failed):       ${FAILED}${NC}"
echo -e "  ${YELLOW}Not_Reviewed (Manual/None):  ${MANUAL}${NC}"
echo    "  Total rules:                 ${TOTAL}"
echo ""
echo -e "${GREEN}CKL written to:${NC}"
echo -e "  ${BOLD}${OUTPUT_FILE}${NC}"
