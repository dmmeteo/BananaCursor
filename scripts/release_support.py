import hashlib
import json
import os


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bundle_tree(bundle):
    return {
        str(path.relative_to(bundle)): ("link", os.readlink(path)) if path.is_symlink() else ("file", sha256(path))
        for path in bundle.rglob("*") if path.is_symlink() or path.is_file()
    }


def bundle_digest(bundle):
    return hashlib.sha256(json.dumps(bundle_tree(bundle), sort_keys=True).encode()).hexdigest()
