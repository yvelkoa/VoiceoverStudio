"""Fills the string catalogs from `translations.py`, or with `--check` only verifies that nothing is missing."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from translations import APP, INFO_PLIST, KIT  # noqa: E402

ROOT = Path(__file__).parent.parent
CATALOGS = {
    ROOT / "App/Resources/Localizable.xcstrings": APP,
    ROOT / "Packages/VoiceoverKit/Sources/VoiceoverKit/Resources/Localizable.xcstrings": KIT,
}
INFO_CATALOG = ROOT / "App/Resources/InfoPlist.xcstrings"
LANGUAGES = ("ru", "uk")

# English plural forms; the key itself is the "other" form.
EN_PLURALS = {
    "Add %lld effects": {"one": "Add %lld effect", "other": "Add %lld effects"},
    "%lld takes": {"one": "%lld take", "other": "%lld takes"},
    "%lld characters. Each character uses one ElevenLabs credit.": {
        "one": "%lld character. Each character uses one ElevenLabs credit.",
        "other": "%lld characters. Each character uses one ElevenLabs credit.",
    },
}


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def localization(value):
    if isinstance(value, dict):
        return {"variations": {"plural": {form: unit(text) for form, text in value.items()}}}
    return unit(value)


def write(path, catalog):
    text = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : "))
    path.write_text(text + "\n")


def fill(path, table, check):
    catalog = json.loads(path.read_text())
    missing = []
    for key, entry in catalog["strings"].items():
        if entry.get("extractionState") == "stale":
            continue
        if key not in table:
            missing.append(key)
            continue
        value = table[key]
        if value is None:
            entry.pop("localizations", None)
            entry["shouldTranslate"] = False
            continue
        entry.pop("shouldTranslate", None)
        localizations = {lang: localization(text) for lang, text in zip(LANGUAGES, value)}
        if key in EN_PLURALS:
            localizations["en"] = localization(EN_PLURALS[key])
        if check and entry.get("localizations") != localizations:
            missing.append(key)
        entry["localizations"] = localizations
    if not check:
        catalog["strings"] = {k: v for k, v in catalog["strings"].items() if v.get("extractionState") != "stale"}
        write(path, catalog)
    return missing


def fill_info_plist(check):
    catalog = {"sourceLanguage": "en", "version": "1.0", "strings": {}}
    for key, (en, ru, uk) in INFO_PLIST.items():
        catalog["strings"][key] = {
            "extractionState": "manual",
            "localizations": {"en": unit(en), "ru": unit(ru), "uk": unit(uk)},
        }
    if check:
        return [] if json.loads(INFO_CATALOG.read_text()) == catalog else ["InfoPlist.xcstrings is out of date"]
    write(INFO_CATALOG, catalog)
    return []


def main():
    check = "--check" in sys.argv
    problems = []
    for path, table in CATALOGS.items():
        problems += [f"{path.name}: {key}" for key in fill(path, table, check)]
    problems += fill_info_plist(check)
    if problems:
        print("Untranslated or stale strings (run Scripts/strings.sh):")
        print("\n".join(f"  {p}" for p in problems))
        sys.exit(1)
    print("Strings OK" if check else "Catalogs filled")


main()
