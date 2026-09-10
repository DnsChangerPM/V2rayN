#!/usr/bin/env bash
# Downloads (and where necessary builds) every external binary the app ships.
#
#   Xray-core ....... official Win7 build + official modern build
#   V2Ray-core ...... official modern build + Win7 build compiled from source
#   tun2socks ....... official modern build + Win7 build compiled from source
#   Wintun .......... official driver DLL (supports Windows 7 - 11)
#   geoip/geosite ... Loyalsoldier rule databases
#
# The Win7 builds matter because Go 1.21 dropped Windows 7: cores built with
# modern Go refuse to start there. XTLS publishes a patched Go SDK
# (https://github.com/XTLS/go-win7) which we use for the projects that do not
# ship a Win7 binary themselves.
set -euo pipefail

OUT_DIR="${1:-dist/cores}"
XRAY_VERSION="${XRAY_VERSION:-latest}"
V2RAY_VERSION="${V2RAY_VERSION:-latest}"
TUN2SOCKS_VERSION="${TUN2SOCKS_VERSION:-latest}"
WINTUN_URL="${WINTUN_URL:-https://www.wintun.net/builds/wintun-0.14.1.zip}"
WINTUN_SHA256="${WINTUN_SHA256:-}"
GO_WIN7_TAG="${GO_WIN7_TAG:-patched-1.27.1}"
BUILD_WIN7="${BUILD_WIN7:-true}"

mkdir -p "$OUT_DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# --- helpers ----------------------------------------------------------------

resolve_tag() {
  local repo="$1" requested="$2"
  if [[ "$requested" == "latest" ]]; then
    gh api "repos/$repo/releases/latest" --jq .tag_name
  else
    echo "$requested"
  fi
}

download_asset() {
  local repo="$1" tag="$2" asset="$3" dest="$4"
  local url
  url="$(gh api "repos/$repo/releases/tags/$tag" \
    --jq "[.assets[] | select(.name == \"$asset\") | .browser_download_url] | first")"
  if [[ -z "$url" || "$url" == "null" ]]; then
    echo "::error::asset '$asset' not found in $repo $tag" >&2
    return 1
  fi
  log "downloading $asset ($tag)"
  curl -fsSL --retry 3 --retry-delay 2 -o "$dest" "$url"
}

setup_patched_go() {
  log "installing the Windows 7 patched Go SDK ($GO_WIN7_TAG)"
  local zip="$WORK/go-win7.zip"
  curl -fsSL --retry 3 -o "$zip" \
    "https://github.com/XTLS/go-win7/releases/download/$GO_WIN7_TAG/go-for-win7-linux-amd64.zip"
  rm -rf "${RUNNER_TEMP:-/tmp}/gosdk"
  mkdir -p "${RUNNER_TEMP:-/tmp}/gosdk"
  unzip -q "$zip" -d "${RUNNER_TEMP:-/tmp}/gosdk"
  if [[ -d "${RUNNER_TEMP:-/tmp}/gosdk/go" ]]; then
    export GOROOT="${RUNNER_TEMP:-/tmp}/gosdk/go"
  else
    export GOROOT="${RUNNER_TEMP:-/tmp}/gosdk"
  fi
  export PATH="$GOROOT/bin:$PATH"
  # Never let the toolchain download a different (unpatched) SDK.
  export GOTOOLCHAIN=local
  go version
}

build_win7() {
  # build_win7 <repo> <tag> <build-target> <output>
  local repo="$1" tag="$2" target="$3" output="$4"
  local dir="$WORK/$(basename "$repo")"
  log "building $(basename "$repo") $tag for Windows 7 (patched Go)"
  rm -rf "$dir"
  git clone --depth 1 --branch "$tag" "https://github.com/$repo.git" "$dir"
  (
    cd "$dir"
    export CGO_ENABLED=0 GOOS=windows GOARCH=amd64
    go build -trimpath -ldflags="-s -w -buildid=" -o "$output" "$target"
  )
}

is_pe() {
  local file="$1"
  [[ "$(head -c 2 "$file" | od -An -tx1 | tr -d ' \n')" == "4d5a" ]]
}

# --- Xray -------------------------------------------------------------------

XRAY_TAG="$(resolve_tag XTLS/Xray-core "$XRAY_VERSION")"
log "Xray-core: $XRAY_TAG"

download_asset XTLS/Xray-core "$XRAY_TAG" Xray-win7-64.zip "$WORK/xray-win7.zip"
download_asset XTLS/Xray-core "$XRAY_TAG" Xray-windows-64.zip "$WORK/xray.zip"

unzip -o -j "$WORK/xray-win7.zip" xray.exe -d "$WORK/x7" >/dev/null
unzip -o -j "$WORK/xray.zip" xray.exe -d "$WORK/xm" >/dev/null
mv "$WORK/x7/xray.exe" "$OUT_DIR/xray-win7.exe"
mv "$WORK/xm/xray.exe" "$OUT_DIR/xray.exe"

# --- V2Ray ------------------------------------------------------------------

V2RAY_TAG="$(resolve_tag v2fly/v2ray-core "$V2RAY_VERSION")"
log "V2Ray-core: $V2RAY_TAG"

download_asset v2fly/v2ray-core "$V2RAY_TAG" v2ray-windows-64.zip "$WORK/v2ray.zip"
unzip -o -j "$WORK/v2ray.zip" v2ray.exe -d "$WORK/vm" >/dev/null
mv "$WORK/vm/v2ray.exe" "$OUT_DIR/v2ray.exe"

if [[ "$BUILD_WIN7" == "true" ]]; then
  setup_patched_go
  build_win7 v2fly/v2ray-core "$V2RAY_TAG" ./main "$OUT_DIR/v2ray-win7.exe"
else
  log "BUILD_WIN7=false - reusing the modern v2ray binary"
  cp "$OUT_DIR/v2ray.exe" "$OUT_DIR/v2ray-win7.exe"
fi

# --- tun2socks --------------------------------------------------------------

T2S_TAG="$(resolve_tag xjasonlyu/tun2socks "$TUN2SOCKS_VERSION")"
log "tun2socks: $T2S_TAG"

download_asset xjasonlyu/tun2socks "$T2S_TAG" tun2socks-windows-amd64.zip "$WORK/t2s.zip"
unzip -o -j "$WORK/t2s.zip" 'tun2socks-windows-amd64.exe' -d "$WORK/tm" >/dev/null 2>&1 ||
  unzip -o -j "$WORK/t2s.zip" '*.exe' -d "$WORK/tm" >/dev/null
mv "$WORK/tm"/*.exe "$OUT_DIR/tun2socks.exe"

if [[ "$BUILD_WIN7" == "true" ]]; then
  setup_patched_go
  build_win7 xjasonlyu/tun2socks "$T2S_TAG" . "$OUT_DIR/tun2socks-win7.exe"
else
  cp "$OUT_DIR/tun2socks.exe" "$OUT_DIR/tun2socks-win7.exe"
fi

# --- Wintun driver ----------------------------------------------------------

log "downloading the Wintun driver"
curl -fsSL --retry 3 -o "$WORK/wintun.zip" "$WINTUN_URL"
if [[ -n "$WINTUN_SHA256" ]]; then
  echo "$WINTUN_SHA256  $WORK/wintun.zip" | sha256sum -c -
fi
# The archive contains amd64/wintun.dll, x86/wintun.dll, arm/wintun.dll, ...
unzip -o "$WORK/wintun.zip" 'amd64/wintun.dll' -d "$WORK/wt" >/dev/null
mv "$WORK/wt/amd64/wintun.dll" "$OUT_DIR/wintun.dll"

# --- routing databases ------------------------------------------------------

log "downloading the routing databases (geoip.dat / geosite.dat)"
download_asset Loyalsoldier/v2ray-rules-dat latest geoip.dat "$OUT_DIR/geoip.dat"
download_asset Loyalsoldier/v2ray-rules-dat latest geosite.dat "$OUT_DIR/geosite.dat"

# --- sanity checks ----------------------------------------------------------

log "verifying the binaries"
for binary in xray.exe xray-win7.exe v2ray.exe v2ray-win7.exe tun2socks.exe tun2socks-win7.exe wintun.dll; do
  path="$OUT_DIR/$binary"
  if [[ ! -f "$path" ]]; then
    echo "::error::missing $binary" >&2
    exit 1
  fi
  if [[ "$binary" != *.dll ]] && ! is_pe "$path"; then
    echo "::error::$binary is not a Windows executable" >&2
    exit 1
  fi
  printf '  %-22s %8s bytes\n' "$binary" "$(stat -c %s "$path")"
done

echo "XRAY_VERSION=$XRAY_TAG" > "$OUT_DIR/versions.env"
echo "V2RAY_VERSION=$V2RAY_TAG" >> "$OUT_DIR/versions.env"
echo "TUN2SOCKS_VERSION=$T2S_TAG" >> "$OUT_DIR/versions.env"

log "cores ready in $OUT_DIR"
