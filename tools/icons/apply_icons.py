"""Put uploaded icon asset ids into the game.

1. Upload the PNGs in tools/icons/out to Roblox (Studio: View > Asset Manager > Bulk Import).
2. In icon_ids.json, paste each image's asset id next to its file name (numbers only are fine).
3. Run from the repo root:   python3 tools/icons/apply_icons.py
   This writes src/ReplicatedStorage/Shared/IconIds.luau and rebuilds rainfall.rbxl.
Entries left empty keep the icon the game uses today.
"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SHOP = {"Vitality", "Iron", "Swift", "Power", "Regen"}
SPECIAL = {"WarBand", "MinionUpgrade"}
SKILLS = {"Skill_ShadowStep": "Shadow Step", "Skill_ArcaneBurst": "Arcane Burst", "Skill_DashShot": "Dash Shot",
          "Skill_TauntingShockwave": "Taunting Shockwave", "Skill_BloodRush": "Blood Rush"}


def asset(value):
    value = str(value or "").strip()
    digits = re.sub(r"\D", "", value)
    return "rbxassetid://" + digits if digits else ""


def lua_table(entries):
    lines = ["{"]
    for key in sorted(entries):
        lines.append('\t\t["%s"] = "%s",' % (key, entries[key]))
    lines.append("\t}")
    return "\n".join(lines) if len(lines) > 2 else "{}"


def main():
    ids = json.load(open(os.path.join(HERE, "icon_ids.json")))
    groups = {"Items": {}, "Shop": {}, "Special": {}, "Skills": {}}
    for name, value in ids.items():
        icon = asset(value)
        if not icon:
            continue
        if name in SHOP:
            groups["Shop"][name] = icon
        elif name in SPECIAL:
            groups["Special"][name] = icon
        elif name in SKILLS:
            groups["Skills"][SKILLS[name]] = icon
        else:
            groups["Items"][name] = icon
    out = ["-- IconIds: uploaded icon images (the painted icons in tools/icons/out). Filled in by",
           "-- tools/icons/apply_icons.py from tools/icons/icon_ids.json - edit that json, not this file.",
           "-- An empty table keeps the existing icons. Values are \"rbxassetid://<id>\".",
           "return {"]
    for group in ("Items", "Shop", "Special", "Skills"):
        out.append("\t%s = %s," % (group, lua_table(groups[group])))
    out.append("}")
    path = os.path.join(ROOT, "src", "ReplicatedStorage", "Shared", "IconIds.luau")
    open(path, "w").write("\n".join(out) + "\n")
    print("icons set:", {k: len(v) for k, v in groups.items()})
    subprocess.check_call([sys.executable, os.path.join(ROOT, "tools", "rbxl_build.py"),
                           os.path.join(ROOT, "rainfall.rbxl"), os.path.join(ROOT, "src"), os.path.join(ROOT, "rainfall.rbxl")])


if __name__ == "__main__":
    main()
