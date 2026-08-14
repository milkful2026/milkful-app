"""Generate importable draw.io (.drawio) files for Milkful (Well-Architected).

Outputs:
  docs/design/milkful-hld.drawio        - 2 pages: Architecture (VPC/Zero-Trust/Stateless)
                                          and Database-per-Service
  docs/design/milkful-messaging.drawio  - Event-driven messaging topology
  docs/design/milkful-lld.drawio        - LLD sequence flows (with EventBridge -> SQS)

Run:  python scripts/design/generate_drawio.py
"""
import os
from xml.sax.saxutils import escape

OUT_DIR = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "..", "docs", "design")
)

# ---------------------------------------------------------------- style palette
STYLES = {
    "client": "rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontSize=12;",
    "edge_svc": "rounded=1;whiteSpace=wrap;html=1;fillColor=#ffe6cc;strokeColor=#d79b00;fontSize=12;",
    "api": "rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontSize=12;",
    "service": "rounded=1;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;fontSize=12;",
    "msg": "rounded=1;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;fontSize=12;",
    "eb": "rounded=1;whiteSpace=wrap;html=1;fillColor=#ffe6cc;strokeColor=#d79b00;fontSize=12;fontStyle=1;",
    "sqs": "rounded=1;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;fontSize=11;",
    "sns": "rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontSize=11;",
    "sfn": "rounded=1;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;fontSize=11;",
    "dlq": "rounded=1;whiteSpace=wrap;html=1;fillColor=#f8cecc;strokeColor=#b85450;fontSize=10;",
    "data": "shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=14;fillColor=#f8cecc;strokeColor=#b85450;fontSize=11;",
    "external": "rounded=1;whiteSpace=wrap;html=1;fillColor=#f5f5f5;strokeColor=#666666;fontSize=11;",
    "observ": "rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontSize=11;",
    "net": "rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontSize=11;",
    "note": "shape=note;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;fontSize=10;align=left;verticalAlign=top;spacingLeft=6;spacingTop=4;size=14;",
    "title": "text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;fontStyle=1;fontSize=20;",
    "subtitle": "text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;fontStyle=2;fontSize=12;fontColor=#555555;",
}

CONTAINER = (
    "rounded=1;whiteSpace=wrap;html=1;fillColor=#fbfcfe;strokeColor=#b3bcc6;"
    "verticalAlign=top;align=left;fontStyle=1;fontSize=13;fontColor=#48525c;"
    "spacingLeft=12;spacingTop=8;container=1;collapsible=0;"
)
VPC = (
    "rounded=1;whiteSpace=wrap;html=1;fillColor=#eef6fb;strokeColor=#2d6a9f;"
    "verticalAlign=top;align=left;fontStyle=1;fontSize=13;fontColor=#1b4b73;"
    "spacingLeft=12;spacingTop=8;container=1;collapsible=0;"
)
SUBNET_PRIV = (
    "rounded=1;whiteSpace=wrap;html=1;fillColor=#f2f8f2;strokeColor=#5a8f5a;"
    "verticalAlign=top;align=left;fontStyle=1;fontSize=12;fontColor=#3a5f3a;"
    "spacingLeft=10;spacingTop=6;container=1;collapsible=0;"
)
SUBNET_PUB = (
    "rounded=1;whiteSpace=wrap;html=1;fillColor=#fdf5ec;strokeColor=#c08a3e;"
    "verticalAlign=top;align=left;fontStyle=1;fontSize=12;fontColor=#8a5a1e;"
    "spacingLeft=10;spacingTop=6;container=1;collapsible=0;"
)
SUBNET_MSG = (
    "rounded=1;whiteSpace=wrap;html=1;fillColor=#fbf7ee;strokeColor=#b08d3e;"
    "verticalAlign=top;align=left;fontStyle=1;fontSize=12;fontColor=#6f5a24;"
    "spacingLeft=10;spacingTop=6;container=1;collapsible=0;"
)

# hybrid compute per service (must match milkful-architecture.drawio and §6.1 of the doc)
COMPUTE_TYPE = {
    "Identity & Auth": "Lambda",
    "User Service": "Lambda",
    "Cart Service": "Lambda",
    "Subscription Service": "Lambda",
    "Notification Service": "Lambda",
    "Catalog Service": "Fargate",
    "Pricing & Offer Service": "Fargate",
    "Order Service": "Fargate",
    "Payment Service": "Fargate",
    "Wallet Service": "Fargate",
    "Inventory Service": "Fargate",
    "Delivery Service": "Fargate",
    "Reporting & Analytics": "Fargate",
}
# compute-coloured service boxes: Lambda = orange, Fargate = blue
SVC_LAMBDA = "rounded=1;whiteSpace=wrap;html=1;fillColor=#ffe6cc;strokeColor=#d79b00;fontSize=12;"
SVC_FARGATE = "rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontSize=12;"


def svc_style(name):
    return SVC_LAMBDA if COMPUTE_TYPE.get(name) == "Lambda" else SVC_FARGATE


# compute annotation for LLD lifeline labels (labels differ from full service names)
LLD_COMPUTE = {
    "Order Service": "Fargate",
    "Inventory Svc": "Fargate",
    "Payment Svc": "Fargate",
    "Subscription Svc": "Lambda",
    "Delivery Svc": "Fargate",
    "Notification": "Lambda",
    "Catalog Svc": "Fargate",
    "Wallet": "Fargate",
}


EDGE_STYLE = "edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;strokeColor=#4a5568;fontSize=10;"
FLOW_EDGE = (
    "edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;strokeColor=#37474f;"
    "strokeWidth=2;fontSize=11;fontColor=#37474f;fontStyle=1;labelBackgroundColor=#ffffff;"
)
THIN_EDGE = (
    "edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;strokeColor=#90a4ae;"
    "fontSize=10;fontColor=#607d8b;labelBackgroundColor=#ffffff;"
)


def vtx(cid, value, x, y, w, h, style, parent="1"):
    return (
        f'        <mxCell id="{cid}" value="{escape(value)}" style="{style}" '
        f'vertex="1" parent="{parent}">\n'
        f'          <mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry" />\n'
        f"        </mxCell>\n"
    )


def edg(eid, source, target, value="", style=EDGE_STYLE):
    return (
        f'        <mxCell id="{eid}" value="{escape(value)}" style="{style}" '
        f'edge="1" parent="1" source="{source}" target="{target}">\n'
        f'          <mxGeometry relative="1" as="geometry" />\n'
        f"        </mxCell>\n"
    )


def page(name, pid, width, height, body):
    return (
        f'  <diagram name="{escape(name)}" id="{pid}">\n'
        f'    <mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" guides="1" '
        f'tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" '
        f'pageWidth="{width}" pageHeight="{height}" math="0" shadow="0">\n'
        f"      <root>\n"
        f'        <mxCell id="0" />\n'
        f'        <mxCell id="1" parent="0" />\n'
        f"{body}"
        f"      </root>\n"
        f"    </mxGraphModel>\n"
        f"  </diagram>\n"
    )


def wrap(pages):
    return '<mxfile host="app.diagrams.net" type="device">\n' + "".join(pages) + "</mxfile>\n"


# ============================================================ HLD page 1
def build_hld_arch():
    b = ""
    b += vtx("t1", "Milkful - Well-Architected Architecture (VPC | Zero-Trust | Stateless)", 40, 8, 1440, 34, STYLES["title"])

    # principles note (top-right)
    principles = (
        "DESIGN PRINCIPLES  -  "
        "Stateless services (JWT, no session affinity, auto-scaled).  "
        "Zero-Trust (authenticate every request, least-privilege IAM per service, "
        "private subnets, VPC endpoints, mTLS).  "
        "Database-per-service (no shared DB).  "
        "Event-driven (EventBridge + SQS + SNS + Step Functions).  Multi-AZ."
    )
    b += vtx("n_principles", principles, 1100, 48, 380, 100, STYLES["note"])

    # clients
    b += vtx("clients", "1 - Client Applications (public internet)", 40, 48, 1040, 90, CONTAINER)
    for cid, label, x in [
        ("c_user", "Customer App\n(Flutter)", 20),
        ("c_del", "Delivery App\n(Flutter)", 275),
        ("c_admin", "Admin Web\n(React)", 530),
        ("c_b2b", "B2B Portal\n(React)", 785),
    ]:
        b += vtx(cid, label, x, 34, 235, 44, STYLES["client"], parent="clients")

    # edge
    b += vtx("edge", "2 - Edge (public, managed) - Zero-Trust entry: TLS + WAF + JWT", 40, 168, 1040, 90, CONTAINER)
    for cid, label, x, sk in [
        ("e_r53", "Route 53", 15, "edge_svc"),
        ("e_cf", "CloudFront\n+ WAF + Shield", 220, "edge_svc"),
        ("e_s3", "S3 Static", 425, "edge_svc"),
        ("a_gw", "API Gateway", 630, "api"),
        ("a_cog", "Cognito", 835, "api"),
    ]:
        b += vtx(cid, label, x, 34, 195, 44, STYLES[sk], parent="edge")

    # VPC
    b += vtx("vpc", "3 - Amazon VPC  -  Multi-AZ, private subnets, default-deny security groups", 40, 290, 1440, 470, VPC)

    # public subnet
    b += vtx("sn_pub", "Public Subnets (AZ-a / AZ-b)", 20, 34, 1400, 66, SUBNET_PUB, parent="vpc")
    b += vtx("alb", "Application Load Balancer\n(TLS termination)", 20, 28, 250, 30, STYLES["net"], parent="sn_pub")
    b += vtx("nat", "NAT Gateway\n(controlled egress)", 300, 28, 220, 30, STYLES["net"], parent="sn_pub")

    # app subnet
    b += vtx("sn_app", "Private App Subnets - Microservices (hybrid: 8 ECS Fargate + 5 Lambda)", 20, 116, 900, 150, SUBNET_PRIV, parent="vpc")
    app_note = (
        "13 stateless microservices (see 'Database-per-Service' page for the per-service compute type).  "
        "Fargate (behind ALB): Catalog, Pricing, Order, Payment, Wallet, Inventory, Delivery, Reporting.  "
        "Lambda (event-driven): Auth, User, Cart, Subscription, Notification.  "
        "Each: own IAM role (least privilege), no local state, auto-scaling across AZs, idempotent writes."
    )
    b += vtx("n_app", app_note, 15, 32, 860, 100, STYLES["note"], parent="sn_app")

    # data subnet
    b += vtx("sn_data", "Private Data Subnets - Database per Service (no shared DB)", 20, 282, 900, 170, SUBNET_PRIV, parent="vpc")
    for cid, label, x in [
        ("d_rds", "Aurora\n(per-svc clusters)", 20),
        ("d_ddb", "DynamoDB\n(cart, tracking)", 215),
        ("d_red", "ElastiCache\nRedis", 410),
        ("d_oss", "OpenSearch\n(search + CQRS)", 605),
    ]:
        b += vtx(cid, label, x, 36, 175, 70, STYLES["data"], parent="sn_data")
    b += vtx("n_data", "One database per service; cross-service data via events / APIs only.", 20, 118, 760, 40, STYLES["note"], parent="sn_data")

    # messaging backbone
    b += vtx("sn_msg", "Async Messaging Backbone", 940, 116, 480, 150, SUBNET_MSG, parent="vpc")
    b += vtx("mb_eb", "Amazon EventBridge\n(domain-event bus)", 15, 34, 215, 40, STYLES["eb"], parent="sn_msg")
    b += vtx("mb_sns", "Amazon SNS\n(fan-out)", 245, 34, 215, 40, STYLES["sns"], parent="sn_msg")
    b += vtx("mb_sqs", "Amazon SQS\n(+ DLQ, per consumer)", 15, 84, 215, 44, STYLES["sqs"], parent="sn_msg")
    b += vtx("mb_sfn", "AWS Step Functions\n(saga / orchestration)", 245, 84, 215, 44, STYLES["sfn"], parent="sn_msg")

    # vpc endpoints
    b += vtx("sn_vpce", "VPC Endpoints (PrivateLink)", 940, 282, 480, 90, SUBNET_PRIV, parent="vpc")
    b += vtx("n_vpce", "SQS, SNS, EventBridge, S3, DynamoDB, Secrets Manager, KMS, CloudWatch - AWS traffic stays private (no internet egress).", 15, 30, 450, 50, STYLES["note"], parent="sn_vpce")

    # external (outside VPC)
    b += vtx("ext", "External Integrations (egress via NAT only)", 40, 790, 720, 90, CONTAINER)
    for cid, label, x in [
        ("x_rzp", "Razorpay /\nPaytm", 15),
        ("x_sms", "SMS /\nWhatsApp", 190),
        ("x_loc", "Amazon\nLocation Svc", 365),
        ("x_msg", "SES /\nPinpoint", 540),
    ]:
        b += vtx(cid, label, x, 34, 160, 44, STYLES["external"], parent="ext")

    # cross-cutting
    b += vtx("cross", "Zero-Trust Security & Observability (all layers)", 780, 790, 700, 90, CONTAINER)
    for cid, label, x in [
        ("o_iam", "IAM", 12), ("o_kms", "KMS", 127), ("o_sec", "Secrets Mgr", 242),
        ("o_cw", "CloudWatch", 357), ("o_xray", "X-Ray", 472), ("o_ct", "CloudTrail", 587),
    ]:
        b += vtx(cid, label, x, 34, 105, 44, STYLES["observ"], parent="cross")

    # edges (consolidated)
    b += edg("f1", "clients", "edge", "HTTPS", FLOW_EDGE)
    b += edg("f2", "a_gw", "alb", "private integration (VPC Link)", FLOW_EDGE)
    b += edg("f3", "alb", "sn_app", "route to services", FLOW_EDGE)
    b += edg("f4", "sn_app", "sn_data", "database-per-service", FLOW_EDGE)
    b += edg("f5", "sn_app", "sn_msg", "publish / consume (EventBridge, SQS, SNS, SFN)", FLOW_EDGE)
    b += edg("f6", "sn_app", "sn_vpce", "PrivateLink", THIN_EDGE)
    b += edg("f7", "sn_app", "nat", "outbound", THIN_EDGE)
    b += edg("f8", "nat", "ext", "egress", THIN_EDGE)
    b += edg("i1", "a_gw", "a_cog", "validate JWT", THIN_EDGE)
    b += edg("i2", "e_cf", "e_s3", "static", THIN_EDGE)

    return page("Architecture", "hld-arch", 1520, 920, b)


# ============================================================ HLD page 2 (DB per service)
def build_hld_dbps():
    b = ""
    b += vtx("t2", "Milkful - Database-per-Service (no shared database)", 40, 8, 1440, 34, STYLES["title"])
    note = (
        "Each microservice owns its datastore. A service NEVER connects to another service's "
        "database - it obtains data via published events or the owning service's API."
    )
    b += vtx("n_dbps", note, 40, 46, 1120, 40, STYLES["note"])
    # compute legend
    b += vtx("lg_far", "Fargate (always-on, behind ALB)", 1180, 46, 300, 20, SVC_FARGATE)
    b += vtx("lg_lam", "Lambda (event-driven, scale-to-zero)", 1180, 70, 300, 20, SVC_LAMBDA)

    cards = [
        ("Identity & Auth", "Amazon Cognito\n(user pool)", "api"),
        ("User Service", "Aurora: users db", "data"),
        ("Catalog Service", "Aurora: catalog db\n+ OpenSearch", "data"),
        ("Inventory Service", "Aurora: inventory db", "data"),
        ("Cart Service", "DynamoDB: cart (TTL)", "data"),
        ("Order Service", "Aurora: orders db", "data"),
        ("Subscription Service", "Aurora: subscriptions db", "data"),
        ("Payment Service", "Aurora: payments db", "data"),
        ("Wallet Service", "Aurora: wallet db (ledger)", "data"),
        ("Pricing & Offer Service", "Aurora: offers db\n+ Redis", "data"),
        ("Delivery Service", "Aurora: delivery db\n+ DynamoDB tracking", "data"),
        ("Notification Service", "DynamoDB: templates/logs", "data"),
        ("Reporting & Analytics", "OpenSearch + S3\n(CQRS read models)", "data"),
    ]
    cols = 4
    cw, ch = 340, 150
    x0, y0 = 40, 100
    gx, gy = 20, 24
    for i, (svc, db, sk) in enumerate(cards):
        r, c = divmod(i, cols)
        x = x0 + c * (cw + gx)
        y = y0 + r * (ch + gy)
        cardid = f"card{i}"
        compute = COMPUTE_TYPE.get(svc, "Fargate")
        b += vtx(cardid, svc, x, y, cw, ch, CONTAINER)
        b += vtx(f"svc{i}", f"{svc}\n[{compute}]", 20, 34, cw - 40, 40, svc_style(svc), parent=cardid)
        dbstyle = STYLES["data"] if sk == "data" else STYLES["api"]
        b += vtx(f"db{i}", db, 40, 88, cw - 80, 52, dbstyle, parent=cardid)
        b += edg(f"ce{i}", f"svc{i}", f"db{i}", "owns", THIN_EDGE)

    height = y0 + 4 * (ch + gy) + 20
    width = x0 + cols * (cw + gx) + 20
    return page("Database-per-Service", "hld-dbps", width, height, b)


# ============================================================ messaging topology
def build_messaging():
    b = ""
    b += vtx("tm", "Milkful - Event-Driven Messaging Topology (EventBridge | SQS+DLQ | SNS | Step Functions)", 40, 8, 1240, 34, STYLES["title"])

    producers = [
        ("p_ord", "Order Service"),
        ("p_pay", "Payment Service"),
        ("p_inv", "Inventory Service"),
        ("p_sub", "Subscription Service"),
        ("p_del", "Delivery Service"),
        ("p_usr", "User Service"),
        ("p_wal", "Wallet Service"),
    ]
    # queue rows: (queue id, queue label w/ events, consumer id, consumer label)
    rows = [
        ("q_ord", "order-events-q\n(PaymentConfirmed, PaymentFailed,\nSubscriptionOrderDue)", "co_ord", "Order Service"),
        ("q_inv", "inventory-events-q\n(OrderCancelled -> release)", "co_inv", "Inventory Service"),
        ("q_cat", "catalog-events-q\n(StockChanged)", "co_cat", "Catalog Service"),
        ("q_wal", "wallet-events-q\n(UserRegistered, OrderConfirmed,\nOrderCancelled)", "co_wal", "Wallet Service"),
        ("q_del", "delivery-events-q\n(OrderConfirmed)", "co_del", "Delivery Service"),
        ("q_not", "notification-events-q\n(OrderConfirmed, PaymentFailed,\nDeliveryStatusChanged, LowStock...)", "co_not", "Notification Service"),
        ("q_rpt", "reporting-events-q\n(all events - catch-all)", "co_rpt", "Reporting Service"),
    ]

    top = 90
    step = 76
    # column headers
    b += vtx("h_prod", "Producers (PutEvents)", 40, 58, 200, 24, STYLES["subtitle"])
    b += vtx("h_q", "SQS queues (per consumer)", 560, 58, 260, 24, STYLES["subtitle"])
    b += vtx("h_dlq", "DLQ", 840, 58, 90, 24, STYLES["subtitle"])
    b += vtx("h_con", "Consumers (poll)", 970, 58, 200, 24, STYLES["subtitle"])

    # EventBridge central bus
    bus_h = len(rows) * step + 4
    b += vtx("eb", "Amazon\nEventBridge\n\n'milkful-events'\nbus + rules", 300, top, 150, bus_h, STYLES["eb"])

    # producers (left)
    for i, (pid, label) in enumerate(producers):
        y = top + i * step
        b += vtx(pid, label, 40, y, 200, 44, STYLES["service"])
        b += edg(f"ep_{i}", pid, "eb", "", THIN_EDGE)

    # queues + dlq + consumers (right)
    for i, (qid, qlabel, coid, colabel) in enumerate(rows):
        y = top + i * step
        b += vtx(qid, qlabel, 560, y, 260, 56, STYLES["sqs"])
        b += vtx(f"dlq_{i}", "DLQ", 840, y + 6, 90, 44, STYLES["dlq"])
        b += vtx(coid, colabel, 970, y + 4, 200, 44, STYLES["service"])
        b += edg(f"eq_{i}", "eb", qid, "rule", THIN_EDGE)
        b += edg(f"qc_{i}", qid, coid, "poll", EDGE_STYLE)
        b += edg(f"qd_{i}", qid, f"dlq_{i}", "", THIN_EDGE)

    # SNS fan-out container
    sns_y = top + len(rows) * step + 20
    b += vtx("snsbox", "SNS Fan-out (last-mile notifications + OTP)", 40, sns_y, 1130, 130, CONTAINER)
    b += vtx("nsvc", "Notification\nService", 20, 40, 170, 44, STYLES["service"], parent="snsbox")
    b += vtx("t_sms", "sns-sms topic", 260, 30, 160, 34, STYLES["sns"], parent="snsbox")
    b += vtx("t_push", "sns-push topic", 260, 78, 160, 34, STYLES["sns"], parent="snsbox")
    b += vtx("pr_sms", "SMS / WhatsApp", 500, 30, 180, 34, STYLES["external"], parent="snsbox")
    b += vtx("pr_push", "Amazon Pinpoint (push)", 500, 78, 200, 34, STYLES["external"], parent="snsbox")
    b += vtx("pr_ses", "Amazon SES (email)", 760, 54, 200, 34, STYLES["external"], parent="snsbox")
    b += edg("sns1", "nsvc", "t_sms", "publish", THIN_EDGE)
    b += edg("sns2", "nsvc", "t_push", "publish", THIN_EDGE)
    b += edg("sns3", "t_sms", "pr_sms", "", THIN_EDGE)
    b += edg("sns4", "t_push", "pr_push", "", THIN_EDGE)
    b += edg("sns5", "nsvc", "pr_ses", "email", THIN_EDGE)

    # Step Functions container
    sfn_y = sns_y + 150
    b += vtx("sfnbox", "AWS Step Functions - Orchestration / Saga", 40, sfn_y, 1130, 150, CONTAINER)
    b += vtx("sf1", "Order Saga", 20, 40, 350, 44, STYLES["sfn"], parent="sfnbox")
    b += vtx("sf1c", "Reserve (Inventory) -> Charge (Payment/Wallet) -> Confirm (Order); compensate on failure (release stock, refund).", 20, 90, 350, 46, STYLES["note"], parent="sfnbox")
    b += vtx("sf2", "Subscription Daily Run", 390, 40, 350, 44, STYLES["sfn"], parent="sfnbox")
    b += vtx("sf2c", "EventBridge Scheduler (pre-cutoff) -> get due (Subscription) -> create orders (Order) -> auto-debit (Wallet) -> notify.", 390, 90, 350, 46, STYLES["note"], parent="sfnbox")
    b += vtx("sf3", "Refund Workflow", 760, 40, 350, 44, STYLES["sfn"], parent="sfnbox")
    b += vtx("sf3c", "On cancellation: Wallet refund + gateway refund + Notification.", 760, 90, 350, 46, STYLES["note"], parent="sfnbox")

    height = sfn_y + 150 + 40
    return page("Messaging Topology", "msg-topo", 1240, height, b)


# ============================================================ LLD sequence builder
def build_sequence(name, pid, participants, messages):
    spacing = 200
    box_w = 150
    left = 40
    header_y = 50
    header_h = 44
    start_y = 150
    step = 54

    centers = {}
    for i, (key, _) in enumerate(participants):
        centers[key] = left + i * spacing + box_w / 2

    life_h = start_y + len(messages) * step + 30
    total_w = left + (len(participants) - 1) * spacing + box_w + 60
    total_h = header_y + life_h + 60

    b = ""
    b += vtx("t_" + pid, name, 20, 8, total_w - 40, 30, STYLES["title"])

    for key, label in participants:
        cx = centers[key]
        comp = LLD_COMPUTE.get(label)
        fill = "#ffe6cc" if comp == "Lambda" else "#dae8fc"
        stroke = "#d79b00" if comp == "Lambda" else "#6c8ebf"
        disp = label + (f"\n({comp})" if comp else "")
        style = (
            "shape=umlLifeline;perimeter=lifelinePerimeter;whiteSpace=wrap;html=1;"
            "container=0;collapsible=0;recursiveResize=0;outlineConnect=0;"
            f"fillColor={fill};strokeColor={stroke};fontSize=11;fontStyle=1;size=" + str(header_h) + ";"
        )
        b += vtx(f"{pid}_ll_{key}", disp, int(cx - box_w / 2), header_y, box_w, int(life_h), style)

    for idx, (fk, tk, label, kind) in enumerate(messages):
        y = start_y + idx * step
        x1 = centers[fk]
        x2 = centers[tk]
        if kind == "return":
            estyle = "html=1;endArrow=open;dashed=1;strokeColor=#b85450;fontSize=10;endFill=0;"
        elif kind == "async":
            estyle = "html=1;endArrow=open;dashed=0;strokeColor=#2d6a4f;fontSize=10;"
        else:
            estyle = "html=1;endArrow=block;dashed=0;strokeColor=#333333;fontSize=10;"
        eid = f"{pid}_m{idx}"
        b += (
            f'        <mxCell id="{eid}" value="{escape(label)}" style="{estyle}" '
            f'edge="1" parent="1">\n'
            f'          <mxGeometry relative="1" as="geometry">\n'
            f'            <mxPoint x="{int(x1)}" y="{y}" as="sourcePoint" />\n'
            f'            <mxPoint x="{int(x2)}" y="{y}" as="targetPoint" />\n'
            f"          </mxGeometry>\n"
            f"        </mxCell>\n"
        )
    return page(name, pid, int(total_w), int(total_h), b)


def build_lld():
    pages = []

    # Flow 1: Order Placement (with Step Functions saga + EventBridge -> SQS)
    p1 = [
        ("U", "Customer App"), ("GW", "API Gateway"), ("O", "Order Service"),
        ("SF", "Step Functions\n(Order Saga)"), ("I", "Inventory Svc"),
        ("P", "Payment Svc"), ("PG", "Payment Gateway"),
        ("EB", "EventBridge"), ("Q", "SQS queues"), ("N", "Notification"),
    ]
    m1 = [
        ("U", "GW", "POST /orders (cart) + JWT", "sync"),
        ("GW", "O", "Create order (idempotency-key)", "sync"),
        ("O", "SF", "Start Order Saga", "sync"),
        ("SF", "I", "Reserve stock", "sync"),
        ("I", "SF", "Reserved OK", "return"),
        ("SF", "P", "Charge (wallet-first + gateway)", "sync"),
        ("P", "PG", "Charge remainder (UPI/card)", "sync"),
        ("PG", "P", "Success (ref)", "return"),
        ("P", "SF", "PaymentConfirmed", "return"),
        ("SF", "O", "Confirm order (or compensate)", "return"),
        ("O", "EB", "Publish OrderConfirmed", "async"),
        ("EB", "Q", "Rules route to queues", "async"),
        ("Q", "N", "notification-events-q (poll)", "async"),
        ("N", "U", "Push/SMS confirmation + ETA", "async"),
    ]
    pages.append(build_sequence("1. Order Placement (Saga)", "lld1", p1, m1))

    # Flow 2: Subscription
    p2 = [
        ("U", "Customer App"), ("GW", "API Gateway"), ("S", "Subscription Svc"),
        ("DB", "subscriptions db"), ("SCH", "EventBridge Sched"), ("SFN", "Step Functions"),
        ("O", "Order Service"), ("W", "Wallet"), ("EB", "EventBridge"),
        ("Q", "SQS"), ("N", "Notification"),
    ]
    m2 = [
        ("U", "GW", "Create subscription", "sync"),
        ("GW", "S", "POST /subscriptions", "sync"),
        ("S", "DB", "Save (ACTIVE)", "sync"),
        ("S", "U", "Active", "return"),
        ("SCH", "SFN", "Daily trigger (pre-cutoff)", "async"),
        ("SFN", "S", "Get due subscriptions", "sync"),
        ("S", "EB", "Publish SubscriptionOrderDue", "async"),
        ("EB", "Q", "order-events-q (rule)", "async"),
        ("Q", "O", "poll -> generate orders", "async"),
        ("O", "W", "Auto-debit wallet", "sync"),
        ("O", "N", "Order created / low-balance", "async"),
        ("N", "U", "Notify", "async"),
    ]
    pages.append(build_sequence("2. Subscription Mgmt", "lld2", p2, m2))

    # Flow 3: Inventory
    p3 = [
        ("SF", "Order Saga"), ("I", "Inventory Svc"), ("DB", "inventory db"),
        ("R", "Redis"), ("EB", "EventBridge"), ("Q", "catalog-events-q"),
        ("C", "Catalog Svc"), ("OS", "OpenSearch"), ("A", "Admin Panel"),
    ]
    m3 = [
        ("SF", "I", "Reserve(items)", "sync"),
        ("I", "DB", "reserved += qty (own DB)", "sync"),
        ("I", "R", "Update cached stock", "async"),
        ("I", "SF", "Reserved", "return"),
        ("SF", "I", "Commit on payment success", "sync"),
        ("I", "DB", "on_hand -= qty", "sync"),
        ("I", "EB", "Publish StockChanged", "async"),
        ("EB", "Q", "route (rule)", "async"),
        ("Q", "C", "poll", "async"),
        ("C", "OS", "Update product index", "sync"),
        ("A", "I", "Manual adjust (+audit)", "sync"),
        ("I", "DB", "adjust + audit log", "sync"),
    ]
    pages.append(build_sequence("3. Inventory Update", "lld3", p3, m3))

    # Flow 4: Delivery
    p4 = [
        ("EB", "EventBridge"), ("Q", "delivery-events-q"), ("D", "Delivery Svc"),
        ("DB", "delivery db"), ("LOC", "Location Service"), ("DDB", "DynamoDB (tracking)"),
        ("DP", "Partner App"), ("N", "Notification"), ("U", "Customer App"),
    ]
    m4 = [
        ("EB", "Q", "OrderConfirmed (rule)", "async"),
        ("Q", "D", "poll", "async"),
        ("D", "DB", "Fetch orders by zone/slot", "sync"),
        ("D", "LOC", "Optimize routes", "sync"),
        ("LOC", "D", "Optimized routes", "return"),
        ("D", "DB", "Save delivery + route", "sync"),
        ("D", "DDB", "Live tracking (TTL)", "sync"),
        ("D", "N", "Assign run to partner", "async"),
        ("N", "DP", "New delivery run", "async"),
        ("DP", "D", "Out for delivery + GPS", "sync"),
        ("D", "DDB", "Update location/status", "sync"),
        ("D", "N", "DeliveryStatusChanged", "async"),
        ("N", "U", "Out for delivery + ETA", "async"),
        ("DP", "D", "Delivered + proof (OTP/photo)", "sync"),
        ("D", "DB", "Mark DELIVERED", "sync"),
    ]
    pages.append(build_sequence("4. Delivery Assignment", "lld4", p4, m4))

    return wrap(pages)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    hld = wrap([build_hld_arch(), build_hld_dbps()])
    messaging = wrap([build_messaging()])
    lld = build_lld()

    outputs = {
        "milkful-hld.drawio": hld,
        "milkful-messaging.drawio": messaging,
        "milkful-lld.drawio": lld,
    }
    for fname, content in outputs.items():
        path = os.path.join(OUT_DIR, fname)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print("Wrote", path)


if __name__ == "__main__":
    main()
