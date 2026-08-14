"""Approximate renderer for a .drawio file -> PNG, for visual QA.

Parses vertex geometries and edges (with exit/entry anchors) and draws them
with matplotlib so we can verify arrows actually touch nodes and don't overlap.
Not a full mxGraph renderer - AWS icon art is shown as coloured boxes.
"""
import re
import sys
import xml.etree.ElementTree as ET
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, Rectangle

SRC = sys.argv[1] if len(sys.argv) > 1 else r"d:\milkful\milkful-app\docs\design\milkful-architecture.drawio"
OUT = sys.argv[2] if len(sys.argv) > 2 else r"d:\milkful\milkful-app\docs\design\_preview.png"


def gattr(style, key, default=None):
    m = re.search(rf"{key}=([^;]+)", style or "")
    return m.group(1) if m else default


def main():
    t = ET.parse(SRC)
    root = t.getroot()
    V = {}
    E = []
    for c in root.iter("mxCell"):
        cid = c.get("id")
        st = c.get("style", "") or ""
        g = c.find("mxGeometry")
        if c.get("vertex") == "1" and g is not None:
            V[cid] = dict(
                x=float(g.get("x", 0)), y=float(g.get("y", 0)),
                w=float(g.get("width", 0)), h=float(g.get("height", 0)),
                label=(c.get("value", "") or "").split("\n")[0],
                fill=gattr(st, "fillColor", "#ffffff"),
                stroke=gattr(st, "strokeColor", "#333333"),
                style=st,
            )
        elif c.get("edge") == "1":
            E.append(dict(src=c.get("source"), tgt=c.get("target"),
                          label=(c.get("value", "") or ""), style=st))

    maxx = max(v["x"] + v["w"] for v in V.values()) + 40
    maxy = max(v["y"] + v["h"] for v in V.values()) + 40

    # optional crop: x0 y0 x1 y1 as argv[3..6]
    if len(sys.argv) >= 7:
        cx0, cy0, cx1, cy1 = (float(a) for a in sys.argv[3:7])
    else:
        cx0, cy0, cx1, cy1 = 0, 0, maxx, maxy

    fig, ax = plt.subplots(figsize=((cx1 - cx0) / 80.0, (cy1 - cy0) / 80.0), dpi=130)
    ax.set_xlim(cx0, cx1)
    ax.set_ylim(cy0, cy1)
    ax.invert_yaxis()
    ax.axis("off")

    big = {"vpc", "ebbus"}
    # draw vertices
    for cid, v in V.items():
        z = 1 if cid in big else 3
        alpha = 0.25 if cid in big else 1.0
        ax.add_patch(Rectangle((v["x"], v["y"]), v["w"], v["h"],
                               facecolor=v["fill"], edgecolor=v["stroke"],
                               linewidth=1.0, alpha=alpha, zorder=z))
        if v["label"] and cid not in big:
            ax.text(v["x"] + v["w"] / 2, v["y"] + v["h"] + 9, v["label"],
                    ha="center", va="top", fontsize=5.2, zorder=5)
        if cid in big:
            ax.text(v["x"] + 8, v["y"] + 14, v["label"][:60], ha="left",
                    va="top", fontsize=7, color=v["stroke"], zorder=2)

    def anchor(v, ax_, ay_):
        return (v["x"] + ax_ * v["w"], v["y"] + ay_ * v["h"])

    def endpoint(v, xa, ya, other):
        if xa is not None and ya is not None:
            return anchor(v, xa, ya)
        # nearest side to 'other'
        cx, cy = v["x"] + v["w"] / 2, v["y"] + v["h"] / 2
        ox, oy = other
        if abs(ox - cx) > abs(oy - cy):
            return (v["x"] + (v["w"] if ox > cx else 0), cy)
        return (cx, v["y"] + (v["h"] if oy > cy else 0))

    for e in E:
        s, tg = V.get(e["src"]), V.get(e["tgt"])
        if not s or not tg:
            continue
        st = e["style"]
        col = gattr(st, "strokeColor", "#607d8b")
        exX = gattr(st, "exitX"); exY = gattr(st, "exitY")
        enX = gattr(st, "entryX"); enY = gattr(st, "entryY")
        exX = float(exX) if exX else None; exY = float(exY) if exY else None
        enX = float(enX) if enX else None; enY = float(enY) if enY else None
        tcx, tcy = tg["x"] + tg["w"] / 2, tg["y"] + tg["h"] / 2
        scx, scy = s["x"] + s["w"] / 2, s["y"] + s["h"] / 2
        p0 = endpoint(s, exX, exY, (tcx, tcy))
        p1 = endpoint(tg, enX, enY, (scx, scy))
        # orthogonal L route
        pts = [p0]
        if abs(p0[1] - p1[1]) < 2 or abs(p0[0] - p1[0]) < 2:
            pass
        else:
            horiz_exit = exX in (0.0, 1.0) or (exX is None and abs(p0[0] - scx) > 1)
            if horiz_exit:
                pts.append((p1[0], p0[1]))
            else:
                pts.append((p0[0], p1[1]))
        pts.append(p1)
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        ax.plot(xs, ys, color=col, linewidth=1.3,
                linestyle="--" if "dashed=1" in st else "-", zorder=4)
        ax.add_patch(FancyArrowPatch(pts[-2], pts[-1], arrowstyle="-|>",
                                     mutation_scale=9, color=col, zorder=6))
        if e["label"]:
            mx, my = (pts[0][0] + pts[-1][0]) / 2, (pts[0][1] + pts[-1][1]) / 2
            ax.text(mx, my - 4, e["label"][:32], fontsize=4.6, color=col,
                    ha="center", va="bottom", zorder=7,
                    bbox=dict(boxstyle="round,pad=0.1", fc="white", ec="none", alpha=0.7))

    plt.subplots_adjust(left=0, right=1, top=1, bottom=0)
    plt.savefig(OUT, dpi=130)
    print("Wrote", OUT, "crop", int(cx0), int(cy0), int(cx1), int(cy1))


if __name__ == "__main__":
    main()
