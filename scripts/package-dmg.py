#!/usr/bin/env python3
from pathlib import Path

import dmgbuild
from ds_store import DSStore
from mac_alias import Alias


def build_dmg(bundle: Path, destination: Path):
    mount = None

    def remember_mount(path, _options):
        nonlocal mount
        mount = Path(path)

    def callback(info):
        if info.get("type") == "operation::finished" and info.get("operation") == "dsstore::create":
            background = mount / "BananaCursor.app/Contents/Resources/installer-background.tiff"
            with DSStore.open(str(mount / ".DS_Store"), "r+") as store:
                view = store["."]["icvp"]
                view["backgroundType"] = 2
                view["backgroundImageAlias"] = Alias.for_file(str(background)).to_bytes()
                store["."]["icvp"] = view

    settings = {
        "format": "UDZO", "compression_level": 9, "filesystem": "HFS+",
        "files": [(str(bundle), "BananaCursor.app")], "symlinks": {"Applications": "/Applications"},
        "background": None, "icon": None,
        "icon_locations": {"BananaCursor.app": (160, 145), "Applications": (480, 145)},
        "window_rect": ((160, 140), (640, 400)), "icon_size": 96, "text_size": 14,
        "default_view": "icon-view", "arrange_by": None, "grid_offset": (0, 0),
        "show_icon_preview": False, "include_icon_view_settings": True,
        "include_list_view_settings": False, "show_status_bar": False,
        "show_tab_view": False, "show_toolbar": False, "show_pathbar": False, "show_sidebar": False,
        "create_hook": remember_mount,
    }
    dmgbuild.build_dmg(str(destination), "BananaCursor", settings=settings, callback=callback)
