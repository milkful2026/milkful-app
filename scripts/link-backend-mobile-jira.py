"""Link backend service stories to the mobile stories they support (dependency links).

Uses the 'Blocks' link type: backend service BLOCKS the mobile feature
(so the mobile feature shows 'is blocked by' the backend service).

Run:
  $env:JIRA_EMAIL="milkfuldairyindia@gmail.com"; $env:JIRA_TOKEN="<token>"
  python scripts/link-backend-mobile-jira.py
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

# mobile story -> backend services that block/support it
# (mobile_key, mobile_name, [backend_keys])
LINKS = [
    ("MA-1", "User Registration", ["MA-92", "MA-93", "MA-100", "MA-95"]),
    ("MA-21", "User Login", ["MA-92", "MA-93"]),
    ("MA-22", "Product Listing", ["MA-94", "MA-95"]),
    ("MA-23", "Add to Cart", ["MA-96", "MA-95", "MA-101"]),
    ("MA-24", "Payment Gateway Integration", ["MA-99", "MA-100"]),
    ("MA-25", "Subscription Module", ["MA-98", "MA-97", "MA-100"]),
    ("MA-26", "Order History", ["MA-97"]),
    ("MA-27", "Transaction History", ["MA-100", "MA-99"]),
    ("MA-28", "Feedback", ["MA-97", "MA-104"]),
    ("MA-29", "Offers", ["MA-101"]),
    ("MA-30", "Referrals", ["MA-100", "MA-101"]),
    ("MA-31", "Calendar View", ["MA-98", "MA-97"]),
    ("MA-32", "Order Cancellation", ["MA-97", "MA-95", "MA-100"]),
    ("MA-33", "Wallet Recharge", ["MA-100", "MA-99"]),
    ("MA-34", "Order Confirmation / Preview", ["MA-97", "MA-101", "MA-100"]),
    ("MA-35", "Order Details", ["MA-97", "MA-102"]),
    ("MA-36", "Order Status", ["MA-97", "MA-102", "MA-103"]),
    ("MA-37", "Inventory Module Integration", ["MA-95"]),
    ("MA-38", "Invoice Generation", ["MA-101", "MA-99"]),
]

BACKEND_NAMES = {
    "MA-92": "Identity & Auth", "MA-93": "User", "MA-94": "Catalog",
    "MA-95": "Inventory", "MA-96": "Cart", "MA-97": "Order",
    "MA-98": "Subscription", "MA-99": "Payment", "MA-100": "Wallet",
    "MA-101": "Pricing & Offer", "MA-102": "Delivery", "MA-103": "Notification",
    "MA-104": "Reporting & Analytics",
}


def create_link(blocker, blocked):
    """blocker BLOCKS blocked -> outwardIssue=blocker, inwardIssue=blocked."""
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
    for mobile_key, mobile_name, backends in LINKS:
        for be in backends:
            try:
                create_link(be, mobile_key)
                total += 1
                print(f"{be} ({BACKEND_NAMES.get(be, be)}) blocks {mobile_key} ({mobile_name})")
            except urllib.error.HTTPError as e:
                print(f"FAILED {be} -> {mobile_key}: {e.code} {e.read().decode()}")
    print(f"\nCreated {total} dependency links.")


if __name__ == "__main__":
    main()
