import json
import base64
import os
import urllib.request
import urllib.error

email = os.environ.get("JIRA_EMAIL", "milkfuldairyindia@gmail.com")
token = os.environ.get("JIRA_TOKEN")
if not token:
    raise SystemExit("Set JIRA_TOKEN environment variable")

auth = base64.b64encode(f"{email}:{token}".encode()).decode()
base = "https://milkfuldairyindia.atlassian.net"
headers = {
    "Authorization": f"Basic {auth}",
    "Accept": "application/json",
    "Content-Type": "application/json",
}


def req(method, url, data=None):
    body = json.dumps(data).encode() if data is not None else None
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw.strip() else {}
    except urllib.error.HTTPError as e:
        print("ERROR", e.code, e.read().decode())
        raise


epics = [
    {
        "summary": "mobile-app-development",
        "description": "Epic for Flutter mobile app development including onboarding, customer features, and mobile-specific integrations.",
    },
    {
        "summary": "backend services",
        "description": "Epic for backend APIs and microservices including auth, OTP/SMS, wallet, serviceability, orders, and integrations.",
    },
    {
        "summary": "Admin-UI",
        "description": "Epic for admin web UI including operations dashboard, inventory, orders, users, and configuration management.",
    },
]

for epic in epics:
    body = {
        "fields": {
            "project": {"key": "MA"},
            "summary": epic["summary"],
            "issuetype": {"id": "10004"},
            "description": {
                "type": "doc",
                "version": 1,
                "content": [
                    {
                        "type": "paragraph",
                        "content": [{"type": "text", "text": epic["description"]}],
                    }
                ],
            },
        }
    }
    result = req("POST", f"{base}/rest/api/3/issue", body)
    print(f"{result['key']} - {epic['summary']} -> {base}/browse/{result['key']}")
