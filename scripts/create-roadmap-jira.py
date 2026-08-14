"""Create the AWS deployment roadmap in Jira.

Structure:
  Epic  : Cloud Infrastructure & Deployment (AWS)
  Story : one per roadmap phase (9)
  Subtask: one per roadmap task (33) with planned start/due dates in description

Run:
  $env:JIRA_EMAIL="milkfuldairyindia@gmail.com"; $env:JIRA_TOKEN="<token>"
  python scripts/create-roadmap-jira.py
"""
import base64
import json
import os
import urllib.error
import urllib.request
from datetime import date, timedelta

EMAIL = os.environ.get("JIRA_EMAIL", "milkfuldairyindia@gmail.com")
TOKEN = os.environ["JIRA_TOKEN"]
BASE = "https://milkfuldairyindia.atlassian.net"
PROJECT = "MA"

EPIC_TYPE = "10004"
STORY_TYPE = "10003"
SUBTASK_TYPE = "10005"
START_DATE_FIELD = "customfield_10015"

BASE_DATE = date(2026, 7, 15)

AUTH = base64.b64encode(f"{EMAIL}:{TOKEN}".encode()).decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Accept": "application/json",
    "Content-Type": "application/json",
}

# phase: (name, [ (task, start_day, duration_days), ... ])
PHASES = [
    ("Week 1 - Foundation & Security", [
        ("IAM & Roles Setup", 0, 7),
        ("WAF & Shield Configuration", 7, 7),
    ]),
    ("Week 2 - Frontend Hosting", [
        ("S3 Bucket + CloudFront", 14, 7),
        ("SSL/TLS Certificates", 21, 3),
        ("Deploy Initial Frontend", 24, 4),
    ]),
    ("Week 3 - Authentication", [
        ("Cognito User Pools", 28, 7),
        ("API Gateway Integration", 35, 5),
        ("JWT Flow Testing", 40, 2),
    ]),
    ("Week 4 - Backend APIs", [
        ("API Gateway Endpoints", 42, 7),
        ("Lambda Functions", 49, 7),
        ("Connect to RDS/DynamoDB", 56, 4),
        ("ElastiCache Setup", 60, 3),
    ]),
    ("Week 5 - Database & Storage", [
        ("RDS Schema Finalization", 63, 7),
        ("DynamoDB Config", 70, 5),
        ("S3 Storage Setup", 75, 3),
        ("Backups & Multi-AZ", 78, 2),
    ]),
    ("Week 6 - Payments & Delivery", [
        ("Payment Gateway Integration", 80, 7),
        ("Location Service Setup", 87, 5),
        ("Delivery Partner App Link", 92, 3),
    ]),
    ("Week 7 - Notifications & Monitoring", [
        ("SNS Setup", 95, 4),
        ("Pinpoint Config", 99, 3),
        ("CloudWatch Dashboards", 102, 5),
        ("X-Ray Integration", 107, 3),
    ]),
    ("Week 8 - Scalability & Resilience", [
        ("Load Balancer Setup", 110, 5),
        ("Auto Scaling Config", 115, 5),
        ("CloudFront Optimization", 120, 3),
        ("Performance Testing", 123, 4),
    ]),
    ("Week 9 - CI/CD & Validation", [
        ("CodePipeline Integration", 127, 5),
        ("Automated Deployments", 132, 4),
        ("Security Audits", 136, 3),
        ("End-to-End Testing", 139, 5),
    ]),
]


def _post(fields):
    body = json.dumps({"fields": fields}).encode()
    req = urllib.request.Request(
        f"{BASE}/rest/api/3/issue", data=body, headers=HEADERS, method="POST"
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode())


def create_issue(fields, optional_keys=()):
    """Create an issue; if optional fields are rejected (400), retry without them."""
    try:
        return _post(fields)
    except urllib.error.HTTPError as e:
        if e.code != 400 or not optional_keys:
            raise RuntimeError(f"{e.code}: {e.read().decode()}") from e
        reduced = {k: v for k, v in fields.items() if k not in optional_keys}
        return _post(reduced)


def adf(*paragraphs):
    return {
        "version": 1,
        "type": "doc",
        "content": [
            {"type": "paragraph", "content": [{"type": "text", "text": p}]}
            for p in paragraphs
        ],
    }


def fmt(d):
    return d.isoformat()


def main():
    # 1) Epic
    epic = create_issue(
        {
            "project": {"key": PROJECT},
            "summary": "Cloud Infrastructure & Deployment (AWS)",
            "issuetype": {"id": EPIC_TYPE},
            "description": adf(
                "AWS cloud-native deployment roadmap for the Milkful platform.",
                "Covers foundation/security, frontend hosting, auth, backend APIs, "
                "data & storage, payments & delivery, notifications & monitoring, "
                "scalability & resilience, and CI/CD.",
                "Timeline: 2026-07-15 onwards (~144 working days across 9 phases). "
                "See docs/design/milkful-deployment-roadmap-cost.md.",
            ),
            "labels": ["aws", "infrastructure", "devops", "roadmap"],
        },
        optional_keys=("labels",),
    )
    epic_key = epic["key"]
    print(f"EPIC {epic_key} - Cloud Infrastructure & Deployment (AWS)")

    total_created = 0
    for phase_name, tasks in PHASES:
        p_start = min(t[1] for t in tasks)
        p_end = max(t[1] + t[2] for t in tasks)
        story_fields = {
            "project": {"key": PROJECT},
            "parent": {"key": epic_key},
            "summary": f"Phase: {phase_name}",
            "issuetype": {"id": STORY_TYPE},
            "description": adf(
                f"Deployment roadmap phase '{phase_name}'.",
                "Tasks: " + "; ".join(f"{t[0]} ({t[2]}d)" for t in tasks),
                f"Planned window: {fmt(BASE_DATE + timedelta(days=p_start))} "
                f"to {fmt(BASE_DATE + timedelta(days=p_end))}.",
            ),
            "labels": ["aws", "infrastructure", "roadmap"],
            START_DATE_FIELD: fmt(BASE_DATE + timedelta(days=p_start)),
            "duedate": fmt(BASE_DATE + timedelta(days=p_end)),
        }
        story = create_issue(
            story_fields, optional_keys=("labels", START_DATE_FIELD, "duedate")
        )
        story_key = story["key"]
        print(f"  STORY {story_key} - {phase_name}")

        for task, start, dur in tasks:
            s_date = BASE_DATE + timedelta(days=start)
            d_date = BASE_DATE + timedelta(days=start + dur)
            sub_fields = {
                "project": {"key": PROJECT},
                "parent": {"key": story_key},
                "summary": task,
                "issuetype": {"id": SUBTASK_TYPE},
                "description": adf(
                    f"Duration: {dur} day(s).",
                    f"Planned: {fmt(s_date)} to {fmt(d_date)}.",
                ),
            }
            sub = create_issue(sub_fields, optional_keys=("description",))
            total_created += 1
            print(f"    SUBTASK {sub['key']} - {task} ({dur}d)")

    print(f"\nDone. Epic {epic_key}: 9 stories, {total_created} sub-tasks.")
    print(f"{BASE}/browse/{epic_key}")


if __name__ == "__main__":
    main()
