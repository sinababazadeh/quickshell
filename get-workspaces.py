#!/usr/bin/env python3
import json
import subprocess
import sys

def get_hyprland_workspaces():
    # 1. Fetch workspaces
    try:
        ws_proc = subprocess.run(["hyprctl", "-j", "workspaces"], capture_output=True, text=True, timeout=1)
        workspaces = json.loads(ws_proc.stdout) if ws_proc.returncode == 0 and ws_proc.stdout.strip() else []
    except Exception:
        workspaces = []

    # 2. Fetch clients (windows)
    try:
        cl_proc = subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True, timeout=1)
        clients = json.loads(cl_proc.stdout) if cl_proc.returncode == 0 and cl_proc.stdout.strip() else []
    except Exception:
        clients = []

    # 3. Fetch active workspace
    active_id = None
    try:
        act_proc = subprocess.run(["hyprctl", "-j", "activeworkspace"], capture_output=True, text=True, timeout=1)
        if act_proc.returncode == 0 and act_proc.stdout.strip():
            act_data = json.loads(act_proc.stdout)
            active_id = act_data.get("id")
    except Exception:
        pass

    # 4. Fetch monitors
    monitors = []
    try:
        mon_proc = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True, timeout=1)
        if mon_proc.returncode == 0 and mon_proc.stdout.strip():
            monitors = json.loads(mon_proc.stdout)
    except Exception:
        monitors = []

    ws_map = {}
    for w in workspaces:
        ws_id = w.get("id")
        win_count = w.get("windows", 0)
        # Filter: ONLY occupied workspaces (has windows > 0 or is the currently active workspace)
        if win_count > 0 or ws_id == active_id:
            ws_map[ws_id] = {
                "id": ws_id,
                "name": str(w.get("name", ws_id)),
                "monitor": str(w.get("monitor", "")),
                "monitorID": w.get("monitorID", 0),
                "windowsCount": win_count,
                "isActive": (ws_id == active_id),
                "clients": []
            }

    # Add windows to their respective workspaces
    for c in clients:
        ws_info = c.get("workspace", {})
        ws_id = ws_info.get("id")
        if ws_id in ws_map:
            ws_map[ws_id]["clients"].append({
                "title": c.get("title", ""),
                "class": c.get("class", ""),
                "initialClass": c.get("initialClass", ""),
                "at": c.get("at", [0, 0]),
                "size": c.get("size", [100, 100]),
                "focusHistoryID": c.get("focusHistoryID", 0),
                "pinned": c.get("pinned", False),
                "floating": c.get("floating", False)
            })

    # Sort workspaces primarily by monitor, then by workspace id
    ws_list = list(ws_map.values())
    ws_list.sort(key=lambda x: (x["monitor"], x["id"]))

    mon_list = []
    for m in monitors:
        mon_list.append({
            "id": m.get("id", 0),
            "name": m.get("name", ""),
            "width": m.get("width", 1920),
            "height": m.get("height", 1080),
            "focused": m.get("focused", False)
        })

    output_payload = {
        "workspaces": ws_list,
        "activeWorkspaceId": active_id,
        "monitors": mon_list
    }
    print(json.dumps(output_payload))

if __name__ == "__main__":
    get_hyprland_workspaces()
