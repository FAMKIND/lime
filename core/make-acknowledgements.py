#!/usr/bin/env python3
"""Writes ios/Lime/Resources/Acknowledgements.txt: the licence notices of everything LimeCore links
into the iOS app (normal dependencies for the iOS targets; not build tools or test crates), with each
crate's own licence files, and the SQLCipher (Zetetic) notice that binary distribution must reproduce.

Run it again when dependencies change:  ./core/make-acknowledgements.py
"""
import hashlib, json, os, subprocess, sys

here = os.path.dirname(os.path.abspath(__file__))
out_path = os.path.join(here, "..", "ios", "Lime", "Resources", "Acknowledgements.txt")

def run(*cmd):
    return subprocess.run(cmd, cwd=here, check=True, capture_output=True, text=True).stdout

meta = json.loads(run("cargo", "metadata", "--format-version", "1", "--locked"))
packages = {p["id"]: p for p in meta["packages"]}

linked = set()
for target in ("aarch64-apple-ios", "aarch64-apple-ios-sim"):
    tree = run("cargo", "tree", "-e", "normal", "--target", target, "--prefix", "none", "--format", "{p}", "--locked")
    for line in tree.splitlines():
        parts = line.replace(" (*)", "").split()
        if len(parts) >= 2:
            linked.add((parts[0], parts[1].lstrip("v")))
by_name = {(p["name"], p["version"]): p for p in packages.values()}

names = sorted(n for n in linked if n[0] not in ("lime_core", "lime_mesh") and n in by_name)  # lime's own crates are not third-party
texts = {}      # sha -> text
users = {}      # sha -> [crate names]
rows = []
for name, version in names:
    pkg = by_name[(name, version)]
    folder = os.path.dirname(pkg["manifest_path"])
    files = sorted(f for f in os.listdir(folder) if f.upper().startswith(("LICENSE", "LICENCE", "COPYING", "UNLICENSE", "NOTICE")) and os.path.isfile(os.path.join(folder, f)))
    shas = []
    for f in files:
        text = open(os.path.join(folder, f), encoding="utf-8", errors="replace").read().strip()
        sha = hashlib.sha256(text.encode()).hexdigest()
        texts[sha] = text
        users.setdefault(sha, []).append(f"{name} {version}")
        shas.append(sha)
    rows.append((name, version, pkg.get("license") or "see licence files", pkg.get("repository") or "", shas))

# SQLCipher: vendored inside libsqlite3-sys
sqlcipher = None
for (name, version), pkg in by_name.items():
    if name == "libsqlite3-sys":
        path = os.path.join(os.path.dirname(pkg["manifest_path"]), "sqlcipher", "LICENSE")
        if os.path.exists(path):
            sqlcipher = open(path, encoding="utf-8", errors="replace").read().strip()
            sqlcipher_version = version
if not sqlcipher:
    sys.exit("could not find the SQLCipher licence in libsqlite3-sys")

lines = []
lines.append("LIME ACKNOWLEDGEMENTS")
lines.append("=====================\n")
lines.append("Lime is built with the open-source software below. Thank you to everyone who made it.")
lines.append("Lime's own code is MIT-licensed. This list is generated from the libraries linked into the app")
lines.append("(core/make-acknowledgements.py); the full text of each licence follows the list.\n")
lines.append("SQLCIPHER (the encrypted local database)")
lines.append("----------------------------------------")
lines.append("Lime's on-device store uses SQLCipher Community Edition by Zetetic LLC (bundled with")
lines.append(f"libsqlite3-sys {sqlcipher_version}), which includes SQLite (public domain). Its licence:\n")
lines.append(sqlcipher + "\n")
lines.append("CALLS (WebRTC and LiveKit)")
lines.append("--------------------------")
lines.append("Lime's one-to-one calls use Google's WebRTC (packaged by stasel/WebRTC) and its group calls use the LiveKit client SDK")
lines.append("for Swift with LiveKit's own build of WebRTC (livekit/webrtc-xcframework) and its small Rust library")
lines.append("(livekit/livekit-uniffi-xcframework). The media server is LiveKit's open-source server. Their licences:")
lines.append("  WebRTC (Google, the WebRTC project authors; stasel/WebRTC and livekit/webrtc-xcframework)  [BSD-3-Clause]")
lines.append("  LiveKit client SDK for Swift, livekit-uniffi-xcframework and the LiveKit server  [Apache-2.0]  https://github.com/livekit")
lines.append("")
lines.append("  WebRTC: Copyright (c) 2011, The WebRTC project authors. All rights reserved. Redistribution and use in source and binary")
lines.append("  forms, with or without modification, are permitted provided that the following conditions are met: redistributions of")
lines.append("  source code must retain the above copyright notice, this list of conditions and the following disclaimer; redistributions")
lines.append("  in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the")
lines.append("  documentation and/or other materials provided with the distribution; neither the name of Google nor the names of its")
lines.append("  contributors may be used to endorse or promote products derived from this software without specific prior written")
lines.append("  permission. THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \"AS IS\" AND ANY EXPRESS OR IMPLIED")
lines.append("  WARRANTIES ARE DISCLAIMED. The Apache-2.0 text for LiveKit is among the licence texts at the end of this file.\n")
lines.append("LIBRARIES")
lines.append("---------")
for name, version, lic, repo, shas in rows:
    lines.append(f"{name} {version}  [{lic}]" + (f"  {repo}" if repo else ""))
lines.append("")
lines.append("LICENCE TEXTS")
lines.append("-------------")
for sha, text in sorted(texts.items(), key=lambda kv: sorted(users[kv[0]])[0]):
    who = sorted(set(users[sha]))
    lines.append("=" * 72)
    lines.append(", ".join(who))
    lines.append("=" * 72)
    lines.append(text + "\n")
os.makedirs(os.path.dirname(out_path), exist_ok=True)
open(out_path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print(f"{len(rows)} libraries, {len(texts)} distinct licence texts, {os.path.getsize(out_path) // 1024} KB -> {os.path.relpath(out_path)}")
