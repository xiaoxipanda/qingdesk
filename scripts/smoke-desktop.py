#!/usr/bin/env python3
"""Live window test: only the two dedicated Workbench Test applications are changed.

Build with build-fixtures.sh, then add both .app bundles to workbench favorites.
The workbench must be running and have Accessibility permission. Hermes is never used.
"""
import json
import subprocess
import sys

helper = sys.argv[1]
ids = ["local.desktop-workbench.test.left", "local.desktop-workbench.test.right"]

def call(name, arguments=None, expect_success=True):
    result = subprocess.run([helper, "--no-autostart", "--call", name, json.dumps(arguments or {})],
                            text=True, capture_output=True, timeout=40)
    data = json.loads(result.stdout)
    if expect_success:
        assert result.returncode == 0 and data.get("ok"), (name, data, result.stderr)
    return data

def near(a, b):
    return all(abs(a[key] - b[key]) <= 3 for key in ("x", "y", "width", "height"))

state = call("get_workspace_state")
assert state["accessibility_granted"], "Grant Accessibility to Desktop Workbench first"
assert all(any(app["app_id"] == app_id for app in state["apps"]) for app_id in ids), "Add the two test fixtures first"
original = {}
references = []
for app_id in ids:
    ready = call("ensure_app", {"app_id": app_id, "timeout_seconds": 15})
    assert ready["pid"] > 0 and ready["window"]["frame"]["width"] > 0
    original[app_id] = ready["window"]["frame"]
    references.append(ready["window"]["window_ref"])

failed = call("ensure_app", {"app_id": ids[0], "window_ref": "closed-window"}, expect_success=False)
assert failed["code"] == "window_stale", failed
screen = state["screens"][0]["frame"]
for preset in ("left_right", "top_bottom", "focus_left", "focus_right"):
    placed = call("apply_layout", {"app_ids": ids, "preset": preset, "window_refs": references})
    assert placed["verified"] and len(placed["windows"]) == 2, placed
    left, right = [window["frame"] for window in placed["windows"]]
    for frame in (left, right):
        assert screen["x"] <= frame["x"] and screen["y"] <= frame["y"]
        assert frame["x"] + frame["width"] <= screen["x"] + screen["width"] + 3
        assert frame["y"] + frame["height"] <= screen["y"] + screen["height"] + 3
    if preset == "top_bottom":
        assert left["y"] + left["height"] <= right["y"] + 3
    else:
        assert left["x"] + left["width"] <= right["x"] + 3
    restored = call("restore_layout")
    assert restored["verified"]
    current = call("get_workspace_state")
    for app_id in ids:
        app = next(app for app in current["apps"] if app["app_id"] == app_id)
        assert len(app["windows"]) == 1 and near(app["windows"][0]["frame"], original[app_id]), app

print(json.dumps({"passed": True, "layouts": 4, "restoration_verified": True,
                  "stale_window_rejected": True, "targets": ids}, ensure_ascii=False))
