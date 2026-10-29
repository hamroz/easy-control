"""Downloads the HaGRID subset: annotations (parsed in memory), then selected 512px images.

Usage: uv run fetch.py [--out ../../data/hagrid] [--workers 16]
Resumable: images already on disk are skipped.
"""
import argparse
import json
import pathlib
import struct
import urllib.request
import zlib
from concurrent.futures import ThreadPoolExecutor, as_completed

from remotezip import RemoteZip

from classes import NONE_SOURCES, POSITIVE_SOURCES, SPLIT_SIZES
from select_subset import check_disjoint, select

HOST = "https://rndml-team-cv.obs.ru-moscow-1.hc.sbercloud.ru/datasets/hagrid_v2"
ANNOTATIONS = f"{HOST}/annotations_with_landmarks/annotations.zip"
IMAGES = f"{HOST}/hagridv2_512.zip"
IMAGE_ROOT = "HaGRIDv2_dataset_512"


def build_manifest() -> list[dict]:
    manifest = []
    with RemoteZip(ANNOTATIONS) as z:
        names = set(z.namelist())
        for kind, sources in (("positive", POSITIVE_SOURCES), ("none", NONE_SOURCES)):
            for source in sources:
                for split, n in SPLIT_SIZES[kind].items():
                    name = f"annotations/{split}/{source}.json"
                    if name not in names:
                        print(f"  missing {name}, skipped")
                        continue
                    picked = select(json.loads(z.read(name)), source, split, n)
                    manifest += picked
                    print(f"  {split:5} {source:16} {len(picked)}")
    return manifest


def fetch_member(info, dest: pathlib.Path) -> int:
    """Reads one zip member with a single HTTP range request (local header + data)."""
    end = info.header_offset + 30 + len(info.filename.encode()) + 1024 + info.compress_size
    req = urllib.request.Request(IMAGES, headers={"Range": f"bytes={info.header_offset}-{end}"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        blob = resp.read()
    name_len, extra_len = struct.unpack("<HH", blob[26:30])
    start = 30 + name_len + extra_len
    data = blob[start:start + info.compress_size]
    if info.compress_type == 8:
        data = zlib.decompress(data, -15)
    elif info.compress_type != 0:
        raise ValueError(f"unsupported compression {info.compress_type}")
    dest.write_bytes(data)
    return len(data)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(pathlib.Path(__file__).resolve().parents[2] / "data" / "hagrid"))
    parser.add_argument("--workers", type=int, default=16)
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    print("Selecting from annotations…")
    manifest = build_manifest()
    check_disjoint(manifest)
    with open(out / "manifest.jsonl", "w") as f:
        for rec in manifest:
            f.write(json.dumps(rec) + "\n")
    print(f"manifest: {len(manifest)} images, {sum(len(r['boxes']) for r in manifest)} boxes")

    print("Reading image archive directory…")
    with RemoteZip(IMAGES) as z:
        infos = {i.filename: i for i in z.infolist()}
    todo = []
    for rec in manifest:
        dest = out / "images" / rec["source"] / f"{rec['image_id']}.jpg"
        if not dest.exists():
            info = infos.get(f"{IMAGE_ROOT}/{rec['source']}/{rec['image_id']}.jpg")
            if info is None:
                print(f"  not in archive: {rec['source']}/{rec['image_id']}")
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            todo.append((info, dest))
    print(f"downloading {len(todo)} images with {args.workers} workers…")

    total, failed = 0, 0
    with ThreadPoolExecutor(args.workers) as pool:
        futures = [pool.submit(fetch_member, info, dest) for info, dest in todo]
        for i, fut in enumerate(as_completed(futures), 1):
            try:
                total += fut.result()
            except Exception as e:  # noqa: BLE001 — keep going; rerun resumes
                failed += 1
                print(f"  failed: {e}")
            if i % 1000 == 0:
                print(f"  {i}/{len(todo)} ({total / 1e9:.2f} GB)")
    print(f"done: {len(todo) - failed} downloaded, {failed} failed, {total / 1e9:.2f} GB")


if __name__ == "__main__":
    main()
