"""Generate a single, modern Milkful architecture diagram using AWS icons.

Design goals (per user feedback):
  * Use real AWS icons (mxgraph.aws4.*) instead of plain boxes.
  * Clear, NON-OVERLAPPING in/out arrows per service:
      - Each service sits on its OWN ROW.
      - DATA (grey) leaves the LEFT side  -> its own database.
      - PUBLISH (green) leaves the RIGHT side -> central EventBridge bus.
      - CONSUME (orange) enters the TOP  <- its own SQS queue (fed by EventBridge).
      - SYNC (blue) is consolidated at the top (API Gateway -> internal ALB -> all services).
    Because every flow type uses a different side and every service owns a row,
    lines run parallel and do not cross.

Output: docs/design/milkful-architecture.drawio
Run:    python scripts/design/generate_combined.py
"""
import os
from xml.sax.saxutils import escape

OUT_DIR = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "..", "docs", "design")
)

# ---- AWS icon helper -------------------------------------------------------
_PTS = ("[[0,0,0],[0.25,0,0],[0.5,0,0],[0.75,0,0],[1,0,0],[0,1,0],[0.25,1,0],"
        "[0.5,1,0],[0.75,1,0],[1,1,0],[0,0.25,0],[0,0.5,0],[0,0.75,0],"
        "[1,0.25,0],[1,0.5,0],[1,0.75,0]]")

# category (fill, gradient)
COMPUTE = ("#D05C17", "#F78E04")
INTEG = ("#BC1356", "#F34482")
DB = ("#3334B9", "#4D72F3")
NET = ("#5A30B5", "#945DF2")
SEC = ("#BB0816", "#F54749")
STORAGE = ("#277116", "#60A337")
ANALYTICS = ("#4D27AA", "#945DF2")
GENERAL = ("#232F3E", "#5A6B86")


def aws(res, cat, fontsize=10):
    fill, grad = cat
    return (f"sketch=0;points={_PTS};outlineConnect=0;fontColor=#232F3E;"
            f"gradientColor={grad};gradientDirection=north;fillColor={fill};"
            f"strokeColor=#ffffff;dashed=0;verticalLabelPosition=bottom;"
            f"verticalAlign=top;align=center;html=1;fontSize={fontsize};fontStyle=0;"
            f"aspect=fixed;shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{res};")


# container / misc styles
S_TITLE = "text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;fontStyle=1;fontSize=22;"
S_SUB = "text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;fontSize=13;fontColor=#555555;"
S_VPC = ("rounded=1;whiteSpace=wrap;html=1;fillColor=#F2F8FD;strokeColor=#2D6A9F;"
         "dashed=0;verticalAlign=top;align=left;fontStyle=1;fontSize=14;fontColor=#1B4B73;"
         "spacingLeft=14;spacingTop=10;")
S_EBBUS = ("rounded=1;whiteSpace=wrap;html=1;fillColor=#FCE4EF;strokeColor=#BC1356;"
           "dashed=0;verticalAlign=top;align=center;fontStyle=1;fontSize=12;fontColor=#8C0F45;"
           "spacingTop=64;")
S_ALB = "rounded=1;whiteSpace=wrap;html=1;fillColor=#E9F3E6;strokeColor=#277116;fontSize=11;fontColor=#1a4d10;"
S_EXT = "rounded=1;whiteSpace=wrap;html=1;fillColor=#f5f5f5;strokeColor=#666666;fontSize=10;dashed=1;"
S_NOTE = ("shape=note;whiteSpace=wrap;html=1;fillColor=#FFF8E1;strokeColor=#D6B656;"
          "fontSize=11;align=left;verticalAlign=top;spacingLeft=8;spacingTop=6;size=16;")

# edge styles
E_SYNC = ("edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;"
          "strokeColor=#1565C0;strokeWidth=2.5;fontSize=10;fontColor=#1565C0;"
          "labelBackgroundColor=#ffffff;")
E_PUB = ("edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=block;"
         "strokeColor=#2E7D32;strokeWidth=2;fontSize=9;fontColor=#2E7D32;"
         "labelBackgroundColor=#ffffff;exitX=1;exitY=0.5;exitDx=0;exitDy=0;")
E_CONS = ("edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=block;"
          "strokeColor=#E65100;strokeWidth=2;fontSize=9;fontColor=#E65100;"
          "labelBackgroundColor=#ffffff;entryX=0.5;entryY=0;entryDx=0;entryDy=0;")
E_RULE = ("edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=open;dashed=1;"
          "strokeColor=#B0870A;strokeWidth=1.5;fontSize=8;fontColor=#B0870A;"
          "labelBackgroundColor=#ffffff;")
E_DATA = ("edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;startArrow=block;endArrow=block;"
          "startFill=1;strokeColor=#546E7A;strokeWidth=1.5;fontSize=9;fontColor=#546E7A;"
          "labelBackgroundColor=#ffffff;exitX=0;exitY=0.5;exitDx=0;exitDy=0;")
E_EXT = ("edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;dashed=1;"
         "strokeColor=#8E24AA;strokeWidth=2;fontSize=9;fontColor=#8E24AA;"
         "labelBackgroundColor=#ffffff;")
E_PLAIN = ("edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;"
           "strokeColor=#607D8B;strokeWidth=1.5;fontSize=9;fontColor=#455A64;"
           "labelBackgroundColor=#ffffff;")


def vtx(cid, value, x, y, w, h, style, parent="1"):
    return (
        f'        <mxCell id="{cid}" value="{escape(value)}" style="{style}" vertex="1" parent="{parent}">\n'
        f'          <mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry" />\n'
        f"        </mxCell>\n"
    )


def edg(eid, src, tgt, value, style):
    return (
        f'        <mxCell id="{eid}" value="{escape(value)}" style="{style}" edge="1" parent="1" source="{src}" target="{tgt}">\n'
        f'          <mxGeometry relative="1" as="geometry" />\n'
        f"        </mxCell>\n"
    )


def build():
    b = ""
    b += vtx("title", "Milkful - AWS Cloud Architecture", 40, 16, 1560, 32, S_TITLE)
    b += vtx("subtitle",
             "Event-driven microservices  -  hybrid compute (Lambda + Fargate)  -  clear IN / OUT per service  -  database-per-service  -  zero-trust VPC",
             40, 50, 1560, 24, S_SUB)

    # ---- legend ----
    legend = ("LINE COLOURS\n"
              "BLUE  = sync request IN (API Gateway - JWT)\n"
              "GREEN = publish event OUT -> EventBridge\n"
              "ORANGE = consume IN <- SQS queue\n"
              "GREY  = own database read / write\n"
              "PURPLE = external call (egress via NAT)\n"
              "\n"
              "COMPUTE\n"
              "Lambda  = event-driven / bursty (scale-to-zero)\n"
              "Fargate = always-on / latency-sensitive (behind ALB)")
    b += vtx("legend", legend, 1180, 92, 400, 180, S_NOTE)

    # ---- top: clients + edge + api (sync request path) ----
    # Clean LEFT-TO-RIGHT chain; auth/protection sit on a 2nd row, OFF the
    # vertical sync path so nothing overlaps.
    y_top, y2 = 120, 214
    b += vtx("cust", "Customer &\nDelivery apps", 70, y_top, 52, 52, aws("client", GENERAL))
    b += vtx("admin", "Admin & B2B\n(React)", 70, y2, 52, 52, aws("users", GENERAL))
    b += vtx("r53", "Route 53", 210, y_top, 52, 52, aws("route_53", NET))
    b += vtx("cf", "CloudFront", 350, y_top, 52, 52, aws("cloudfront", NET))
    b += vtx("shield", "AWS Shield", 350, y2, 52, 52, aws("shield", SEC))
    b += vtx("waf", "AWS WAF", 490, y_top, 52, 52, aws("waf", SEC))
    b += vtx("cognito", "Cognito\n(JWT authorizer)", 490, y2, 52, 52, aws("cognito", SEC))
    b += vtx("apigw", "API Gateway", 630, y_top, 52, 52, aws("api_gateway", NET))

    HZ = ("exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;")
    b += edg("t1", "cust", "r53", "HTTPS", E_SYNC + HZ)
    b += edg("t2", "admin", "r53", "", E_SYNC +
             "exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.85;entryDx=0;entryDy=0;")
    b += edg("t3", "r53", "cf", "DNS", E_SYNC + HZ)
    b += edg("t4", "cf", "waf", "", E_SYNC + HZ)
    b += edg("t5", "waf", "apigw", "", E_SYNC + HZ)
    b += edg("t6", "cognito", "apigw", "verify JWT", E_PLAIN +
             "dashed=1;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.85;entryDx=0;entryDy=0;")
    b += edg("t7", "shield", "cf", "protects", E_PLAIN +
             "dashed=1;exitX=0.5;exitY=0;exitDx=0;exitDy=0;entryX=0.5;entryY=1;entryDx=0;entryDy=0;")

    # ---- VPC container ----
    vpc_x, vpc_y, vpc_w, vpc_h = 40, 300, 1540, 1990
    b += vtx("vpc",
             "Amazon VPC   -   private subnets  |  zero-trust (IAM role per service, VPC endpoints, mTLS)  |  stateless services  |  database-per-service",
             vpc_x, vpc_y, vpc_w, vpc_h, S_VPC)

    # internal ALB rail (sync fan-out target)
    alb_x, alb_y, alb_w = 300, 340, 620
    b += vtx("alb", "VPC Link  ->  Internal ALB   (fronts Fargate services  |  API Gateway invokes Lambda directly)",
             alb_x, alb_y, alb_w, 34, S_ALB)
    # single clean VERTICAL arrow: API Gateway bottom -> ALB top (aligned x)
    b += edg("sync_main", "apigw", "alb", "authorized REST - JWT (stateless)",
             E_SYNC + "exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.574;entryY=0;entryDx=0;entryDy=0;")

    # ---- EventBridge central bus (tall) ----
    n = 13
    row0 = 460
    step = 132
    svc_x, svc_w, svc_h = 560, 52, 46
    db_x, db_w = 330, 70
    sqs_x, sqs_sz = 872, 36
    eb_x, eb_w = 940, 170
    eb_y = 440
    eb_h = (n - 1) * step + svc_h + 90
    b += vtx("ebbus", "Amazon EventBridge\nmilkful-events bus + rules", eb_x, eb_y, eb_w, eb_h, S_EBBUS)
    b += vtx("ebicon", "", eb_x + eb_w / 2 - 26, eb_y + 6, 52, 52, aws("eventbridge", INTEG))

    # ---- services (each on its own row) ----
    # (name, res_icon, cat, db_label, db_icon, db_cat, publishes, consume_queue)
    # Compute choice per service (hybrid):
    #   lambda  = event-driven / bursty / glue (scale-to-zero, native EventBridge+SQS)
    #   fargate = always-on / latency-sensitive / long-lived conns / steady load (behind ALB)
    services = [
        ("Identity & Auth", "lambda", COMPUTE, "Cognito user pools", "cognito", SEC, None, None),
        ("User Service", "lambda", COMPUTE, "users (DynamoDB)", "dynamodb", DB, "UserRegistered", None),
        ("Catalog Service", "fargate", COMPUTE, "catalog (RDS) + OpenSearch", "rds", DB, None, "catalog-events-q"),
        ("Pricing & Offer", "fargate", COMPUTE, "offers + Redis", "elasticache", DB, None, None),
        ("Cart Service", "lambda", COMPUTE, "cart (DynamoDB TTL)", "dynamodb", DB, None, None),
        ("Order Service", "fargate", COMPUTE, "orders (Aurora)", "aurora", DB, "OrderPlaced / Confirmed / Cancelled", "order-events-q"),
        ("Subscription Service", "lambda", COMPUTE, "subscriptions (Aurora)", "aurora", DB, "SubscriptionOrderDue", None),
        ("Payment Service", "fargate", COMPUTE, "payments (Aurora)", "aurora", DB, "PaymentConfirmed / Failed", None),
        ("Wallet Service", "fargate", COMPUTE, "wallet (Aurora)", "aurora", DB, "WalletLowBalance", "wallet-events-q"),
        ("Inventory Service", "fargate", COMPUTE, "inventory (Aurora)", "aurora", DB, "StockChanged / LowStock", "inventory-events-q"),
        ("Delivery Service", "fargate", COMPUTE, "delivery (DynamoDB)", "dynamodb", DB, "DeliveryStatusChanged", "delivery-events-q"),
        ("Reporting & Analytics", "fargate", COMPUTE, "OpenSearch + S3", "opensearch_service", ANALYTICS, None, "reporting-events-q"),
        ("Notification Service", "lambda", COMPUTE, "notif log (DynamoDB)", "dynamodb", DB, None, "notification-events-q"),
    ]

    def eb_frac(abs_y):
        """Fraction along the EventBridge left edge for a given absolute Y."""
        f = (abs_y - eb_y) / eb_h
        return max(0.02, min(0.98, f))

    # per service: DATA on LEFT, PUBLISH upper-right lane, CONSUME lower-right lane.
    # SQS icons hug the EventBridge bus so the corridor has no obstacles.
    for i, (name, res, cat, dbl, dbi, dbc, pub, cons) in enumerate(services):
        y = row0 + i * step
        sid = f"svc{i}"
        did = f"db{i}"
        pub_y = y + 0.12 * svc_h      # upper-right anchor
        con_y = y + 0.85 * svc_h      # lower-right anchor
        b += vtx(sid, name, svc_x, y, svc_w, svc_h, aws(res, cat))
        b += vtx(did, dbl, db_x, y - 2, db_w, svc_h + 4, aws(dbi, dbc, fontsize=9))
        # DATA (grey) service LEFT <-> its DB
        b += edg(f"d{i}", sid, did, "R/W",
                 E_DATA + "entryX=1;entryY=0.5;entryDx=0;entryDy=0;")
        # PUBLISH (green) service UPPER-right -> EventBridge (straight horizontal)
        if pub:
            style = (E_PUB.replace("exitY=0.5", "exitY=0.12")
                     + f"entryX=0;entryY={eb_frac(pub_y):.4f};entryDx=0;entryDy=0;")
            b += edg(f"p{i}", sid, "ebbus", "OUT: " + pub, style)
        # CONSUME (orange) EventBridge -> SQS (hugging bus) -> service LOWER-right
        if cons:
            qid = f"q{i}"
            qy = con_y - sqs_sz / 2
            b += vtx(qid, cons, sqs_x, qy, sqs_sz, sqs_sz,
                     aws("simple_queue_service_sqs", INTEG, fontsize=8))
            rule_style = (E_RULE + f"exitX=0;exitY={eb_frac(con_y):.4f};exitDx=0;exitDy=0;"
                          "entryX=1;entryY=0.5;entryDx=0;entryDy=0;")
            b += edg(f"r{i}", "ebbus", qid, "rule", rule_style)
            cons_style = (E_CONS.replace("entryX=0.5;entryY=0", "entryX=1;entryY=0.85")
                          + "exitX=0;exitY=0.5;exitDx=0;exitDy=0;")
            b += edg(f"c{i}", qid, sid, "IN", cons_style)

    last_y = row0 + (n - 1) * step  # bottom-most service (Notification)

    # ---- Step Functions (orchestration) top-right, beside EB top ----
    b += vtx("sfn", "Step Functions\n(Order Saga | Sub Daily Run | Refund)",
             eb_x + eb_w + 70, eb_y + 2, 60, 60, aws("step_functions", INTEG, fontsize=9))
    b += edg("sfn1", "sfn", "ebbus", "orchestrate / compensate",
             E_PLAIN + "dashed=1;exitX=0;exitY=0.5;exitDx=0;exitDy=0;entryX=1;entryY=0.03;entryDx=0;entryDy=0;")

    # ---- bottom band (inside VPC): NAT egress + SNS fan-out + notes ----
    band_y = last_y + 95          # comfortably below the last service row

    # NAT gateway (egress) below the DB column
    b += vtx("nat", "NAT Gateway", 330, band_y, 52, 52, aws("nat_gateway", NET))

    # SNS fan-out fed by Notification service (bottom service -> straight down)
    b += vtx("sns", "Amazon SNS\n(sms / push)", 470, band_y, 56, 56,
             aws("simple_notification_service_sns", INTEG, fontsize=9))
    b += vtx("prov", "SMS / WhatsApp  -  Pinpoint (push)  -  SES (email)",
             560, band_y - 2, 300, 60, S_EXT)
    b += edg("sns1", f"svc{n-1}", "sns", "publish",
             E_PUB.replace("exitX=1;exitY=0.5;exitDx=0;exitDy=0;", "exitX=0.5;exitY=1;exitDx=0;exitDy=0;"))
    b += edg("sns2", "sns", "prov", "fan-out", E_EXT)

    b += vtx("extnote",
             "Outbound (via NAT):\nPayment -> Razorpay/Paytm\nDelivery -> Amazon Location",
             890, band_y - 2, 230, 62, S_NOTE)

    # ---- observability / cross-cutting note (bottom-right, inside VPC) ----
    obs = ("Cross-cutting (all services):\n"
           "- IAM least-privilege role per service, KMS, Secrets Manager\n"
           "- VPC endpoints (SQS / SNS / EventBridge / S3 / DynamoDB)\n"
           "- Observability: CloudWatch, X-Ray, CloudTrail\n"
           "- Every SQS queue has a Dead-Letter Queue (DLQ)  -  Multi-AZ")
    b += vtx("obs", obs, 1150, band_y - 8, 430, 132, S_NOTE)

    # ---- External systems (OUTSIDE the VPC) ----
    ext_y = vpc_y + vpc_h + 40
    b += vtx("rzp", "Razorpay / Paytm\n(payment gateway)", 330, ext_y, 200, 56, S_EXT)
    b += vtx("loc", "Amazon Location Service\n(maps / geocoding / routing)", 560, ext_y, 240, 56, S_EXT)
    b += edg("x0", "nat", "rzp", "", E_EXT + "exitX=0.5;exitY=1;exitDx=0;exitDy=0;")
    b += edg("x3", "nat", "loc", "", E_EXT + "exitX=0.5;exitY=1;exitDx=0;exitDy=0;")

    return page("Milkful Architecture", "arch", 1620, ext_y + 120, b)


def page(name, pid, width, height, body):
    return (
        f'  <diagram name="{escape(name)}" id="{pid}">\n'
        f'    <mxGraphModel dx="1400" dy="900" grid="0" gridSize="10" guides="1" '
        f'tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" '
        f'pageWidth="{int(width)}" pageHeight="{int(height)}" math="0" shadow="0">\n'
        f"      <root>\n"
        f'        <mxCell id="0" />\n        <mxCell id="1" parent="0" />\n'
        f"{body}"
        f"      </root>\n    </mxGraphModel>\n  </diagram>\n"
    )


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    content = '<mxfile host="app.diagrams.net" type="device">\n' + build() + "</mxfile>\n"
    path = os.path.join(OUT_DIR, "milkful-architecture.drawio")
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Wrote", path)


if __name__ == "__main__":
    main()
