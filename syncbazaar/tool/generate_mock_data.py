#!/usr/bin/env python3
"""Generates assets/dev/mock_data.json for SyncBazaar development/testing.

Run from anywhere:
    python3 tool/generate_mock_data.py

Re-run any time to regenerate with fresh random data, then hot-restart
(capital R) the running Flutter app to reload it (hot reload alone won't
re-trigger the startup seeder).
"""

import json
import random
from datetime import date, timedelta
from pathlib import Path

random.seed()  # nondeterministic on purpose: fresh data each run

TODAY = date.today()
OUTPUT_PATH = Path(__file__).resolve().parent.parent / "assets" / "dev" / "mock_data.json"

EMPLOYEE_EMAILS = [
    "employee@syncbazaar.com",  # Via
    "missy@syncbazaar.com",
    "tg@syncbazaar.com",
    "sen@syncbazaar.com",
]

CUSTOMER_NAMES = [
    "Juan Dela Cruz", "Maria Santos", "Jose Reyes", "Ana Bautista",
    "Mark Villanueva", "Grace Mendoza", "Paolo Garcia", "Angel Cruz",
    "Kim Aquino", "Ricky Torres", "Bea Fernandez", "Carlo Ramos",
    "Nica Flores", "Dennis Castro", "Joy Gonzales", "Miguel Rivera",
    "Trisha Navarro", "Aaron Domingo", "Faith Pascual", "Leo Salazar",
    "Cathy Morales", "Bryan Ocampo", "Kaye Delos Santos", "Vince Aguilar",
]

PAYMENT_METHODS = ["CASH", "GCASH"]

COMPANIES = [
    {"id": "c1", "name": "Amkor Technology", "address": "Bicutan, Taguig City",
     "contact": "0917-100-2000", "incentive_percent": 10, "buffer_percent": 10},
    {"id": "c2", "name": "SM City Lucena", "address": "Lucena City, Quezon",
     "contact": "0917-200-3000", "incentive_percent": 10, "buffer_percent": 5},
    {"id": "c3", "name": "MSEUF Campus", "address": "Lucena City, Quezon",
     "contact": "0917-300-4000", "incentive_percent": 8, "buffer_percent": 10},
]

# Each product: maker, model name, price range (PHP), 2-3 realistic colorways,
# and the basename of its bundled photo.
# The maker is only used to build the display name — products carry no separate
# brand or category field.
# Prices stay within 1500-2800 and always land on a round hundred; the
# per-model ranges below keep the relative brand tiering (Onitsuka cheapest,
# On Cloud priciest) inside that band.
PRODUCT_CATALOG = [
    ("Nike", "Air Max SC", (1900, 2300), ["Triple White", "Triple Black", "Light Orewood Brown"], "airmaxsc"),
    ("Nike", "Air Jordan 1 Low", (2200, 2600), ["Black/White", "University Blue", "Bred Toe"], "airjordan1low"),
    ("Nike", "ZoomX Vaporfly", (2000, 2400), ["Panda", "University Red", "Grey Fog"], "zoomxvaporfly"),
    ("Adidas", "Samba OG", (1800, 2200), ["Cloud White/Core Black/Gum", "Core Black/Cloud White"], "sambaog"),
    ("Adidas", "Gazelle", (1700, 2100), ["Hazy Green/Off White", "Core Black/Ftwr White"], "gazellebold"),
    ("Adidas", "Ultraboost 1.0", (2400, 2800), ["Core Black", "Cloud White", "Solar Red"], "ultraboost10"),
    ("On Cloud", "Cloud 5", (2500, 2800), ["All Black", "Frost/White", "Ivory/Frost"], "cloud5"),
    ("On Cloud", "Cloudrunner", (2600, 2800), ["Frost/Wash", "All Black"], "cloudrunner"),
    ("On Cloud", "Cloudswift", (2400, 2700), ["Midnight/Eclipse", "White/Pearl"], "cloudswift"),
    ("Onitsuka Tiger", "Mexico 66", (1500, 1900), ["Oatmeal/Habanero", "Dark Brown", "Cream/Peacoat"], "mexico66"),
    ("Onitsuka Tiger", "Serrano", (1500, 1800), ["White/Black", "Cream/Forest"], "serrano"),
    ("Onitsuka Tiger", "Ultimate 81", (1600, 2000), ["White/Navy", "Black/White"], "ultimate81"),
]

# Every model above maps to a bundled photo in assets/images/default_shoes/.
# Three models were chosen specifically because a photo exists for them:
# Air Max SC, ZoomX Vaporfly and Cloudrunner replaced Air Force 1 '07, Dunk Low
# and Cloudmonster, which had none. Keep this invariant — a catalog entry
# without a matching PNG renders as a grey placeholder in every screen.
IMAGE_DIR = "assets/images/default_shoes"

# Prices must always end in "00", so step the random draw by whole hundreds.
PRICE_STEP = 100

# Sales per bazaar per day. Sized against the ~PHP 2,000 average unit price
# so a day's revenue lands inside the 10k-35k band the dashboard chart's
# vertical axis is scaled for.
SALES_PER_DAY = (5, 16)

CORE_SIZES = ["38", "39", "40", "41", "42"]
EXTRA_SIZES = ["36", "37", "43"]

WEEKDAY_MONFRI = set(range(0, 5))  # Mon-Fri

# --- August Fair -------------------------------------------------------
# A named, fixed-date bazaar (unlike every other event here, which is
# positioned relative to TODAY). Mon 3 - Fri 7 August 2026.
AUGUST_FAIR_START = date(2026, 8, 3)
AUGUST_FAIR_END = date(2026, 8, 7)

# Revenue band every day of the fair has to land inside.
AUGUST_FAIR_REVENUE_CAP = 25_000

# Per-day revenue target, Mon..Fri — the money, not a sale count. A fixed
# count can't hold a band this tight: unit prices run PHP 1,500-2,800 and
# discounts take off up to 30%, so the same count swings several thousand
# pesos from one day to the next. Targets sit below the cap with enough
# spread that the chart still has a readable shape.
AUGUST_FAIR_DAY_TARGETS = [
    (0, 21_000),  # Mon: opening day
    (1, 23_500),  # Tue: building
    (2, 20_500),  # Wed: midweek dip
    (3, 24_500),  # Thu: recovering
    (4, 22_500),  # Fri: steady close
]

# The fair runs Mon-Fri, but it hasn't sold on days that haven't happened
# yet: sales stop at TODAY, so Friday's bar appears on its own once Friday
# arrives. Same rule every other ongoing bazaar in this file follows. Set
# False to prefill the whole run regardless of the date.
AUGUST_FAIR_SALES_THROUGH_TODAY_ONLY = True


def next_allowed_day(d, allowed_weekdays):
    while d.weekday() not in allowed_weekdays:
        d += timedelta(days=1)
    return d


def business_span(start, length, allowed_weekdays):
    """Returns (start, end) covering `length` days honoring allowed weekdays
    (consecutive calendar days, but start/end both land on allowed days)."""
    end = start + timedelta(days=length - 1)
    while end.weekday() not in allowed_weekdays:
        end += timedelta(days=1)
    return start, end


def make_event(id_, name, floor_date, min_days, max_days, allowed_weekdays, offset_days_range):
    offset = random.randint(*offset_days_range)
    start = next_allowed_day(floor_date + timedelta(days=offset), allowed_weekdays)
    length = random.randint(min_days, max_days)
    start, end = business_span(start, length, allowed_weekdays)
    return {
        "id": id_,
        "name": name,
        "company_id": random.choice(COMPANIES)["id"],
        "start_date": start.isoformat(),
        "end_date": end.isoformat(),
        "payment_methods": ["CASH", "GCASH"],
        "assigned_employee_emails": [],
        "allocations": [],
    }


def build_products():
    products = []
    stock_by_sku = {}  # (product_id, color, size) -> remaining qty
    for i, (brand, model, price_range, colors, image) in enumerate(PRODUCT_CATALOG, start=1):
        pid = f"p{i}"
        sizes = list(CORE_SIZES)
        for extra in EXTRA_SIZES:
            if random.random() < 0.5:
                sizes.append(extra)
        sizes.sort(key=int)

        low, high = price_range
        base_price = float(random.randrange(low, high + 1, PRICE_STEP))
        stock_entries = []
        for color in colors:
            for size in sizes:
                qty = random.randint(12, 20)
                stock_entries.append({"color": color, "size": size, "qty": qty})
                stock_by_sku[(pid, color, size)] = qty

        products.append({
            "id": pid,
            "name": f"{brand} {model}",
            "image": f"{IMAGE_DIR}/{image}.png",
            "base_price": base_price,
            "colors": colors,
            "sizes": sizes,
            "stock": stock_entries,
        })
    return products, stock_by_sku


def pick_skus_for_event(product, count, remaining, min_qty, max_qty):
    """Picks up to `count` (color, size) combos for this product that still
    have enough remaining stock, and reserves `min_qty..max_qty` from each."""
    combos = [(c, s) for c in product["colors"] for s in product["sizes"]]
    random.shuffle(combos)
    picked = []
    for color, size in combos:
        if len(picked) >= count:
            break
        key = (product["id"], color, size)
        available = remaining.get(key, 0)
        if available < min_qty:
            continue
        qty = min(random.randint(min_qty, max_qty), available)
        remaining[key] -= qty
        picked.append({"product_id": product["id"], "color": color, "size": size, "qty": qty})
    return picked


def allocate_event(event, products, remaining, products_per_event=(5, 8), qty_range=(3, 6)):
    chosen_products = random.sample(products, k=min(random.randint(*products_per_event), len(products)))
    allocations = []
    for product in chosen_products:
        allocations.extend(
            pick_skus_for_event(product, random.randint(1, 3), remaining, *qty_range)
        )
    event["allocations"] = allocations


def generate_daily_sales(event, remaining, start_date, anchor_date,
                         day_pattern, max_qty=1):
    """Generates sales day by day from an explicit per-day target count.

    `day_pattern` is a list of (offset_from_anchor, sale_count) tuples. Going
    day-by-day rather than scattering a lump total at random offsets is what
    keeps each day's revenue inside a predictable band — the chart-visible
    bazaar passes a hand-tuned pattern for a clear good/bad zigzag, every
    other bazaar passes randomised counts from the same band.
    """
    sales = []
    allocations = [a for a in event["allocations"] if a["qty"] > 0]
    if not allocations:
        return sales

    for offset_from_anchor, count in day_pattern:
        day = anchor_date + timedelta(days=offset_from_anchor)
        if day < start_date:
            # Would land before the bazaar opened; skip rather than clamp,
            # which would silently pile these sales onto the start date.
            continue
        day_after_start = (day - start_date).days
        produced = 0
        attempts = 0
        max_attempts = count * 10
        while produced < count and attempts < max_attempts:
            attempts += 1
            sellable_allocs = [
                a for a in allocations
                if remaining.get((a["product_id"], a["color"], a["size"]), 0) > 0
            ]
            if not sellable_allocs:
                break

            alloc = random.choice(sellable_allocs)
            key = (alloc["product_id"], alloc["color"], alloc["size"])
            qty = min(random.randint(1, max_qty), remaining[key])
            remaining[key] -= qty

            discount = random.choices([0, 10, 20, 30], weights=[70, 15, 10, 5])[0]
            sales.append({
                "event_id": event["id"],
                "product_id": alloc["product_id"],
                "color": alloc["color"],
                "size": alloc["size"],
                "customer_name": random.choice(CUSTOMER_NAMES),
                "payment_method": random.choices(PAYMENT_METHODS, weights=[70, 30])[0],
                "qty": qty,
                "discount_percent": discount,
                "days_after_start": day_after_start,
            })
            produced += 1
    return sales


def generate_daily_sales_to_revenue(event, remaining, start_date, day_targets,
                                    price_by_product, cap):
    """Fills each day up to a revenue target instead of a sale count.

    Same shape of output as `generate_daily_sales`, but it counts pesos. A
    candidate sale that would push the day past `cap` is rejected and another
    SKU is tried, so the cap is a hard ceiling rather than an average — which
    is what keeps every bar inside the band on the dashboard chart.
    """
    sales = []
    allocations = [a for a in event["allocations"] if a["qty"] > 0]
    if not allocations:
        return sales

    for offset, target in day_targets:
        day_total = 0.0
        while day_total < target:
            headroom = cap - day_total
            candidates = [
                a for a in allocations
                if remaining.get((a["product_id"], a["color"], a["size"]), 0) > 0
            ]
            random.shuffle(candidates)

            placed = False
            for alloc in candidates:
                discount = random.choices([0, 10, 20, 30], weights=[70, 15, 10, 5])[0]
                value = price_by_product[alloc["product_id"]] * (1 - discount / 100)
                if value > headroom:
                    continue
                remaining[(alloc["product_id"], alloc["color"], alloc["size"])] -= 1
                day_total += value
                sales.append({
                    "event_id": event["id"],
                    "product_id": alloc["product_id"],
                    "color": alloc["color"],
                    "size": alloc["size"],
                    "customer_name": random.choice(CUSTOMER_NAMES),
                    "payment_method": random.choices(PAYMENT_METHODS, weights=[70, 30])[0],
                    "qty": 1,
                    "discount_percent": discount,
                    "days_after_start": offset,
                })
                placed = True
                break

            # Nothing left that fits the remaining headroom (or no stock at
            # all) — stop this day rather than spin. The target sits far
            # enough below the cap that this can only trigger near the top.
            if not placed:
                break
    return sales


def random_day_pattern(days_span):
    """A per-day sale count for every day of an event's run, drawn from the
    band that keeps a day's revenue inside 10k-35k at the ~PHP 2,000 average
    unit price."""
    return [
        (offset, random.randint(*SALES_PER_DAY))
        for offset in range(max(1, days_span))
    ]


def main():
    products, remaining = build_products()

    events = []

    # --- August Fair: fixed calendar dates, Mon 3 - Fri 7 August 2026. ---
    august_fair = {
        "id": "e_august_fair",
        "name": "August Fair",
        "company_id": "c2",  # SM City Lucena
        "start_date": AUGUST_FAIR_START.isoformat(),
        "end_date": AUGUST_FAIR_END.isoformat(),
        # Held still while the rest shift: this is the fixed reference the
        # revenue-shape test measures against, and a moving target cannot be
        # asserted on.
        "fixed_dates": True,
        "payment_methods": ["CASH", "GCASH"],
        "assigned_employee_emails": [
            "employee@syncbazaar.com",
            "missy@syncbazaar.com",
        ],
        "allocations": [],
    }
    events.append(august_fair)

    # --- Ongoing (>= today, at least 2). One deliberately has a fixed start
    # date (no weekday restriction, may span into Sunday) with hand-tuned
    # sales on the last 5 calendar days so the "Average Daily Sales" chart
    # always has a visible good/bad mix to compare, regardless of when this
    # script is rerun; the rest are strict Mon-Fri and may show as
    # "Upcoming" until their weekday start arrives. ---
    ongoing1_start = date(TODAY.year, 7, 27)
    ongoing1_event = {
        "id": "e_ongoing_1",
        "name": "Weekend Pop-Up Bazaar",
        "company_id": random.choice(COMPANIES)["id"],
        "start_date": ongoing1_start.isoformat(),
        "end_date": (TODAY + timedelta(days=random.randint(2, 5))).isoformat(),
        "payment_methods": ["CASH", "GCASH"],
        "assigned_employee_emails": [],
        "allocations": [],
    }
    events.append(ongoing1_event)

    e = make_event("e_ongoing_2", "Midweek Office Bazaar", TODAY, 2, 5, WEEKDAY_MONFRI, (0, 4))
    events.append(e)

    ongoing_events = events[-2:]

    # --- Incoming (>= Aug 24, at least 6, spread out, weekdays only) ---
    incoming_floor = date(2026, 8, 24)
    incoming_names = [
        "Back-to-School Bazaar", "Payday Pop-Up", "Harvest Festival Bazaar",
        "Founders' Week Bazaar", "Community Sale Days", "Sportsfest Sidewalk Sale",
        "Anniversary Bazaar", "Semestral Break Bazaar",
    ]
    incoming_events = []
    for i in range(6):
        ev = make_event(
            f"e_incoming_{i + 1}",
            incoming_names[i % len(incoming_names)],
            incoming_floor, 2, 5, WEEKDAY_MONFRI,
            (i * 6, i * 6 + 5),
        )
        incoming_events.append(ev)
    events.extend(incoming_events)

    # --- Finished (>= June 2, ended before today, at least 3, weekdays only) ---
    finished_floor = date(2026, 6, 2)
    finished_names = ["March Campus Bazaar", "Summer Kickoff Bazaar", "Mid-Year Sale Bazaar"]
    finished_events = []
    for i in range(3):
        ev = make_event(
            f"e_finished_{i + 1}",
            finished_names[i % len(finished_names)],
            finished_floor, 2, 5, WEEKDAY_MONFRI,
            (i * 12, i * 12 + 5),
        )
        # Safety clamp: make sure it actually ended before today.
        end = date.fromisoformat(ev["end_date"])
        if end >= TODAY:
            start = next_allowed_day(finished_floor, WEEKDAY_MONFRI)
            start, end = business_span(start, random.randint(2, 5), WEEKDAY_MONFRI)
            ev["start_date"], ev["end_date"] = start.isoformat(), end.isoformat()
        finished_events.append(ev)
    events.extend(finished_events)

    # Employee assignments: cycle employees across ongoing + incoming bazaars.
    assignable = ongoing_events + incoming_events
    for i, ev in enumerate(assignable):
        ev["assigned_employee_emails"] = [EMPLOYEE_EMAILS[i % len(EMPLOYEE_EMAILS)]]
    for i, ev in enumerate(finished_events):
        ev["assigned_employee_emails"] = [EMPLOYEE_EMAILS[i % len(EMPLOYEE_EMAILS)]]

    # Allocate stock to every event (order matters: shared master pool).
    # e_ongoing_1 gets a bigger allocation up front since its hand-tuned
    # "good/bad day" sales pattern below needs comfortably more stock than
    # the default allocation would give it.
    # August Fair goes first and takes the largest allocation: it is the only
    # bazaar selling on all five days of the current week, so it needs stock
    # for ~61 units before the shared pool is drawn down by anything else.
    allocate_event(august_fair, products, remaining, products_per_event=(10, 12), qty_range=(8, 12))
    allocate_event(ongoing1_event, products, remaining, products_per_event=(10, 12), qty_range=(6, 10))
    for ev in events:
        if ev is ongoing1_event or ev is august_fair:
            continue
        allocate_event(ev, products, remaining)

    # Sales for ongoing and finished bazaars only.
    # e_ongoing_1: hand-tuned counts for Mon-Fri of the current week, which
    # is exactly the window the dashboard's "Average Daily Sales" chart
    # plots, so it always shows a clear mix of good and bad days.
    monday_this_week = TODAY - timedelta(days=TODAY.weekday())
    sales = []

    # August Fair runs Mon-Fri on fixed dates, so its pattern is anchored to
    # its own start date rather than to this week's Monday.
    august_fair_targets = AUGUST_FAIR_DAY_TARGETS
    if AUGUST_FAIR_SALES_THROUGH_TODAY_ONLY:
        days_elapsed = (TODAY - AUGUST_FAIR_START).days
        august_fair_targets = [
            (offset, target)
            for offset, target in AUGUST_FAIR_DAY_TARGETS
            if offset <= days_elapsed
        ]
    sales.extend(generate_daily_sales_to_revenue(
        august_fair, remaining, AUGUST_FAIR_START, august_fair_targets,
        price_by_product={p["id"]: p["base_price"] for p in products},
        cap=AUGUST_FAIR_REVENUE_CAP,
    ))

    sales.extend(generate_daily_sales(
        ongoing1_event, remaining, ongoing1_start, monday_this_week,
        # Counts are sized against the ~PHP 2,000 average unit price so each
        # day's revenue lands inside the 10k-35k band the chart axis is
        # scaled for, while still reading as a clear good/bad zigzag.
        day_pattern=[
            (0, 8),   # Mon: steady opening
            (1, 11),  # Tue: picking up
            (2, 15),  # Wed: best day of the week
            (3, 6),   # Thu: worst day of the week
            (4, 13),  # Fri: strong finish
        ],
    ))
    # Every other bazaar gets the same per-day treatment, just with random
    # counts instead of a hand-tuned shape, so no day anywhere in the dataset
    # falls outside the 10k-35k band.
    for ev in ongoing_events + finished_events:
        if ev is ongoing1_event:
            continue
        start = date.fromisoformat(ev["start_date"])
        days_span = (date.fromisoformat(ev["end_date"]) - start).days + 1
        if ev in ongoing_events:
            # An ongoing bazaar hasn't sold anything past today yet.
            days_span = min(days_span, (TODAY - start).days + 1)
        sales.extend(generate_daily_sales(
            ev, remaining, start, start, random_day_pattern(days_span),
        ))

    data = {
        # The day this ran. Every bazaar below except August Fair is placed
        # relative to it, so the app shifts them forward by whole weeks on load
        # and the fixture keeps describing "now" instead of aging into a
        # calendar where nothing is running. Drop this key and the data silently
        # goes stale again a fortnight later.
        "generated_on": TODAY.isoformat(),
        "companies": COMPANIES,
        "products": products,
        "events": events,
        "sales": sales,
    }

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(data, indent=2))
    fair_sales = [s for s in sales if s["event_id"] == "e_august_fair"]
    print(f"Wrote {OUTPUT_PATH} ({len(products)} products, {len(events)} events, {len(sales)} sales)")
    print(
        f"  August Fair: {AUGUST_FAIR_START} to {AUGUST_FAIR_END}, "
        f"{len(august_fair['allocations'])} SKUs allocated, {len(fair_sales)} sales"
    )


if __name__ == "__main__":
    main()
