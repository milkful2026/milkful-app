"""Link backend service stories to the Admin-UI stories they support.

Uses the 'Blocks' link type: backend service BLOCKS the admin feature
(admin feature shows 'is blocked by' the backend service).

Run:
  $env:JIRA_EMAIL="milkfuldairyindia@gmail.com"; $env:JIRA_TOKEN="<token>"
  python scripts/link-admin-backend-jira.py
"""
import base64
import json
import os
import urllib.error
import urllib.request

EMAIL = os.environ.get("JIRA_EMAIL", "milkfuldairyindia@gmail.com")
TOKEN = os.environ["JIRA_TOKEN"]
BASE = "https://milkfuldairyindia.atlassian.net"
LINK_TYPE = "Blocks"

AUTH = base64.b64encode(f"{EMAIL}:{TOKEN}".encode()).decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Accept": "application/json",
    "Content-Type": "application/json",
}

# admin story -> backend services that support it
LINKS = [
    ("MA-39", "Enable / Disable User Account", ["MA-92", "MA-93"]),
    ("MA-40", "View Recharge / Transaction Status", ["MA-99", "MA-100"]),
    ("MA-41", "Management Reporting Suite", ["MA-104"]),
    ("MA-42", "Product & Catalog Management", ["MA-94", "MA-95"]),
    ("MA-43", "Order & Subscription Management", ["MA-97", "MA-98"]),
    ("MA-44", "Delivery & Route Management", ["MA-102"]),
    ("MA-45", "Offer, Coupon & Referral Management", ["MA-101", "MA-100"]),
    ("MA-46", "Customer Support / CRM & Complaint Desk", ["MA-97", "MA-100", "MA-103"]),
    ("MA-47", "RBAC & Admin Users", ["MA-92"]),
    ("MA-48", "Inventory & Procurement Control", ["MA-95"]),
    ("MA-49", "Notification & Communication Manager", ["MA-103"]),
    ("MA-50", "System Configuration & Audit Log", ["MA-92", "MA-100", "MA-101", "MA-102"]),
]

BACKEND_NAMES = {
    "MA-92": "Identity & Auth", "MA-93": "User", "MA-94": "Catalog",
    "MA-95": "Inventory", "MA-96": "Cart", "MA-97": "Order",
    "MA-98": "Subscription", "MA-99": "Payment", "MA-100": "Wallet",
    "MA-101": "Pricing & Offer", "MA-102": "Delivery", "MA-103": "Notification",
    "MA-104": "Reporting & Analytics",
}


def create_link(blocker, blocked):
    body = json.dumps({
        "type": {"name": LINK_TYPE},
        "outwardIssue": {"key": blocker},
        "inwardIssue": {"key": blocked},
    }).encode()
    req = urllib.request.Request(
        f"{BASE}/rest/api/3/issueLink", data=body, headers=HEADERS, method="POST"
    )
    with urllib.request.urlopen(req) as resp:
        return resp.status


def main():
    total = 0
    for admin_key, admin_name, backends in LINKS:
        for be in backends:
            try:
                create_link(be, admin_key)
                total += 1
                print(f"{be} ({BACKEND_NAMES.get(be, be)}) blocks {admin_key} ({admin_name})")
            except urllib.error.HTTPError as e:
                print(f"FAILED {be} -> {admin_key}: {e.code} {e.read().decode()}")
    print(f"\nCreated {total} admin-to-backend dependency links.")


if __name__ == "__main__":
    main()
