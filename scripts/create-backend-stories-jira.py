"""Create backend microservice stories under epic MA-19 (backend services).

Derived from docs/design/milkful-system-design.md service layer.

Run:
  $env:JIRA_EMAIL="milkfuldairyindia@gmail.com"; $env:JIRA_TOKEN="<token>"
  python scripts/create-backend-stories-jira.py
"""
import base64
import json
import os
import re
import urllib.error
import urllib.request

EMAIL = os.environ.get("JIRA_EMAIL", "milkfuldairyindia@gmail.com")
TOKEN = os.environ["JIRA_TOKEN"]
BASE = "https://milkfuldairyindia.atlassian.net"
PROJECT = "MA"
EPIC_KEY = "MA-19"
STORY_TYPE = "10003"

AUTH = base64.b64encode(f"{EMAIL}:{TOKEN}".encode()).decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Accept": "application/json",
    "Content-Type": "application/json",
}

# name, summary_suffix, responsibility, apis[], stores[], events[], deps[]
SERVICES = [
    {
        "name": "Identity & Auth Service",
        "resp": "Cognito-backed authentication and authorization: mobile OTP (primary), "
                "optional email/social (Google/Apple), JWT issue/refresh, biometric device "
                "binding, RBAC groups, 2FA for admin, session timeout and multi-device revocation.",
        "apis": ["POST /auth/otp/send", "POST /auth/otp/verify", "POST /auth/social",
                 "POST /auth/refresh", "POST /auth/logout"],
        "stores": ["Amazon Cognito user pools", "Aurora (roles/permissions)"],
        "events": ["publishes UserAuthenticated"],
        "deps": ["Cognito", "SNS (OTP SMS)", "User Service"],
    },
    {
        "name": "User Service",
        "resp": "Manage user profiles, multiple saved addresses (geo-pin/pincode), consents "
                "(T&C/privacy/notifications), account type (B2C/B2B) and status. Triggers wallet "
                "auto-create on registration.",
        "apis": ["POST /users", "GET/PUT /users/{id}", "CRUD /users/{id}/addresses",
                 "GET /users/{id}/consents"],
        "stores": ["Aurora (users, addresses)"],
        "events": ["publishes UserRegistered"],
        "deps": ["Cognito", "Wallet Service", "Serviceability/Inventory zones"],
    },
    {
        "name": "Catalog Service",
        "resp": "Product & category catalog with pricing tiers (B2C/B2B), units, images, "
                "subscription eligibility, and full-text search with filters (category, price, "
                "veg/organic) and sort.",
        "apis": ["GET /products", "GET /products/{id}", "GET /categories",
                 "GET /search?q=&filters="],
        "stores": ["Aurora (products, categories)", "OpenSearch (index)", "Redis (cache)",
                   "S3/CloudFront (images)"],
        "events": ["consumes StockChanged", "publishes CatalogUpdated"],
        "deps": ["Inventory Service", "OpenSearch"],
    },
    {
        "name": "Inventory Service",
        "resp": "Real-time stock: reserve/commit/release, batch & expiry awareness, reorder "
                "alerts, admin manual adjustments with audit, and overselling prevention.",
        "apis": ["POST /inventory/reserve", "POST /inventory/commit", "POST /inventory/release",
                 "PATCH /inventory (admin)", "GET /inventory/{productId}"],
        "stores": ["Aurora (inventory)", "Redis (cached stock)"],
        "events": ["publishes StockChanged, LowStock", "consumes OrderCancelled"],
        "deps": ["Order Service", "Catalog Service", "EventBridge"],
    },
    {
        "name": "Cart Service",
        "resp": "Cart CRUD with min/max quantity validation against stock, price/tax/delivery "
                "preview, cross-device persistence, one-time vs subscription items, re-order shortcuts.",
        "apis": ["GET /cart", "PUT /cart", "POST /cart/items", "DELETE /cart/items/{id}"],
        "stores": ["DynamoDB (cart, TTL)", "Redis"],
        "events": ["publishes CartUpdated"],
        "deps": ["Inventory Service", "Pricing & Offer Service"],
    },
    {
        "name": "Order Service",
        "resp": "Order lifecycle and orchestration (reserve -> pay -> confirm), multi-item orders, "
                "status transitions, cancellation with refund, and order history.",
        "apis": ["POST /orders (idempotent)", "GET /orders", "GET /orders/{id}",
                 "POST /orders/{id}/cancel"],
        "stores": ["Aurora (orders, order_items)", "Redis"],
        "events": ["publishes OrderConfirmed, OrderCancelled", "consumes PaymentConfirmed"],
        "deps": ["Inventory", "Payment", "Wallet", "Pricing", "EventBridge"],
    },
    {
        "name": "Subscription Service",
        "resp": "Recurring subscriptions (daily/alternate/weekly/custom), start/pause/resume/stop, "
                "skip-a-day, cut-off enforcement, and scheduled daily order generation.",
        "apis": ["POST /subscriptions", "PATCH /subscriptions/{id}",
                 "POST /subscriptions/{id}/pause|resume|skip"],
        "stores": ["Aurora (subscriptions, subscription_items)"],
        "events": ["publishes SubscriptionOrderDue (via Scheduler + Step Functions)"],
        "deps": ["Order", "Wallet", "Inventory", "EventBridge Scheduler", "Step Functions"],
    },
    {
        "name": "Payment Service",
        "resp": "Gateway integration (Razorpay/Paytm) for UPI/cards/netbanking, wallet-first + "
                "gateway top-up, idempotent charges, webhook signature verification, reconciliation, "
                "and refunds. PCI-DSS via tokenization.",
        "apis": ["POST /payments (idempotency-key)", "POST /payments/webhook",
                 "POST /payments/{id}/refund"],
        "stores": ["Aurora (payments)"],
        "events": ["publishes PaymentConfirmed, PaymentFailed, RefundIssued"],
        "deps": ["Razorpay/Paytm", "Wallet Service", "Order Service"],
    },
    {
        "name": "Wallet Service",
        "resp": "Prepaid wallet balance and immutable ledger (recharge/debit/refund/cashback/"
                "referral), auto-recharge, low-balance alerts, idempotent crediting, auto-create "
                "on registration.",
        "apis": ["GET /wallets/{userId}", "POST /wallets/{id}/recharge",
                 "POST /wallets/{id}/debit", "GET /wallets/{id}/transactions"],
        "stores": ["Aurora (wallets, wallet_txns)"],
        "events": ["publishes WalletDebited, WalletCredited",
                   "consumes UserRegistered, OrderConfirmed"],
        "deps": ["Payment Service", "Order Service"],
    },
    {
        "name": "Pricing & Offer Service",
        "resp": "Price/tax (GST/HSN) and delivery-fee computation, offers/coupons/promo codes "
                "(percentage/flat/BOGO/first-order/subscription), best-offer auto-apply and "
                "real-time validation.",
        "apis": ["POST /pricing/quote", "GET /offers", "POST /offers/validate"],
        "stores": ["Aurora (offers, coupons)", "Redis"],
        "events": ["consumes CatalogUpdated"],
        "deps": ["Catalog", "Cart", "Order"],
    },
    {
        "name": "Delivery Service",
        "resp": "Delivery assignment and route optimization, partner management, live tracking, "
                "delivery proof (OTP/photo), and serviceable zone/holiday calendar.",
        "apis": ["POST /deliveries/assign", "PATCH /deliveries/{id}/status",
                 "GET /deliveries/{id}/tracking"],
        "stores": ["Aurora (deliveries, routes, partners)", "DynamoDB (live tracking, TTL)"],
        "events": ["consumes OrderConfirmed", "publishes DeliveryAssigned, DeliveryStatusChanged"],
        "deps": ["Amazon Location Service", "Notification Service"],
    },
    {
        "name": "Notification Service",
        "resp": "Multi-channel notifications (push/SMS/email/WhatsApp), transactional templates, "
                "OTP delivery, campaign scheduling/targeting, opt-out compliance, and delivery/open metrics.",
        "apis": ["POST /notifications/send", "CRUD /notifications/templates"],
        "stores": ["DynamoDB (templates, logs)"],
        "events": ["consumes OrderConfirmed, DeliveryStatusChanged, LowStock, PaymentFailed"],
        "deps": ["SNS", "SES", "Pinpoint", "WhatsApp BSP"],
    },
    {
        "name": "Reporting & Analytics Service",
        "resp": "Management reporting suite: sales/revenue, subscription analytics (churn/MRR), "
                "delivery performance, inventory & wastage, customer analytics, payments/wallet, "
                "offers/referrals ROI, complaints SLA. Filters, drill-down, scheduling, PDF/Excel export.",
        "apis": ["GET /reports/{type}", "POST /reports/schedule", "GET /reports/{id}/export"],
        "stores": ["OpenSearch", "Aurora read replica", "S3", "Athena/QuickSight"],
        "events": ["consumes domain event stream"],
        "deps": ["All services", "BI/Analytics"],
    },
]


def text(v, marks=None):
    n = {"type": "text", "text": v}
    if marks:
        n["marks"] = marks
    return n


def heading(level, v):
    return {"type": "heading", "attrs": {"level": level}, "content": [text(v)]}


def paragraph(*parts):
    return {"type": "paragraph", "content": list(parts)}


def bullet(items):
    return {
        "type": "bulletList",
        "content": [{"type": "listItem", "content": [paragraph(text(i))]} for i in items],
    }


def build_description(svc):
    return {
        "version": 1,
        "type": "doc",
        "content": [
            heading(2, "Service"),
            paragraph(text(svc["name"] + " (backend microservice on AWS Lambda / ECS Fargate)")),
            heading(2, "Responsibility"),
            paragraph(text(svc["resp"])),
            heading(2, "Key APIs"),
            bullet(svc["apis"]),
            heading(2, "Data Stores"),
            bullet(svc["stores"]),
            heading(2, "Events"),
            bullet(svc["events"]),
            heading(2, "Dependencies"),
            bullet(svc["deps"]),
            heading(2, "Source"),
            paragraph(text("Milkful system design (docs/design/milkful-system-design.md)")),
        ],
    }


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def create_story(svc):
    body = {
        "fields": {
            "project": {"key": PROJECT},
            "parent": {"key": EPIC_KEY},
            "summary": f"{svc['name']} (Backend Microservice)",
            "issuetype": {"id": STORY_TYPE},
            "description": build_description(svc),
            "labels": ["backend", "microservice", "aws", slug(svc["name"])],
        }
    }
    data = json.dumps(body).encode()
    req = urllib.request.Request(f"{BASE}/rest/api/3/issue", data=data, headers=HEADERS, method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{e.code}: {e.read().decode()}") from e


def main():
    created = []
    for svc in SERVICES:
        r = create_story(svc)
        created.append((r["key"], svc["name"]))
        print(f"{r['key']} - {svc['name']}")
    print(f"\nCreated {len(created)} backend stories under {EPIC_KEY}")
    print(f"{BASE}/browse/{EPIC_KEY}")


if __name__ == "__main__":
    main()
