# M0 SPIKE — THROWAWAY. Pulls a few HaGRID 512px images per class via HTTP range requests.
# Usage: uv run fetch_sample.py [--classes palm,peace,fist,one] [--per-class 15] [--out ../../data/hagrid-sample]
import argparse, pathlib, random
from remotezip import RemoteZip

URL = "https://rndml-team-cv.obs.ru-moscow-1.hc.sbercloud.ru/datasets/hagrid_v2/hagridv2_512.zip"
ROOT = "HaGRIDv2_dataset_512"

p = argparse.ArgumentParser()
p.add_argument("--classes", default="palm,peace,fist,one")
p.add_argument("--per-class", type=int, default=15)
p.add_argument("--out", default=str(pathlib.Path(__file__).resolve().parents[2] / "data" / "hagrid-sample"))
args = p.parse_args()

rng = random.Random(42)
with RemoteZip(URL) as z:
    names = z.namelist()
    for cls in args.classes.split(","):
        members = sorted(n for n in names if n.startswith(f"{ROOT}/{cls}/") and n.lower().endswith(".jpg"))
        picked = rng.sample(members, min(args.per_class, len(members)))
        dest = pathlib.Path(args.out) / cls
        dest.mkdir(parents=True, exist_ok=True)
        for m in picked:
            (dest / pathlib.Path(m).name).write_bytes(z.read(m))
        print(f"{cls}: {len(picked)} images -> {dest}")
