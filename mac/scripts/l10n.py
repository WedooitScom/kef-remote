#!/usr/bin/env python3
"""Vérifie les String Catalogs (Sources/<module>/Localizable.xcstrings) contre le code.

    python3 scripts/l10n.py            # compile avec extraction, liste clés manquantes / obsolètes
    python3 scripts/l10n.py --keys     # affiche les clés extraites (JSON) sans comparer

Le compilateur Swift (-emit-localized-strings) relève toutes les chaînes réellement
localisées : littéraux de Text/Button/Label/help…, String(localized:), LocalizedStringResource
et l'aide `localized(_:)` de KEFKit, avec les bons formats (%@, %lld…). La compilation se
fait dans un dossier à part (.build/l10n) pour ne pas invalider la compilation normale.
"""
import glob
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODULES = ["KEFKit", "KEFRemote"]
LANGUAGES = ["en", "es", "it", "ja"]


def extract():
    scratch = os.path.join(ROOT, ".build", "l10n")
    subprocess.run(["swift", "build", "--scratch-path", scratch, "-Xswiftc", "-emit-localized-strings"],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    keys = {m: set() for m in MODULES}
    for path in glob.glob(os.path.join(scratch, "**", "*.stringsdata"), recursive=True):
        data = json.load(open(path))
        source = os.path.realpath(data.get("source", ""))
        for module in MODULES:
            if source.startswith(os.path.realpath(os.path.join(ROOT, "Sources", module)) + os.sep):
                for entry in data.get("tables", {}).get("Localizable", []):
                    keys[module].add(entry["key"])
    return keys


def has_value(loc):
    if not loc:
        return False
    unit = loc.get("stringUnit")
    if unit:
        return bool(unit.get("value", "").strip())
    plural = loc.get("variations", {}).get("plural", {})
    return bool(plural) and all(v.get("stringUnit", {}).get("value", "").strip() for v in plural.values())


def main():
    keys = extract()
    if "--keys" in sys.argv:
        print(json.dumps({m: sorted(k) for m, k in keys.items()}, ensure_ascii=False, indent=1))
        return 0
    problems = 0
    for module in MODULES:
        catalog = json.load(open(os.path.join(ROOT, "Sources", module, "Localizable.xcstrings")))
        strings = catalog["strings"]
        missing = sorted(keys[module] - strings.keys())
        stale = sorted(strings.keys() - keys[module])
        untranslated = sorted(k for k, v in strings.items()
                              if v.get("shouldTranslate", True)
                              and not all(has_value(v.get("localizations", {}).get(lang)) for lang in LANGUAGES))
        for title, items in (("absentes du catalogue", missing), ("obsolètes", stale),
                             ("non traduites", untranslated)):
            if items:
                problems += len(items)
                print(f"{module} : {len(items)} clé(s) {title}")
                for k in items:
                    print(f"  {k!r}")
        print(f"{module} : {len(keys[module])} clés dans le code, {len(strings)} dans le catalogue")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
