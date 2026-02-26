#!/usr/bin/env python3
"""
macOS 15 Sequoia STIG V1R6 — CKL Generator
============================================
Converts scan CSV output + XCCDF XML into a STIG Viewer .ckl file.

Usage:
    sudo python3 generate_ckl.py
    sudo python3 generate_ckl.py --csv /var/log/sequoia_stig_scan_results_combined.csv
    sudo python3 generate_ckl.py --xccdf /path/to/xccdf.xml --output ~/Desktop/results.ckl

Defaults:
    --csv     /var/log/sequoia_stig_scan_results_combined.csv
    --xccdf   ./U_Apple_macOS_15_V1R6_STIG_Manual-xccdf.xml (same dir as this script)
    --output  ./sequoia_stig_v1r6_<timestamp>.ckl
"""

import argparse
import csv
import re
import socket
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET
from datetime import datetime
from pathlib import Path

# ── Defaults ──────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).parent.resolve()

DEFAULT_CSV = Path("/var/log/sequoia_stig_scan_results_combined.csv")
DEFAULT_XCCDF = SCRIPT_DIR / "U_Apple_macOS_15_V1R6_STIG_Manual-xccdf.xml"
DEFAULT_OUTPUT = SCRIPT_DIR / f"sequoia_stig_v1r6_{datetime.now().strftime('%Y%m%d_%H%M%S')}.ckl"

NS = {'xccdf': 'http://checklists.nist.gov/xccdf/1.1'}


# ── System info ───────────────────────────────────────────────────────────────

def get_system_info():
    hostname = socket.gethostname()
    fqdn = socket.getfqdn()
    try:
        ip = socket.gethostbyname(hostname)
    except Exception:
        ip = ""
    try:
        mac = subprocess.check_output(
            "ifconfig en0 2>/dev/null | awk '/ether/{print $2}'",
            shell=True, text=True
        ).strip()
    except Exception:
        mac = ""
    return hostname, ip, mac, fqdn


# ── XCCDF parser ──────────────────────────────────────────────────────────────

def parse_xccdf(xccdf_path):
    print(f"Parsing XCCDF: {xccdf_path}")
    tree = ET.parse(xccdf_path)
    root = tree.getroot()

    bench_title   = root.findtext('xccdf:title', '', NS)
    bench_desc    = root.findtext('xccdf:description', '', NS) or ''
    bench_version = root.findtext('xccdf:version', '1', NS)
    plain_text_el = root.find('.//xccdf:plain-text', NS)
    release_info  = plain_text_el.text.strip() if plain_text_el is not None and plain_text_el.text else ''
    bench_id      = root.get('id', 'Apple_macOS_15_STIG')

    rules = {}
    for group in root.findall('.//xccdf:Group', NS):
        vuln_num    = group.get('id', '')           # V-268420
        group_title = group.findtext('xccdf:title', '', NS)  # SRG ref

        for rule in group.findall('xccdf:Rule', NS):
            rule_id  = rule.get('id', '')           # SV-268420r...
            severity = rule.get('severity', 'medium')
            appl_id  = rule.findtext('xccdf:version', '', NS)  # APPL-15-000001
            title    = rule.findtext('xccdf:title', '', NS)

            # VulnDiscussion is embedded XML-in-text inside <description>
            vuln_discuss = ''
            desc_el = rule.find('xccdf:description', NS)
            if desc_el is not None and desc_el.text:
                m = re.search(r'<VulnDiscussion>(.*?)</VulnDiscussion>',
                              desc_el.text, re.DOTALL)
                vuln_discuss = m.group(1).strip() if m else desc_el.text.strip()

            check_content = ''
            for chk in rule.findall('.//xccdf:check-content', NS):
                if chk.text:
                    check_content = chk.text.strip()
                    break

            fix_text = ''
            for fix in rule.findall('.//xccdf:fixtext', NS):
                if fix.text:
                    fix_text = fix.text.strip()
                    break

            cci_refs = [
                ident.text.strip()
                for ident in rule.findall('xccdf:ident', NS)
                if ident.text and 'cci' in (ident.get('system', '')).lower()
            ]

            rules[appl_id] = {
                'vuln_num':    vuln_num,
                'group_title': group_title,
                'rule_id':     rule_id,
                'severity':    severity,
                'title':       title,
                'vuln_discuss':   vuln_discuss,
                'check_content':  check_content,
                'fix_text':       fix_text,
                'cci_refs':       cci_refs,
            }

    bench_meta = {
        'title':        bench_title,
        'description':  bench_desc,
        'version':      bench_version,
        'release_info': release_info,
        'benchmark_id': bench_id,
    }
    print(f"  Loaded {len(rules)} rules from XCCDF")
    return rules, bench_meta


# ── CSV parser ────────────────────────────────────────────────────────────────

def parse_csv(csv_path):
    results = {}
    try:
        with open(csv_path, newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                appl_id   = row.get('STIG ID', '').strip()
                pass_fail = row.get('Pass/Fail', '').strip()
                output    = row.get('Result', '').strip()
                if appl_id:
                    results[appl_id] = {'pass_fail': pass_fail, 'output': output}
        print(f"  Loaded {len(results)} scan results from CSV")
    except FileNotFoundError:
        print(f"  Warning: CSV not found at {csv_path}")
        print("  All rules will be marked Not_Reviewed — run the compliance script first.")
    return results


# ── Status mapping ────────────────────────────────────────────────────────────

STATUS_MAP = {
    'Passed':       'NotAFinding',
    'Failed':       'Open',
    'Manual Check': 'Not_Reviewed',
}

def to_status(pass_fail):
    return STATUS_MAP.get(pass_fail, 'Not_Reviewed')


# ── XML helpers ───────────────────────────────────────────────────────────────

def esc(text):
    if not text:
        return ''
    return (str(text)
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;'))


# ── CKL builder ───────────────────────────────────────────────────────────────

def generate_ckl(rules, bench_meta, scan_results, output_path, system_info):
    hostname, ip, mac, fqdn = system_info
    scan_date = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    stig_ref  = (f"{bench_meta['title']} :: "
                 f"Version {bench_meta['version']}, {bench_meta['release_info']}")

    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!--DISA STIG Viewer :: 3.x-->',
        '<CHECKLIST>',
        '  <ASSET>',
        '    <ROLE>Workstation</ROLE>',
        '    <ASSET_TYPE>Computing</ASSET_TYPE>',
        f'    <HOST_NAME>{esc(hostname)}</HOST_NAME>',
        f'    <HOST_IP>{esc(ip)}</HOST_IP>',
        f'    <HOST_MAC>{esc(mac)}</HOST_MAC>',
        f'    <HOST_FQDN>{esc(fqdn)}</HOST_FQDN>',
        '    <TARGET_COMMENT></TARGET_COMMENT>',
        '    <TECH_AREA></TECH_AREA>',
        '    <TARGET_KEY>5402</TARGET_KEY>',
        '    <WEB_OR_DATABASE>false</WEB_OR_DATABASE>',
        '    <WEB_DB_SITE></WEB_DB_SITE>',
        '    <WEB_DB_INSTANCE></WEB_DB_INSTANCE>',
        '  </ASSET>',
        '  <STIGS>',
        '    <iSTIG>',
        '      <STIG_INFO>',
    ]

    for name, data in [
        ('version',        bench_meta['version']),
        ('classification', 'UNCLASSIFIED'),
        ('customname',     ''),
        ('stigid',         bench_meta['benchmark_id']),
        ('description',    bench_meta['description']),
        ('filename',       'U_Apple_macOS_15_V1R6_STIG_Manual-xccdf.xml'),
        ('releaseinfo',    bench_meta['release_info']),
        ('title',          bench_meta['title']),
        ('uuid',           str(uuid.uuid4())),
        ('notice',         'terms-of-use'),
        ('source',         'STIG.DOD.MIL'),
    ]:
        lines += [
            '        <SI_DATA>',
            f'          <SID_NAME>{name}</SID_NAME>',
            f'          <SID_DATA>{esc(data)}</SID_DATA>',
            '        </SI_DATA>',
        ]

    lines.append('      </STIG_INFO>')

    passed = failed = manual = not_reviewed = 0

    for appl_id in sorted(rules.keys()):
        r    = rules[appl_id]
        scan = scan_results.get(appl_id, {})

        status          = to_status(scan.get('pass_fail', ''))
        output          = scan.get('output', '')
        finding_details = f"Command output: {output}" if output else ''
        comments        = (f"Auto-generated by compliance scan on {scan_date}"
                           if scan else "Not scanned — run MacOS_15_Sequoia_V1R6_STIG_Compliance_Tool.sh first")

        if status == 'NotAFinding': passed += 1
        elif status == 'Open':      failed += 1
        elif scan.get('pass_fail') == 'Manual Check': manual += 1
        else:                       not_reviewed += 1

        lines.append('      <VULN>')

        for attr, data in [
            ('Vuln_Num',                 r['vuln_num']),
            ('Severity',                 r['severity']),
            ('Group_Title',              r['group_title']),
            ('Rule_ID',                  r['rule_id']),
            ('Rule_Ver',                 appl_id),
            ('Rule_Title',               r['title']),
            ('Vuln_Discuss',             r['vuln_discuss']),
            ('IA_Controls',              ''),
            ('Check_Content',            r['check_content']),
            ('Fix_Text',                 r['fix_text']),
            ('False_Positives',          ''),
            ('False_Negatives',          ''),
            ('Documentable',             'false'),
            ('Mitigations',              ''),
            ('Potential_Impact',         ''),
            ('Third_Party_Tools',        ''),
            ('Mitigation_Control',       ''),
            ('Responsibility',           ''),
            ('Security_Override_Guidance', ''),
            ('Check_Content_Ref',        'M'),
            ('Weight',                   '10.0'),
            ('Class',                    'Unclass'),
            ('STIGRef',                  stig_ref),
            ('TargetKey',                '5402'),
            ('STIG_UUID',                str(uuid.uuid4())),
        ]:
            lines += [
                '        <STIG_DATA>',
                f'          <VULN_ATTRIBUTE>{attr}</VULN_ATTRIBUTE>',
                f'          <ATTRIBUTE_DATA>{esc(data)}</ATTRIBUTE_DATA>',
                '        </STIG_DATA>',
            ]

        for cci in r['cci_refs']:
            lines += [
                '        <STIG_DATA>',
                '          <VULN_ATTRIBUTE>CCI_REF</VULN_ATTRIBUTE>',
                f'          <ATTRIBUTE_DATA>{esc(cci)}</ATTRIBUTE_DATA>',
                '        </STIG_DATA>',
            ]

        lines += [
            f'        <STATUS>{status}</STATUS>',
            f'        <FINDING_DETAILS>{esc(finding_details)}</FINDING_DETAILS>',
            f'        <COMMENTS>{esc(comments)}</COMMENTS>',
            '        <SEVERITY_OVERRIDE></SEVERITY_OVERRIDE>',
            '        <SEVERITY_JUSTIFICATION></SEVERITY_JUSTIFICATION>',
            '      </VULN>',
        ]

    lines += [
        '    </iSTIG>',
        '  </STIGS>',
        '</CHECKLIST>',
    ]

    output_path = Path(output_path)
    output_path.write_text('\n'.join(lines), encoding='utf-8')

    total = passed + failed + manual + not_reviewed
    print(f"\nResults summary:")
    print(f"  NotAFinding  (Passed):       {passed}")
    print(f"  Open         (Failed):       {failed}")
    print(f"  Not_Reviewed (Manual/None):  {manual + not_reviewed}")
    print(f"  Total rules:                 {total}")
    print(f"\nCKL file written to:\n  {output_path}")
    return output_path


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description='Generate a STIG Viewer .ckl file from macOS 15 V1R6 scan results.'
    )
    parser.add_argument('--csv',    default=str(DEFAULT_CSV),
                        help=f'Path to scan CSV (default: {DEFAULT_CSV})')
    parser.add_argument('--xccdf', default=str(DEFAULT_XCCDF),
                        help=f'Path to V1R6 XCCDF XML (default: {DEFAULT_XCCDF})')
    parser.add_argument('--output', default=str(DEFAULT_OUTPUT),
                        help=f'Output .ckl file path (default: timestamped file in script dir)')
    args = parser.parse_args()

    xccdf_path = Path(args.xccdf)
    if not xccdf_path.exists():
        print(f"Error: XCCDF file not found: {xccdf_path}")
        print("Copy the V1R6 XCCDF XML into the STIG/ folder or pass --xccdf /path/to/file.xml")
        sys.exit(1)

    print("macOS 15 Sequoia STIG V1R6 — CKL Generator")
    print("=" * 50)

    rules, bench_meta = parse_xccdf(xccdf_path)
    scan_results      = parse_csv(Path(args.csv))
    system_info       = get_system_info()

    print(f"  Host: {system_info[0]} ({system_info[1]})")

    generate_ckl(rules, bench_meta, scan_results, args.output, system_info)


if __name__ == '__main__':
    main()
