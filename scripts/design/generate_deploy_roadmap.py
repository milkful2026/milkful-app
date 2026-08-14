"""Generate importable draw.io files for the Milkful AWS deployment view and roadmap.

Outputs:
  docs/design/milkful-deployment.drawio  - AWS deployment architecture (1 page)
  docs/design/milkful-roadmap.drawio     - deployment roadmap Gantt (1 page)

Run:  python scripts/design/generate_deploy_roadmap.py
"""
import os
from xml.sax.saxutils import escape

OUT_DIR = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "..", "docs", "design")
)

STYLES = {
    "client": "rounded=1;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontSize=12;",
    "edge_svc": "rounded=1;whiteSpace=wrap;html=1;fillColor=#ffe6cc;strokeColor=#d79b00;fontSize=12;",
    "api": "rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontSize=12;",
    "compute": "rounded=1;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;fontSize=12;",
    "msg": "rounded=1;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;fontSize=12;",
    "data": "shape=cylinder3;whiteSpace=wrap;html=1;boundedLbl=1;backgroundOutline=1;size=14;fillColor=#f8cecc;strokeColor=#b85450;fontSize=12;",
    "external": "rounded=1;whiteSpace=wrap;html=1;fillColor=#f5f5f5;strokeColor=#666666;fontSize=12;",
    "sec": "rounded=1;whiteSpace=wrap;html=1;fillColor=#ffe6cc;strokeColor=#d79b00;fontSize=11;",
    "mon": "rounded=1;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontSize=11;",
    "group": "rounded=0;whiteSpace=wrap;html=1;fillColor=none;strokeColor=#9aa5b1;dashed=1;verticalAlign=top;align=left;fontStyle=1;fontSize=13;fontColor=#5b6570;spacingLeft=8;spacingTop=6;",
    "title": "text;html=1;strokeColor=none;fillColor=none;align=center;verticalAlign=middle;fontStyle=1;fontSize=20;",
}

EDGE_STYLE = "edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;strokeColor=#4a5568;fontSize=10;"


def vertex(cid, value, x, y, w, h, style):
    return (
        f'        <mxCell id="{cid}" value="{escape(value)}" style="{style}" '
        f'vertex="1" parent="1">\n'
        f'          <mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry" />\n'
        f"        </mxCell>\n"
    )


def edge(eid, source, target, value=""):
    return (
        f'        <mxCell id="{eid}" value="{escape(value)}" style="{EDGE_STYLE}" '
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


# ============================================================ deployment diagram
def build_deployment():
    b = ""
    b += vertex("title", "Milkful - AWS Deployment Architecture", 20, 8, 1200, 30, STYLES["title"])

    # groups
    b += vertex("g_client", "Client", 40, 60, 780, 90, STYLES["group"])
    b += vertex("g_mon", "Monitoring", 900, 470, 320, 90, STYLES["group"])
    b += vertex("g_sec", "Security", 900, 590, 320, 150, STYLES["group"])

    nodes = [
        # clients
        ("user", "Mobile / Web App", 70, 90, 220, 50, "client"),
        ("del", "Delivery Partner App", 320, 90, 220, 50, "client"),
        ("admin", "Admin Dashboard", 570, 90, 220, 50, "client"),
        # edge
        ("cf", "Amazon CloudFront", 70, 200, 200, 50, "edge_svc"),
        ("s3", "Amazon S3\n(Static Hosting)", 70, 300, 200, 60, "data"),
        # api + auth
        ("apigw", "Amazon API Gateway", 420, 200, 220, 50, "api"),
        ("cog", "Amazon Cognito\n(Auth)", 420, 300, 220, 60, "api"),
        # compute
        ("lord", "Lambda: Order Service", 380, 420, 220, 55, "compute"),
        ("lpay", "Lambda: Payment Service", 640, 420, 220, 55, "compute"),
        # data
        ("rds", "Amazon RDS", 120, 560, 170, 80, "data"),
        ("ddb", "Amazon DynamoDB", 320, 560, 170, 80, "data"),
        ("ec", "ElastiCache\nRedis", 520, 560, 170, 80, "data"),
        # messaging
        ("sns", "Amazon SNS", 380, 700, 190, 50, "msg"),
        ("pin", "Amazon Pinpoint", 380, 790, 190, 50, "msg"),
        # external / location
        ("loc", "Amazon Location Service", 640, 560, 220, 55, "edge_svc"),
        ("rzp", "External Payment Gateway\n(Razorpay)", 900, 420, 260, 55, "external"),
        # monitoring
        ("cw", "Amazon CloudWatch", 920, 500, 130, 45, "mon"),
        ("xray", "AWS X-Ray", 1070, 500, 130, 45, "mon"),
        # security
        ("iam", "AWS IAM", 920, 620, 130, 45, "sec"),
        ("waf", "AWS WAF", 1070, 620, 130, 45, "sec"),
        ("shield", "AWS Shield", 995, 680, 130, 45, "sec"),
    ]
    for cid, label, x, y, w, h, sk in nodes:
        b += vertex(cid, label, x, y, w, h, STYLES[sk])

    edges = [
        ("user", "cf"), ("cf", "s3"),
        ("user", "apigw"), ("del", "apigw"), ("admin", "apigw"),
        ("apigw", "cog"), ("apigw", "lord"), ("apigw", "lpay"),
        ("lord", "rds"), ("lord", "ddb"), ("lord", "ec"),
        ("lpay", "rzp"),
        ("lord", "sns"), ("sns", "pin"),
        ("lord", "loc"),
        ("lord", "cw"), ("lpay", "cw"), ("apigw", "xray"),
        ("apigw", "waf"), ("cf", "shield"), ("cog", "iam"),
    ]
    for i, (s, t) in enumerate(edges):
        b += edge(f"de{i}", s, t)

    return page("Deployment", "deploy-page", 1260, 880, b)


# ================================================================ roadmap gantt
SECTIONS = [
    ("Week 1 - Foundation & Security", "#dae8fc", "#6c8ebf", [
        ("IAM & Roles Setup", 0, 7),
        ("WAF & Shield Configuration", 7, 7),
    ]),
    ("Week 2 - Frontend Hosting", "#d5e8d4", "#82b366", [
        ("S3 Bucket + CloudFront", 14, 7),
        ("SSL/TLS Certificates", 21, 3),
        ("Deploy Initial Frontend", 24, 4),
    ]),
    ("Week 3 - Authentication", "#ffe6cc", "#d79b00", [
        ("Cognito User Pools", 28, 7),
        ("API Gateway Integration", 35, 5),
        ("JWT Flow Testing", 40, 2),
    ]),
    ("Week 4 - Backend APIs", "#e1d5e7", "#9673a6", [
        ("API Gateway Endpoints", 42, 7),
        ("Lambda Functions", 49, 7),
        ("Connect to RDS/DynamoDB", 56, 4),
        ("ElastiCache Setup", 60, 3),
    ]),
    ("Week 5 - Database & Storage", "#fff2cc", "#d6b656", [
        ("RDS Schema Finalization", 63, 7),
        ("DynamoDB Config", 70, 5),
        ("S3 Storage Setup", 75, 3),
        ("Backups & Multi-AZ", 78, 2),
    ]),
    ("Week 6 - Payments & Delivery", "#f8cecc", "#b85450", [
        ("Payment Gateway Integration", 80, 7),
        ("Location Service Setup", 87, 5),
        ("Delivery Partner App Link", 92, 3),
    ]),
    ("Week 7 - Notifications & Monitoring", "#dae8fc", "#6c8ebf", [
        ("SNS Setup", 95, 4),
        ("Pinpoint Config", 99, 3),
        ("CloudWatch Dashboards", 102, 5),
        ("X-Ray Integration", 107, 3),
    ]),
    ("Week 8 - Scalability & Resilience", "#d5e8d4", "#82b366", [
        ("Load Balancer Setup", 110, 5),
        ("Auto Scaling Config", 115, 5),
        ("CloudFront Optimization", 120, 3),
        ("Performance Testing", 123, 4),
    ]),
    ("Week 9 - CI/CD & Validation", "#ffe6cc", "#d79b00", [
        ("CodePipeline Integration", 127, 5),
        ("Automated Deployments", 132, 4),
        ("Security Audits", 136, 3),
        ("End-to-End Testing", 139, 5),
    ]),
]


def build_roadmap():
    label_w = 260
    chart_x0 = 20 + label_w
    day_px = 8
    row_h = 24
    top = 90
    total_days = 144

    b = ""
    chart_w = total_days * day_px
    total_w = chart_x0 + chart_w + 40

    # count rows: each section header + its tasks
    n_rows = sum(1 + len(tasks) for _, _, _, tasks in SECTIONS)
    bottom = top + n_rows * row_h
    total_h = bottom + 60

    b += vertex("title", "Milkful - AWS Deployment Roadmap", 20, 8, total_w - 40, 30, STYLES["title"])

    # week axis header + gridlines
    axis_style = "text;html=1;strokeColor=none;fillColor=#eef2f7;align=center;verticalAlign=middle;fontSize=10;fontStyle=1;"
    week = 0
    d = 0
    while d <= total_days:
        x = chart_x0 + d * day_px
        # gridline
        grid = (
            f'        <mxCell id="grid{d}" value="" '
            f'style="endArrow=none;html=1;strokeColor=#d9dee4;dashed=1;" edge="1" parent="1">\n'
            f'          <mxGeometry relative="1" as="geometry">\n'
            f'            <mxPoint x="{x}" y="{top}" as="sourcePoint" />\n'
            f'            <mxPoint x="{x}" y="{bottom}" as="targetPoint" />\n'
            f"          </mxGeometry>\n"
            f"        </mxCell>\n"
        )
        b += grid
        if d < total_days:
            week += 1
            b += vertex(f"wk{week}", f"W{week}", x, top - 26, day_px * 7, 22, axis_style)
        d += 7

    # rows
    y = top
    ri = 0
    for sec_name, fill, stroke, tasks in SECTIONS:
        # section header row (spans label + chart)
        sec_style = (
            "rounded=0;whiteSpace=wrap;html=1;fillColor=#eef2f7;strokeColor=#c3cbd4;"
            "align=left;verticalAlign=middle;fontStyle=1;fontSize=12;spacingLeft=8;"
        )
        b += vertex(f"sec{ri}", sec_name, 20, y, label_w + chart_w, row_h, sec_style)
        y += row_h
        ri += 1
        for tname, start, dur in tasks:
            # label
            lab_style = (
                "text;html=1;strokeColor=none;fillColor=none;align=left;"
                "verticalAlign=middle;fontSize=11;spacingLeft=14;"
            )
            b += vertex(f"lab{ri}", tname, 20, y, label_w, row_h, lab_style)
            # bar
            bx = chart_x0 + start * day_px
            bw = dur * day_px
            bar_style = (
                f"rounded=1;whiteSpace=wrap;html=1;fillColor={fill};strokeColor={stroke};"
                f"fontSize=9;align=center;verticalAlign=middle;"
            )
            b += vertex(f"bar{ri}", f"{dur}d", bx, y + 3, bw, row_h - 6, bar_style)
            y += row_h
            ri += 1

    return page("Roadmap", "roadmap-page", int(total_w), int(total_h), b)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    deploy = wrap([build_deployment()])
    roadmap = wrap([build_roadmap()])

    dpath = os.path.join(OUT_DIR, "milkful-deployment.drawio")
    rpath = os.path.join(OUT_DIR, "milkful-roadmap.drawio")
    with open(dpath, "w", encoding="utf-8") as f:
        f.write(deploy)
    with open(rpath, "w", encoding="utf-8") as f:
        f.write(roadmap)
    print("Wrote", dpath)
    print("Wrote", rpath)


if __name__ == "__main__":
    main()
