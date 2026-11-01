#!/usr/bin/env python3
"""Builds the studio page (site/) into a folder ready for GitHub Pages.

Copies the page's files and writes studio.json: the repository and the workflows the page can
start (the story video and the chase / action video) with their inputs, read from the workflow
files. So the page's forms always match the workflows: add an option there and it shows up on the
page with the next build.

Usage: tools/site/build.py OUT_DIR [--repo owner/name] [--branch main]
Needs PyYAML (pip install pyyaml).
"""
import argparse
import json
import os
import shutil
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# key, workflow file, label on the page, release tag prefix of its videos
WORKFLOWS = [("story", "story.yml", "🎭 Story", "story-"), ("chase", "record.yml", "🚓 Chase & action", "chase-")]
FILES = ["index.html", "app.js", "style.css"]


def inputs(path):
    with open(path, encoding="utf-8") as f:
        doc = yaml.safe_load(f)
    # YAML 1.1 reads the key "on" as True
    on = doc.get("on", doc.get(True)) or {}
    out = []
    for name, spec in ((on.get("workflow_dispatch") or {}).get("inputs") or {}).items():
        spec = spec or {}
        kind = str(spec.get("type", "string"))
        item = {"name": str(name), "type": kind, "description": str(spec.get("description", "")),
                "required": bool(spec.get("required", False))}
        default = spec.get("default", "")
        if kind == "boolean":
            item["default"] = "true" if default in (True, "true") else "false"
        else:
            item["default"] = "" if default is None else str(default)
        if kind == "choice":
            item["options"] = [str(o) for o in spec.get("options", [])]
            if item["default"] not in item["options"] and item["options"]:
                item["default"] = item["options"][0]
        out.append(item)
    return str(doc.get("name", os.path.basename(path))), out


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out")
    ap.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", "boidbit/cubecity"))
    ap.add_argument("--branch", default="main")
    a = ap.parse_args(argv)
    flows = []
    for key, file, label, prefix in WORKFLOWS:
        name, fields = inputs(os.path.join(ROOT, ".github", "workflows", file))
        if not fields:
            sys.exit(f"{file} has no workflow_dispatch inputs")
        flows.append({"key": key, "file": file, "label": label, "prefix": prefix, "name": name, "inputs": fields})
    os.makedirs(a.out, exist_ok=True)
    for f in FILES:
        shutil.copy(os.path.join(ROOT, "site", f), os.path.join(a.out, f))
    cfg = {"repo": a.repo, "branch": a.branch, "workflows": flows, "built": os.environ.get("GITHUB_SHA", "")[:7]}
    with open(os.path.join(a.out, "studio.json"), "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=1)
    for f in flows:
        print(f"studio page -> {a.out}: {f['file']} ({len(f['inputs'])} inputs: {', '.join(i['name'] for i in f['inputs'])})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
