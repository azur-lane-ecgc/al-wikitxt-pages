#!/usr/bin/env python3
"""Generate modules/CommonResourceData.lua from the ecgc-dev common resource JSON dump.

Pipeline:
  1. cd <ecgc-dev>/packages/frontend
  2. bun run <wiki-repo>/scripts/common_resource/dump_common_resource.ts > /tmp/common_resource.json
  3. uv run scripts/common_resource/generate_common_resource.py /tmp/common_resource.json

Outputs:
  - modules/CommonResourceData.lua            (Lua data module, generated; do not hand-edit)
  - scripts/common_resource/common_resource_expected.lua      (totals from the TS dump, used by the Lua test harness)

Run the test harness after regenerating:
  cd <wiki-repo>
  script -q /dev/null bunx wasmoon -l modules -l scripts scripts/common_resource/run_tests.lua
"""

import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
DATA_OUT = REPO_ROOT / "modules" / "CommonResourceData.lua"
EXPECTED_OUT = REPO_ROOT / "scripts" / "common_resource" / "common_resource_expected.lua"

# Canonical source-group order (matches the ecgc-dev modal layout: Daily, Farming, Shops).
GROUP_ORDER = [
    "academy",
    "missions",
    "dailyRaid",
    "cruisePass",
    "campaignDrop",
    "hardModeDrop",
    "eventDrop",
    "opsi",
    "generalShop",
    "coreDataShop",
    "guildShop",
    "meritShop",
    "medalShop",
    "prototypeShop",
    "eventShop",
    "metaShop",
]

# Item-cell wikitext (wiki Display templates) keyed by ecgc resource name.
ICONS = {
    "Coin": "{{Display|Coinicon|N|Coin|50}}",
    "Oil": "{{Display|Oilicon|N|Oil|50}}",
    "Core Data": "{{Display|Core Data|R|Core Data|50}}",
    "Guild Token": "{{Display|GuildToken|R|Guild Token|50}}",
    "Crystal Fragment": "{{Display|Crystal Fragment|SR|Crystal Fragment|50}}",
    "Prototype Core": "{{Display|Protocoreicon|SR|Prototype Core|50}}",
    "Wisdom Cube": "{{Display|Wisdom Cube|SR|Wisdom Cube}}",
    "T1 EXP Data Pack": "{{Display|T1EXP|R|T1 EXP Data Pack|50}}",
    "High-Efficiency Combat Logistics Plan": "{{Display|High-Efficiency Combat Logistics Plan|P|High-Efficiency Combat Logistics Plan|50}}",
    "Cognitive Chip": "{{Display|Cognitive Chip|SR|Cognitive Chip|50}}",
    "Cognitive Array": "{{Display|Cognitive Array|SR|Cognitive Array|50}}",
    "Universal Bulin": "{{Display|Universal BulinIcon|P|Universal Bulin|50}}",
    "Prototype Bulin MKII": "{{Display|Prototype Bulin MKIIIcon|SR|Prototype Bulin MKII|50}}",
    "Specialized Bulin Custom MKIII": "{{Display|Specialized Bulin Custom MKIIIIcon|UR|Specialized Bulin Custom MKIII|50}}",
    "T1 Plate": "{{Display|UnknownT1Plate|N|T1 Plate|50}}",
    "T2 Plate": "{{Display|UnknownT2Plate|R|T2 Plate|50}}",
    "T3 Plate": "{{Display|UnknownT3Plate|P|T3 Plate|50}}",
    "T4 Plate": "{{Display|UnknownT4Plate|SR|T4 Plate|50}}",
    "Augment Module Core": "{{Display|Augment Module Core|SR|Augment Module Core|50}}",
    "Augment Module EXP": "{{Display|T1 Augment Module Stone|R|Augment Module Stone T1|50}} {{Display|T2 Augment Module Stone|E|Augment Module Stone T2|50}} {{Display|T3 Augment Module Stone|SR|Augment Module Stone T3|50}}",
    "T1 Augment Conversion": "{{Display|T1 Augment Module Conversion Stone|E|Augment Module Conversion Stone T1|50}}",
    "T2 Augment Conversion": "{{Display|T2 Augment Module Conversion Stone|SR|Augment Module Conversion Stone T2|50}}",
    "T1 Retrofit Blueprint": "{{Display|UnknownT1BP|R|T1 Retrofit Blueprint|50}}",
    "T2 Retrofit Blueprint": "{{Display|UnknownT2BP|P|T2 Retrofit Blueprint|50}}",
    "T3 Retrofit Blueprint": "{{Display|UnknownT3BP|SR|T3 Retrofit Blueprint|50}}",
    "T1 Skill Book": "{{Display|UnknownT1Book|R|T1 Skill Book}}",
    "T2 Skill Book": "{{Display|UnknownT2Book|P|T2 Skill Book}}",
    "T3 Skill Book": "{{Display|UnknownT3Book|SR|T3 Skill Book}}",
    "T4 Skill Book": "{{Display|UnknownT4Book|UR|T4 Skill Book}}",
    "Gem": "{{Display|Ruby|P|Gems|50}}",
}

WIKI_ANCHOR_RE = re.compile(
    r'<a\s+href="https://azurlane\.koumakan\.jp/wiki/([^"]+)"[^>]*>\s*(.*?)\s*</a>',
    re.DOTALL,
)
INTERNAL_ANCHOR_RE = re.compile(r'<a\s+href="(/[^"]*)"[^>]*>\s*(.*?)\s*</a>', re.DOTALL)


def html_to_wikitext(text: str) -> str:
    """Convert ecgc-dev JSX notes HTML into wiki markup."""
    text = re.sub(r"\s+", " ", text).strip()

    def wiki_link(match: re.Match) -> str:
        page = unquote(match.group(1)).replace(" ", "_")
        label = match.group(2)
        return f"[[{page}|{label}]]"

    text = WIKI_ANCHOR_RE.sub(wiki_link, text)
    # Links into the ecgc site itself have no wiki equivalent: keep the label text only.
    text = INTERNAL_ANCHOR_RE.sub(lambda m: m.group(2), text)
    text = re.sub(r"<b>\s*(.*?)\s*</b>", r"'''\1'''", text)
    text = re.sub(r"<i>\s*(.*?)\s*</i>", r"''\1''", text)
    text = re.sub(r"<br\s*/?>", "<br />", text)
    text = re.sub(r"</?(?:p|span|div)[^>]*>", "", text)
    return text.strip()


def lua_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")
    return f"'{escaped}'"


def table_safe(text: str) -> str:
    """Escape characters that would break wikitext table cells (notes only)."""
    return text.replace("|", "{{!}}")


def lua_number(value) -> str:
    if isinstance(value, str):  # "RNG" or "N/A" pass through
        return lua_string(value)
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return repr(value)


def lua_bool_or_nil(value) -> str:
    return "true" if value else "nil"


def render_location(loc: dict, indent: str) -> str:
    qty = loc["quantity"]
    lines = [
        f"{indent}{{",
        f"{indent}  name = {lua_string(loc['name'])},",
        f"{indent}  link = {lua_string(loc.get('wikiLink', ''))},",
        f"{indent}  amount = {lua_number(qty['amount'])},",
        f"{indent}  timeFrame = {lua_string(str(qty['timeFrame'])) if qty['timeFrame'] else 'nil'},",
    ]
    notes = loc.get("notes")
    if notes:
        lines.append(f"{indent}  notes = {lua_string(html_to_wikitext(table_safe(notes)))},")
    lines.append(f"{indent}}}")
    return "\n".join(lines)


def render_drop_group(group_key: str, group: dict, indent: str) -> str:
    mark = group["checkMark"]
    lines = [
        f"{indent}{{",
        f"{indent}  group = {lua_string(group_key)},",
        f"{indent}  color = {lua_string(mark['color'])},",
        f"{indent}  mark = {lua_string(mark['mark'])},",
        f"{indent}  optimal = {lua_bool_or_nil(mark.get('optimal'))},",
        f"{indent}  locations = {{",
    ]
    for loc in group.get("locations") or []:
        lines.append(render_location(loc, indent + "    ") + ",")
    lines.append(f"{indent}  }},")
    lines.append(f"{indent}}}")
    return "\n".join(lines)


def render_resource(resource: dict, indent: str) -> str:
    lines = [
        f"{indent}{{",
        f"{indent}  name = {lua_string(resource['name'])},",
        f"{indent}  category = {lua_string(resource['category'])},",
        f"{indent}  icon = {lua_string(ICONS[resource['name']])},",
        f"{indent}  link = {lua_string(resource.get('wikiLink', ''))},",
        f"{indent}  drops = {{",
    ]
    ordered = [
        (key, resource["drops"][key])
        for key in GROUP_ORDER
        if key in resource["drops"] and resource["drops"][key].get("found")
    ]
    for key, group in ordered:
        lines.append(render_drop_group(key, group, indent + "    ") + ",")
    lines.append(f"{indent}  }},")
    # Totals are taken verbatim from the TS dump: 21 resources run
    # getTotalGuaranteed, the 9 type-random ones (plates T1-T3, skill books
    # T1-T3, retrofit prints T1-T3) hardcode 'N/A'.
    total = resource["total"]
    lines.append(
        f"{indent}  total = {{ bimonthly = {lua_number(total['bimonthly'])},"
        f" monthly = {lua_number(total['monthly'])},"
        f" weekly = {lua_number(total['weekly'])},"
        f" daily = {lua_number(total['daily'])},"
        f" oneTime = {lua_number(total.get('oneTime', 'N/A'))} }},"
    )
    notes = resource.get("notes")
    if notes:
        lines.append(f"{indent}  notes = {lua_string(html_to_wikitext(table_safe(notes)))},")
    lines.append(f"{indent}}}")
    return "\n".join(lines)


def generate_data_module(dump: dict) -> str:
    header = (
        "-- Data module for the Common Resource guide.\n"
        "-- GENERATED by scripts/common_resource/generate_common_resource.py from the ecgc-dev\n"
        "-- CommonResourceData TypeScript source. DO NOT EDIT BY HAND.\n"
        "-- Regenerate with: uv run scripts/common_resource/generate_common_resource.py <dump.json>\n"
        "-- Schema per resource: name, category, icon (wikitext), link (wiki page),\n"
        "--   drops = { { group, color, mark, optimal, locations = { { name, link,\n"
        "--     amount (number or 'RNG'), timeFrame, notes } } } }, notes.\n"
        "-- timeFrame values: daily, weekly, monthly, bimonthly, one-time, chapter,\n"
        "--   cycle, or nil.\n\n"
        "return {\n"
    )
    out = [header]
    for section in ("infinite", "finite"):
        out.append(f"  {section} = {{\n")
        for resource in dump[section]:
            out.append(render_resource(resource, "    ") + ",\n")
        out.append("  },\n")
    out.append("}\n")
    return "".join(out)


def generate_expected_totals(dump: dict) -> str:
    lines = [
        "-- Expected totals as computed by the ecgc-dev TypeScript getTotalGuaranteed.\n"
        "-- GENERATED by scripts/common_resource/generate_common_resource.py. Used by scripts/common_resource/run_tests.lua.\n"
        "-- oneTime uses the string 'N/A' where the TS side reports N/A.\n\n"
        "return {\n",
    ]
    for section in ("infinite", "finite"):
        lines.append(f"  {section} = {{\n")
        for resource in dump[section]:
            total = resource["total"]
            one_time = total.get("oneTime", "N/A")
            lines.append(
                "    [%s] = { bimonthly = %s, monthly = %s, weekly = %s, daily = %s, oneTime = %s },\n"
                % (
                    lua_string(resource["name"]),
                    lua_number(total["bimonthly"]),
                    lua_number(total["monthly"]),
                    lua_number(total["weekly"]),
                    lua_number(total["daily"]),
                    lua_number(one_time) if not isinstance(one_time, str) else lua_string(one_time),
                )
            )
        lines.append("  },\n")
    lines.append("}\n")
    return "".join(lines)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <common_resource.json>")
    dump = json.loads(Path(sys.argv[1]).read_text())

    missing = [r["name"] for s in ("infinite", "finite") for r in dump[s] if r["name"] not in ICONS]
    if missing:
        sys.exit(f"missing icon mapping for: {missing}")

    DATA_OUT.write_text(generate_data_module(dump))
    EXPECTED_OUT.write_text(generate_expected_totals(dump))
    print(f"wrote {DATA_OUT}")
    print(f"wrote {EXPECTED_OUT}")
    print(f"resources: {len(dump['infinite'])} renewable, {len(dump['finite'])} finite")


if __name__ == "__main__":
    main()
