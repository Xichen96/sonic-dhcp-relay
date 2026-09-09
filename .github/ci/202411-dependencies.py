import hashlib
import json
import pathlib
import sys
import urllib.parse
import urllib.request


ARCH_ARTIFACTS = {
    "amd64": (
        "sonic-buildimage.broadcom",
        "12F4D2A66FF4C29665A6981DEB066C64C081DE4A8A73BD67AE3671F0C0DAD65D02",
    ),
    "arm64": (
        "sonic-buildimage.marvell-arm64",
        "DAF324C79E0A0AE0072B027A943A3CB34B96F287A26645AD5976E5C6F55AD26E02",
    ),
    "armhf": (
        "sonic-buildimage.marvell-armhf",
        "32ACC6E382CF43260C77DB6846820D4C924E6104197953110FCA2B5EB102845502",
    ),
}
PACKAGES = {
    "libswsscommon": "1.0.0",
    "libswsscommon-dev": "1.0.0",
    "libyang": "1.0.73",
    "libyang-dev": "1.0.73",
    **{
        f"libnl-{family}-{kind}": "3.7.0-0.2+b1sonic1"
        for family in ("3", "genl-3", "nf-3", "route-3")
        for kind in ("200", "dev")
    },
}
BUILD_API = "https://dev.azure.com/mssonic/build/_apis/build/builds/1214622/artifacts"


def download(artifact, file_id, name):
    query = urllib.parse.urlencode({
        "artifactName": artifact,
        "fileId": file_id,
        "fileName": name,
        "api-version": "7.1",
    })
    with urllib.request.urlopen(f"{BUILD_API}?{query}", timeout=120) as response:
        return response.read()


arch, destination, evidence = sys.argv[1:]
artifact, manifest_id = ARCH_ARTIFACTS[arch]
manifest = json.loads(download(artifact, manifest_id, "manifest.json"))
entries = {item["path"]: item for item in manifest["items"]}
destination = pathlib.Path(destination)
destination.mkdir(parents=True, exist_ok=True)
receipt = {"build": 1214622, "artifact": artifact, "manifest": manifest_id, "files": []}

for package, version in PACKAGES.items():
    name = f"{package}_{version}_{arch}.deb"
    blob = entries[f"/target/debs/bookworm/{name}"]["blob"]
    content = download(artifact, blob["id"], name)
    if len(content) != blob["size"]:
        raise RuntimeError(f"Size mismatch for {name}: {len(content)} != {blob['size']}")
    (destination / name).write_bytes(content)
    receipt["files"].append({
        "name": name,
        "content_id": blob["id"],
        "size": len(content),
        "sha256": hashlib.sha256(content).hexdigest(),
    })
    print(f"Downloaded {name}: {len(content)} bytes", flush=True)

pathlib.Path(evidence).write_text(json.dumps(receipt, indent=2) + "\n")
