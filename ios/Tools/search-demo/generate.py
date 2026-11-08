#!/usr/bin/env python3
"""Generate an offline, reproducible search library and its question set."""

import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent

SITES = [
    ("github.com", "GitHub"),
    ("youtube.com", "YouTube"),
    ("xiaohongshu.com", "小红书"),
    ("bilibili.com", "Bilibili"),
    ("sspai.com", "少数派"),
    ("medium.com", "Medium"),
    ("en.wikipedia.org", "维基百科"),
    ("reddit.com", "Reddit"),
]

TOPICS = [
    {
        "slug": "programming", "tag": "Programming", "name": "编程", "author": "陈一帆",
        "handle": "yifan_codes", "label": "computer", "symbol": "laptopcomputer",
        "keywords": ["编程", "software"], "ocr": "WWDC 2026 session notes",
        "titles": ["SwiftUI 瀑布流性能优化", "Actor isolation in Swift 6", "Foundation Models 入门", "Composable architecture patterns"],
    },
    {
        "slug": "food", "tag": "Food", "name": "美食", "author": "李可心",
        "handle": "kexin_eats", "label": "food", "symbol": "fork.knife",
        "keywords": ["美食", "noodles"], "ocr": "配方 15 分钟",
        "titles": ["上海生煎和咖啡店", "Easy ramen recipe", "周末烘焙：抹茶曲奇", "Street food guide to Taipei"],
    },
    {
        "slug": "fashion", "tag": "Fashion", "name": "穿搭", "author": "林小夏",
        "handle": "xiaxia_style", "label": "person", "symbol": "person.crop.square",
        "keywords": ["穿搭", "outfit", "portrait"], "ocr": "秋装搭配清单",
        "titles": ["秋季通勤穿搭", "Minimalist outfit ideas", "红色外套搭配", "Portrait street style"],
    },
    {
        "slug": "travel", "tag": "Travel", "name": "旅行", "author": "王远航",
        "handle": "yuanhang_go", "label": "travel", "symbol": "airplane",
        "keywords": ["旅行", "trip"], "ocr": "路线图 第一天",
        "titles": ["京都两日路线", "Weekend in Singapore", "上海博物馆攻略", "Train travel photography"],
    },
    {
        "slug": "music", "tag": "Music", "name": "音乐", "author": "周乐乐",
        "handle": "lele_music", "label": "musical instrument", "symbol": "music.note",
        "keywords": ["音乐", "music"], "ocr": "曲目表 live set",
        "titles": ["爵士钢琴入门", "Live concert recap", "吉他和弦练习", "Ambient album review"],
    },
    {
        "slug": "design", "tag": "Design", "name": "设计", "author": "赵墨白",
        "handle": "mobai_design", "label": "design", "symbol": "paintpalette",
        "keywords": ["设计", "graphic"], "ocr": "GRID SYSTEM poster",
        "titles": ["蓝色玻璃质感设计", "Typography and spacing", "海报色彩灵感", "Design system components"],
    },
]


def make_items():
    items = []
    for domain, site_name in SITES:
        for topic in TOPICS:
            for variant, age_hours in enumerate((2, 12, 48, 240)):
                items.append({
                    "key": f"search-demo:{domain}:{topic['slug']}:{variant}",
                    "url": f"https://{domain}/attention-search-demo/{topic['slug']}/{variant}",
                    "site": site_name,
                    "title": f"{site_name}｜{topic['titles'][variant]}",
                    "authorName": topic["author"],
                    "authorHandle": topic["handle"],
                    "ocrText": topic["ocr"] if variant == 0 else None,
                    "visualLabels": [topic["label"]],
                    "keywords": topic["keywords"],
                    "tags": [topic["tag"]],
                    "ageHours": age_hours,
                    "isArchived": topic["slug"] == "music" and variant == 2,
                    "isPrivate": topic["slug"] == "fashion" and variant == 3,
                    "symbol": None,
                })
    for topic in TOPICS:
        for variant, age_hours in enumerate((4, 96)):
            items.append({
                "key": f"image:search-demo:{topic['slug']}:{variant}",
                "url": None,
                "site": "Images",
                "title": f"{topic['name']}示意图 {variant + 1}",
                "authorName": None,
                "authorHandle": None,
                "ocrText": None,
                "visualLabels": [topic["label"]],
                "keywords": topic["keywords"],
                "tags": [topic["tag"]],
                "ageHours": age_hours,
                "isArchived": False,
                "isPrivate": False,
                "symbol": topic["symbol"],
            })
    return items


def count(items, *, scope="all", site=None, tag=None, since_hours=None, keyword=None, visual=None):
    def matches(item):
        if scope == "all" and (item["isArchived"] or item["isPrivate"]):
            return False
        if scope == "archived" and (not item["isArchived"] or item["isPrivate"]):
            return False
        if scope == "private" and not item["isPrivate"]:
            return False
        if site and ("Images" if item["url"] is None else item["url"].split("/")[2]) != site:
            return False
        if tag and tag not in item["tags"]:
            return False
        if since_hours and item["ageHours"] >= since_hours:
            return False
        if keyword:
            fields = [item["title"], item["url"] or "", item["ocrText"] or "", item["site"],
                      item["authorName"] or "", item["authorHandle"] or ""] + item["tags"] + item["keywords"]
            if not all(any(word.casefold() in field.casefold() for field in fields) for word in keyword.split()):
                return False
        if visual and visual not in item["visualLabels"] and not any(visual in k for k in item["keywords"]):
            return False
        return True
    return sum(matches(item) for item in items)


def make_questions(items):
    questions = []

    def add(category, question, *, scope="all", site=None, tag=None, since_hours=None,
            keyword=None, visual=None, note=""):
        questions.append({
            "id": f"Q{len(questions) + 1:03}", "category": category, "question": question,
            "scope": scope, "expected_count": count(items, scope=scope, site=site, tag=tag,
                                                     since_hours=since_hours, keyword=keyword, visual=visual),
            "site": site, "tag": tag, "since_hours": since_hours,
            "keyword": keyword, "visual_concept": visual, "note": note,
        })

    add("scope", "我的收藏一共有多少条？")
    add("scope", "归档里有多少条？", scope="archived", note="先在侧边栏选 Archived")
    add("scope", "私密收藏有多少条？", scope="private", note="先解锁并在侧边栏选 Private")
    add("scope", "我保存了多少张图片？", site="Images")
    for domain, name in SITES:
        add("site", f"我收藏了多少个来自{name}的链接？", site=domain)
        add("recent-site", f"过去24小时我收藏了多少个{name}链接？", site=domain, since_hours=24)
    for topic in TOPICS:
        add("tag", f"#{topic['tag']} 有多少条收藏？", tag=topic["tag"])
        add("recent-tag", f"过去24小时 #{topic['tag']} 有多少条？", tag=topic["tag"], since_hours=24)
        add("author", f"作者{topic['author']}的收藏有多少条？", keyword=topic["author"])
        add("ocr", f"哪些收藏里有「{topic['ocr']}」？", keyword=topic["ocr"])
        add("visual", f"找出关于{topic['name']}的图片或链接。", visual=topic["label"],
            note="只标注无 CLIP 分数时的标签回退数量；CLIP 启用后结果可能增加")
    for domain, name in SITES:
        for topic in TOPICS:
            add("site-tag", f"{name} 的 #{topic['tag']} 收藏有多少条？", site=domain, tag=topic["tag"])
        add("recent-site-tag", f"过去24小时 {name} 的 #Programming 有多少条？",
            site=domain, tag="Programming", since_hours=24)
    add("keyword", "标题里提到 SwiftUI 的收藏有多少条？", keyword="SwiftUI")
    add("keyword", "搜索 catwalks 会找到几条？", keyword="catwalks", note="预期为零，测试无关词")
    add("keyword", "找一下「量子菠萝」的收藏。", keyword="量子菠萝")
    add("keyword", "找包含「配方 15 分钟」的内容。", keyword="配方 15 分钟")
    add("time", "过去24小时一共收藏了多少条？", since_hours=24)
    add("time", "过去72小时一共收藏了多少条？", since_hours=72)
    return questions


def main():
    items = make_items()
    questions = make_questions(items)

    def write_json_rows(path, rows):
        lines = ["["] + [
            "  " + json.dumps(row, ensure_ascii=False, separators=(",", ":")) + ("," if index < len(rows) - 1 else "")
            for index, row in enumerate(rows)
        ] + ["]"]
        path.write_text("\n".join(lines) + "\n")

    write_json_rows(ROOT / "App" / "SearchDemoCorpus.json", items)
    with (OUT / "catalog.csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=items[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(items)
    with (OUT / "questions.csv").open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=questions[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(questions)
    write_json_rows(OUT / "questions.json", questions)
    print(f"Generated {len(items)} items and {len(questions)} questions")


if __name__ == "__main__":
    main()
