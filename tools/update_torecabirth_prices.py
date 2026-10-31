#!/usr/bin/env python3
"""Refresh the static TorecaBirth online-price cache from public listing pages.

The crawler intentionally fails closed unless the repository variable
TORECABIRTH_SCRAPE_ALLOWED is set to true after checking the site's terms and
robots policy. It checks robots.txt again at runtime, runs weekly via GitHub
Actions, and pauses between list-page requests. Product detail pages are not
fetched; the public category pages already show list price and stock status.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qs, urljoin, urlparse, urlunparse
from urllib.robotparser import RobotFileParser

import requests
from bs4 import BeautifulSoup

BASE_URL = "https://www.torecabirth.jp"
USER_AGENT = "ConanTCGPriceCache/1.0 (+https://github.com/090390/my-conan-deck)"
REQUEST_DELAY_SECONDS = 2.5
REQUEST_TIMEOUT_SECONDS = 25
OUT_PATH = Path(__file__).resolve().parents[1] / "public" / "torecabirth-prices.json"

# Public card-list categories currently used by TorecaBirth. Update this list
# when new Conan TCG booster/starter/collection categories are added.
CATEGORY_IDS = [
    # Booster packs 1–11
    2, 7, 25, 68, 75, 83, 84, 111, 122, 134, 145,
    # Starter / theme decks CT-D01–CT-D11
    9, 10, 11, 12, 13, 26, 42, 73, 74, 103, 123,
    # Conan promos / magazine supplements / executive collections
    48, 49, 141, 142,
]
CATEGORY_URLS = [f"{BASE_URL}/product-list/{category_id}" for category_id in CATEGORY_IDS]

PRICE_RE = re.compile(r"([0-9][0-9,]*)\s*円\s*(?:\(\s*税込\s*\)|（\s*税込\s*）)")
STOCK_RE = re.compile(r"在庫数\s*([0-9][0-9,]*)\s*点")
CARD_NUMBER_RE = re.compile(r"型番\s*[:：]?\s*([A-Za-z]{1,5}(?:-[A-Za-z]{1,5})?-?\d{1,4}|\d{3,4})", re.I)
RARITY_RE = re.compile(r"[〖【［\[]\s*(MRCP|SRCP|MRP|SRP|CP2|RP2|SP2|SEC|MR|SR|CP|RP|SP|PR|R|C|D|P)\s*[〗】］\]]", re.I)
PRODUCT_PATH_RE = re.compile(r"^/product/\d+/?$")


def permitted_by_robots(session: requests.Session, target_url: str) -> bool:
    parser = getattr(session, "_torecabirth_robots_parser", None)
    if parser is None:
        robots_url = urljoin(BASE_URL, "/robots.txt")
        try:
            response = session.get(robots_url, timeout=REQUEST_TIMEOUT_SECONDS)
        except requests.RequestException as exc:
            raise RuntimeError(f"robots.txt를 확인할 수 없어 수집을 중단합니다: {exc}") from exc

        if response.status_code == 404:
            # A missing robots.txt means there are no published robots directives,
            # but automated collection still requires the explicit repository gate.
            parser = RobotFileParser()
            parser.parse([])
        elif response.ok:
            parser = RobotFileParser()
            parser.set_url(robots_url)
            parser.parse(response.text.splitlines())
        else:
            raise RuntimeError(f"robots.txt 확인 실패 (HTTP {response.status_code}). 수집을 중단합니다.")
        session._torecabirth_robots_parser = parser

    if not parser.can_fetch(USER_AGENT, target_url):
        raise RuntimeError(f"robots.txt가 수집을 허용하지 않습니다: {target_url}")
    return True


def fetch_page(session: requests.Session, url: str, previous_request_at: list[float]) -> str:
    permitted_by_robots(session, url)
    elapsed = time.monotonic() - previous_request_at[0]
    if previous_request_at[0] and elapsed < REQUEST_DELAY_SECONDS:
        time.sleep(REQUEST_DELAY_SECONDS - elapsed)
    response = session.get(url, timeout=REQUEST_TIMEOUT_SECONDS)
    previous_request_at[0] = time.monotonic()
    if not response.ok:
        raise RuntimeError(f"페이지 요청 실패: HTTP {response.status_code} · {url}")
    response.encoding = response.apparent_encoding or response.encoding
    return response.text


def clean_listing_title(value: str) -> str:
    text = re.sub(r"\s+", " ", value or "").strip()
    text = PRICE_RE.sub("", text)
    text = re.sub(r"在庫数\s*[0-9,]+\s*点|在庫なし|カートに入れる|数量\s*[:：]?", "", text)
    return re.sub(r"\s+", " ", text).strip(" ·　\t\n")


def get_product_context(anchor) -> str:
    anchor_text = anchor.get_text(" ", strip=True)
    if PRICE_RE.search(anchor_text):
        return anchor_text
    # Climb only as far as a single product card, so price/stock from adjacent
    # cards can't accidentally be associated with this product.
    for parent in list(anchor.parents)[:8]:
        if getattr(parent, "name", None) in ("body", "html"):
            break
        product_links = set()
        for link in parent.find_all("a", href=True):
            parsed = urlparse(urljoin(BASE_URL, link.get("href", "")))
            if PRODUCT_PATH_RE.match(parsed.path):
                product_links.add(urlunparse((parsed.scheme, parsed.netloc, parsed.path.rstrip("/"), "", "", "")))
        text = parent.get_text(" ", strip=True)
        if PRICE_RE.search(text) and len(product_links) == 1:
            return text
    return anchor_text


def parse_listing_item(url: str, title: str, context: str, category_url: str):
    clean_title = clean_listing_title(title) or clean_listing_title(context)
    number_match = CARD_NUMBER_RE.search(clean_title) or CARD_NUMBER_RE.search(context)
    price_match = PRICE_RE.search(context) or PRICE_RE.search(title)
    if not number_match or not price_match:
        return None

    card_number = number_match.group(1).replace(" ", "").upper()
    rarity_match = RARITY_RE.search(clean_title) or RARITY_RE.search(context)
    rarity = rarity_match.group(1).upper() if rarity_match else ""

    stock_match = STOCK_RE.search(context) or STOCK_RE.search(title)
    if re.search(r"在庫なし", context) or re.search(r"在庫なし", title):
        in_stock = False
        stock_count = 0
    elif stock_match:
        stock_count = int(stock_match.group(1).replace(",", ""))
        in_stock = stock_count > 0
    else:
        stock_count = None
        in_stock = None

    return {
        "cardNumber": card_number,
        "rarity": rarity,
        "title": clean_title,
        "priceYen": int(price_match.group(1).replace(",", "")),
        "inStock": in_stock,
        "stockCount": stock_count,
        "url": url,
        "sourceCategory": category_url,
    }


def canonical_product_url(href: str) -> str | None:
    absolute = urljoin(BASE_URL, href)
    parsed = urlparse(absolute)
    if parsed.netloc.lower() != urlparse(BASE_URL).netloc.lower():
        return None
    if not PRODUCT_PATH_RE.match(parsed.path):
        return None
    return urlunparse(("https", parsed.netloc, parsed.path.rstrip("/"), "", "", ""))


def collect_category(session: requests.Session, category_url: str, previous_request_at: list[float]) -> list[dict]:
    queue = [category_url]
    visited_pages: set[str] = set()
    found_items: dict[str, dict] = {}

    while queue:
        page_url = queue.pop(0)
        normalized_page = urlunparse((urlparse(page_url).scheme, urlparse(page_url).netloc, urlparse(page_url).path, "", urlparse(page_url).query, ""))
        if normalized_page in visited_pages:
            continue
        visited_pages.add(normalized_page)

        html = fetch_page(session, normalized_page, previous_request_at)
        soup = BeautifulSoup(html, "html.parser")

        # Gather every paginated listing URL within this category.
        current_path = urlparse(category_url).path
        for link in soup.find_all("a", href=True):
            candidate = urljoin(BASE_URL, link["href"])
            parsed = urlparse(candidate)
            if parsed.netloc.lower() != urlparse(BASE_URL).netloc.lower() or parsed.path != current_path:
                continue
            query = parse_qs(parsed.query)
            page_values = query.get("page", [])
            if page_values and page_values[0].isdigit():
                queue.append(urlunparse(("https", parsed.netloc, parsed.path, "", f"page={int(page_values[0])}", "")))

        # Several anchors can lead to the same product (thumbnail/title/cart); use
        # the text-bearing anchor and deduplicate again by canonical product URL.
        anchors_by_url: dict[str, list] = {}
        for anchor in soup.find_all("a", href=True):
            product_url = canonical_product_url(anchor["href"])
            if not product_url:
                continue
            anchors_by_url.setdefault(product_url, []).append(anchor)

        for product_url, anchors in anchors_by_url.items():
            anchor = max(anchors, key=lambda el: len(el.get_text(" ", strip=True)))
            raw_title = anchor.get_text(" ", strip=True)
            context = get_product_context(anchor)
            # When the text-bearing anchor only contains the name, preserve the
            # card label but use its single-card ancestor to read price and stock.
            item = parse_listing_item(product_url, raw_title, context, category_url)
            if not item:
                # Sometimes the price is on a sibling element and the chosen
                # anchor is image-only; try every associated anchor once.
                for fallback_anchor in anchors:
                    fallback_context = get_product_context(fallback_anchor)
                    fallback_title = fallback_anchor.get_text(" ", strip=True)
                    item = parse_listing_item(product_url, fallback_title, fallback_context, category_url)
                    if item:
                        break
            if item:
                # The same listing can appear in more than one category. The
                # product URL uniquely identifies one physical listing/variant.
                found_items[product_url] = item

    return list(found_items.values())


def main() -> int:
    parser = argparse.ArgumentParser(description="Refresh TorecaBirth card price cache")
    parser.add_argument("--dry-run", action="store_true", help="parse pages but do not write the output file")
    args = parser.parse_args()

    gate = os.getenv("TORECABIRTH_SCRAPE_ALLOWED", "").strip().lower()
    if gate not in {"1", "true", "yes"}:
        print("수집 중단: TORECABIRTH_SCRAPE_ALLOWED=true 설정이 필요합니다. 사이트 이용 조건/robots 정책을 확인한 뒤 사용하세요.", file=sys.stderr)
        return 2

    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT, "Accept-Language": "ja,en;q=0.8"})
    previous_request_at = [0.0]
    all_items: dict[str, dict] = {}

    try:
        for index, category_url in enumerate(CATEGORY_URLS, start=1):
            print(f"[{index}/{len(CATEGORY_URLS)}] {category_url}")
            category_items = collect_category(session, category_url, previous_request_at)
            for item in category_items:
                all_items[item["url"]] = item
            print(f"  → 읽은 상품 {len(category_items)}개")
    except (requests.RequestException, RuntimeError) as exc:
        print(f"가격 캐시 갱신 실패: {exc}", file=sys.stderr)
        return 1

    if not all_items:
        print("상품 목록에서 카드 가격을 하나도 읽지 못했습니다. 기존 캐시는 덮어쓰지 않습니다.", file=sys.stderr)
        return 1

    output = {
        "schemaVersion": 1,
        "source": "TorecaBirth",
        "updatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "items": sorted(all_items.values(), key=lambda item: (item["cardNumber"], item["rarity"], item["priceYen"])),
        "meta": {
            "sourceType": "online listing price",
            "categoryCount": len(CATEGORY_URLS),
            "itemCount": len(all_items),
            "note": "Price and stock are collected from public product-list pages; they can change and may differ from final order availability.",
        },
    }

    if args.dry_run:
        print(f"DRY RUN: {len(all_items)}개 상품을 파싱했습니다. JSON 파일은 변경하지 않았습니다.")
        print(json.dumps({"updatedAt": output["updatedAt"], "itemCount": len(all_items), "sample": output["items"][:3]}, ensure_ascii=False, indent=2))
        return 0

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    temporary = OUT_PATH.with_suffix(OUT_PATH.suffix + ".tmp")
    temporary.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(OUT_PATH)
    print(f"완료: {len(all_items)}개 상품을 {OUT_PATH}에 저장했습니다.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
