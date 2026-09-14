# Path to kivy-ios's libcrypto.xcframework. Override by exporting
# LIBCRYPTO_XCFRAMEWORK before running this script if the auto-find
# below picks the wrong one (e.g. multiple kivy-ios checkouts).
LIBCRYPTO_XCFRAMEWORK="${LIBCRYPTO_XCFRAMEWORK:-$(find "." -maxdepth 6 -name 'libcrypto.xcframework' -print -quit)}"

# Patches a single *thin* (single-architecture) ar archive in place.
# Prints "<patched>:<found>" (each 0/1) so the caller can aggregate
# results across architecture slices of a fat archive.
patch_one_thin_archive() {
  local archive="$1"
  local target_symbol="$2"
  local new_symbol="$3"
  local slice_patched=0
  local slice_found=0

  # Inspect each object individually rather than parsing nm's grouped
  # multi-object archive listing — that grouping format (e.g.
  # "libcrypto.a(armcap.o):") differs between BSD (Apple) and GNU
  # ar/nm and is too fragile to parse reliably.
  while IFS= read -r obj; do
    [[ -n "$obj" ]] || continue
    ar -p "$archive" "$obj" > "$obj" 2>/dev/null || continue
    [[ -s "$obj" ]] || continue

    if nm "$obj" 2>/dev/null | grep -qE "[[:space:]]${new_symbol}\$"; then
      slice_found=1
      continue  # this object was already patched in a previous run
    fi

    if nm "$obj" 2>/dev/null | grep -qE "[[:space:]]${target_symbol}\$"; then
      slice_found=1
      xcrun llvm-objcopy --redefine-sym "${target_symbol}=${new_symbol}" "$obj"
      ar -r "$archive" "$obj"
      slice_patched=1
    fi
  done < <(ar -t "$archive")

  echo "${slice_patched}:${slice_found}"
}

# Symbol collides with the copy of OpenSSL/BoringSSL bundled by
# Firebase's gRPC dependency (via SPM). Renaming it inside kivy-ios's
# static libcrypto avoids the "duplicate symbol '_OPENSSL_armcap_P'"
# linker error, while keeping Python's ssl module (used by Kivy's
# UrlRequest) working normally.
patch_armcap_symbol() {
  local xcframework="$1"
  local target_symbol="_OPENSSL_armcap_P"
  local new_symbol="_kivyssl_OPENSSL_armcap_P"

  if [[ -z "$xcframework" || ! -d "$xcframework" ]]; then
    echo "⚠️  libcrypto.xcframework not found — skipping OpenSSL symbol patch."
    echo "    Set LIBCRYPTO_XCFRAMEWORK explicitly if this path is wrong."
    return 0
  fi

  echo "🔧 Checking OpenSSL symbol collision in: $xcframework"

  local patched_any=0

  while IFS= read -r -d '' archive; do
    # Resolve to an absolute path *before* changing directories below —
    # otherwise a relative $archive breaks as soon as we pushd.
    archive="$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")"

    local workdir
    workdir="$(mktemp -d)"
    pushd "$workdir" > /dev/null

    local slice_patched=0
    local slice_found=0

    # Fast path: the symbol name is a plain ASCII string inside the
    # binary regardless of fat-file wrapping, so grep can check for it
    # directly without lipo/ar/nm — skips the expensive per-object
    # extraction entirely when there's nothing to do.
    if grep -a -q -- "$new_symbol" "$archive"; then
      slice_found=1
      popd > /dev/null
      rm -rf "$workdir"
      echo "  ✓ $(basename "$(dirname "$archive")") already patched"
      continue
    fi

    if ! grep -a -q -- "$target_symbol" "$archive"; then
      popd > /dev/null
      rm -rf "$workdir"
      continue
    fi

    if lipo -info "$archive" 2>/dev/null | grep -q '^Architectures in the fat file'; then
      # kivy-ios ships fat static libs (multiple archs lipo'd into one
      # .a), which plain ar/nm can't read directly. Split into thin
      # per-arch archives, patch each independently, then reassemble.
      local archs
      archs=$(lipo -archs "$archive")
      local thin_paths=()

      for arch in $archs; do
        local thin="thin-${arch}.a"
        lipo -thin "$arch" "$archive" -output "$thin"

        local result patched found
        result=$(patch_one_thin_archive "$thin" "$target_symbol" "$new_symbol")
        patched="${result%%:*}"
        found="${result##*:}"
        [[ "$patched" -eq 1 ]] && slice_patched=1
        [[ "$found" -eq 1 ]] && slice_found=1

        thin_paths+=("$thin")
      done

      if [[ "$slice_patched" -eq 1 ]]; then
        lipo -create "${thin_paths[@]}" -output "${archive}.patched"
        mv "${archive}.patched" "$archive"
      fi
    else
      local result patched found
      result=$(patch_one_thin_archive "$archive" "$target_symbol" "$new_symbol")
      patched="${result%%:*}"
      found="${result##*:}"
      [[ "$patched" -eq 1 ]] && slice_patched=1
      [[ "$found" -eq 1 ]] && slice_found=1
    fi

    popd > /dev/null
    rm -rf "$workdir"

    if [[ "$slice_patched" -eq 1 ]]; then
      echo "  → Patched $(basename "$(dirname "$archive")")/$(basename "$archive")"
      patched_any=1
    elif [[ "$slice_found" -eq 1 ]]; then
      echo "  ✓ $(basename "$(dirname "$archive")") already patched"
    fi
  done < <(find "$xcframework" -name '*.a' -print0)

  if [[ "$patched_any" -eq 1 ]]; then
    echo "✅ OpenSSL symbol patch applied."
  else
    echo "  (nothing to patch — either already clean or already patched)"
  fi
}

patch_armcap_symbol "$LIBCRYPTO_XCFRAMEWORK"