#!/usr/bin/env python3
"""Factual current-source inventory; no remote probes or account access."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
out = root / "Design/Completion/2026-10-10"
out.mkdir(parents=True, exist_ok=True)
source = root / "Suzzme/Core/Integrations"
recipes = {}
for filename in ["ProviderReadRecipe.swift", "GoogleProviderRecipes.swift"]:
    for line in (source / filename).read_text().splitlines():
        match = re.search(r'(?:\.init\(id: \.(\w+), name:|google\(\.(\w+),) "([^"]+)"', line)
        if not match:
            continue
        doc = re.search(r'documentation: "([^"]+)"', line)
        scope = re.search(r'scope: "([^"]+)"', line) if filename.startswith("Google") else None
        recipes[match[3]] = dict(provider_id=match[1] or match[2],
            documentation=doc[1] if doc else None, google_scope=scope[1] if scope else None)
assert len(recipes) == 24
directory = (source / "IntegrationDirectory.swift").read_text()
rows = [dict(id=m[1], name=m[2], group=m[3]) for m in re.finditer(
    r'\.init\(id: "([^"]+)", name: "([^"]+)", section: \.(\w+)', directory)]
rows += [dict(id=m[1].lower().replace(" ", "-").replace(".", "-"), name=m[1], group=m[2])
    for m in re.finditer(r'^\s*listed\("([^"]+)", \.(\w+),', directory, re.M)]
assert len(rows) == 121 and len({row["id"] for row in rows}) == 121
for row in rows:
    name = row["name"]
    row.update(live_account_acceptance="PENDING", external_actions="DISABLED", summary_intake="UNAVAILABLE")
    if name in recipes:
        recipe = recipes[name]
        row.update(recipe)
        row.update(implementation="IMPLEMENTED — bounded request-local reads",
            authentication="Registered Google OAuth required" if recipe["google_scope"] else "User-managed personal credential required",
            api_review="Existing recipe; HTTP fixtures passed; live API/account acceptance pending")
    elif name in ["GitHub", "Notion", "Linear"]:
        row.update(implementation="IMPLEMENTED — reviewed resource reads", authentication="Scoped personal token required",
            summary_intake="EXPLICIT OPT-IN — selected allowed issue/PR/page URLs",
            api_review="Established connector; automated checks passed; live acceptance pending")
    elif name == "Gmail":
        row.update(implementation="IMPLEMENTED — inbox headers only", authentication="Google client IDs still placeholders",
            summary_intake="EXPLICIT SOURCE OPT-IN", api_review="Metadata client exists; OAuth registration/live acceptance pending")
    elif name == "LinkedIn":
        row.update(implementation="LIMITED — explicitly shared screen only", authentication="No account connector",
            api_review="Authenticated API capabilities require actual program approval and reviewed scopes")
    elif name == "WhatsApp":
        row.update(implementation="INTENTIONALLY EXCLUDED — no chats/contacts/messages", authentication="Unavailable",
            api_review="No approved supported non-chat use case; no scraping/private database substitute")
    else:
        row.update(implementation="CATALOG ONLY — no connector", authentication="Unavailable",
            api_review="NOT INDIVIDUALLY VERIFIED — API/auth/approval feasibility audit remains incomplete")
rows.sort(key=lambda row: row["name"].casefold())
(out / "integration-inventory.json").write_text(json.dumps(rows, indent=2) + "\n")
lines = ["# Integration inventory — 10 October 2026", "",
    "Generated from the current 121-item directory and 24 existing recipes. This is an implementation inventory, not live API acceptance.", "",
    "27 implemented provider reads, Gmail separately, LinkedIn screen-only, 92 catalog-only entries (including intentionally excluded WhatsApp). No live external account accepted in this pass. **Individual feasibility review of the 92 catalog-only APIs remains unfinished.**", "",
    "| Provider | Implementation | Authentication / next requirement | Summary intake |", "|---|---|---|---|"]
for row in rows:
    lines.append("| " + " | ".join(row[key] for key in ["name", "implementation", "authentication", "summary_intake"]) + " |")
lines += ["", "The JSON companion records every entry's review state and existing recipe documentation URL. Catalog-only does not mean the provider has no API; it means Suzzme has no implemented connector. No generic Connect button is enabled for these entries.", "",
    "Selected official checks: [Contentful read-only CMA scopes](https://www.contentful.com/developers/docs/references/content-management-api/access-tokens/), [Google Meet records](https://developers.google.com/workspace/meet/api/reference/rest/v2/conferenceRecords/list), [BigQuery datasets](https://docs.cloud.google.com/bigquery/docs/reference/rest/v2/datasets/list), [YNAB API](https://api.ynab.com/). These checks do not accept real account behavior."]
(out / "INTEGRATIONS.md").write_text("\n".join(lines) + "\n")
print("Inventoried 121 directory entries and 24 existing recipes. No live-account acceptance.")
