I reviewed [img-to-text.sh](https://onedrive.live.com?cid=576E26223C2D9485\&id=576E26223C2D9485!s6ee6d5b417bd404ebe86901277f730f5\&EntityRepresentationId=e99cdf9d-9c9b-46ce-b50d-702f5f62d5b1). The script’s intended flow is clear: load config, parse args, show banner, optionally prompt for files, choose backend, health-check the Jetson OCR service, then process each file through either Jetson or local Tesseract. The failure you describe — “after the OCR detection passes” — sounds most likely to happen **after the Jetson `/health` check succeeds**, inside the per-file loop or JSON parsing/output section. [\[onedrive.live.com\]](https://onedrive.live.com?cid=576E26223C2D9485&id=576E26223C2D9485!s6ee6d5b417bd404ebe86901277f730f5)

Below are the logging points I would add first.

## 1. Add a debug logger near your print helpers

Put this near the existing `print_ok`, `print_fail`, `print_info`, `print_warn` helpers.

```bash
DEBUG="${DEBUG:-0}"
LOG_FILE="${LOG_FILE:-}"

log_debug() {
  [[ "$DEBUG" == "1" ]] || return 0
  local msg="[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $*"
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s\n' "$msg" >> "$LOG_FILE"
  else
    printf '%s\n' "$msg" >&2
  fi
}

log_error() {
  local msg="[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*"
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s\n' "$msg" >> "$LOG_FILE"
  else
    printf '%s\n' "$msg" >&2
  fi
}
```

Then run the script like this:

```bash
DEBUG=1 LOG_FILE=/tmp/img-to-text.log ./img-to-text.sh myfile.png --backend jetson
```

Or without a file:

```bash
DEBUG=1 ./img-to-text.sh myfile.png --backend jetson
```

## 2. Add an error trap

Because the script uses `set -uo pipefail`, failures can still be hard to locate, especially if a variable is unset or a pipeline behaves unexpectedly. Add this near the top after `set -uo pipefail`.

```bash
trap 'rc=$?; log_error "Failed at line $LINENO with exit code $rc. Command: $BASH_COMMAND"; exit $rc' ERR
```

If you temporarily want stricter debugging, you can also test with:

```bash
set -Eeuo pipefail
```

I would only add `-e` while debugging if the script does not already rely on commands failing harmlessly. Your script currently avoids `-e`, so enabling it may change behavior.

## 3. Log config and final runtime values

Your script loads config from `~/.config/scripts-hub/config`, then applies defaults, then CLI args. The file documents `OCR_BACKEND`, `JETSON_OCR_URL`, and `OCR_LANG` as env/config values. [\[onedrive.live.com\]](https://onedrive.live.com?cid=576E26223C2D9485&id=576E26223C2D9485!s6ee6d5b417bd404ebe86901277f730f5)

Right after argument parsing, before `banner`, add:

```bash
log_debug "Runtime config:"
log_debug "  OCR_BACKEND=${OCR_BACKEND:-<unset>}"
log_debug "  JETSON_OCR_URL=${JETSON_OCR_URL:-<unset>}"
log_debug "  OCR_LANG=${OCR_LANG:-<unset>}"
log_debug "  OUTPUT_DIR=${OUTPUT_DIR:-<unset>}"
log_debug "  FILES count=${#FILES[@]}"
printf '%s\n' "${FILES[@]}" | while read -r _dbg_file; do
  log_debug "  FILE=${_dbg_file}"
done
```

This will quickly confirm whether the backend, URL, language, output directory, and file list are what you think they are.

## 4. Log before and after Jetson health detection

In `run_jetson`, add logging around the health check. Your script checks `JETSON_OCR_URL`, strips the trailing slash, prints that it is trying the Jetson service, and then attempts a health request before falling back to local Tesseract if unreachable. [\[onedrive.live.com\]](https://onedrive.live.com?cid=576E26223C2D9485&id=576E26223C2D9485!s6ee6d5b417bd404ebe86901277f730f5)

Add:

```bash
log_debug "Entering run_jetson"
log_debug "JETSON_OCR_URL before strip=${JETSON_OCR_URL:-<unset>}"

JETSON_OCR_URL="${JETSON_OCR_URL%/}"

log_debug "JETSON_OCR_URL after strip=$JETSON_OCR_URL"
log_debug "Health URL=$JETSON_OCR_URL/health"
```

Then immediately after the health response is captured:

```bash
log_debug "Health response raw: $health"
```

And after parsing Tesseract/TensorRT:

```bash
log_debug "Parsed health: tess_ver=${tess_ver:-<unset>} trt=${trt:-<unset>}"
```

This tells you whether the “OCR detection passes” point is really the service health check, and whether the JSON returned from `/health` is what your Python parser expects.

## 5. Log the per-file loop before anything dangerous happens

Inside the Jetson loop, add logging at the very top:

```bash
for f in "${FILES[@]}"; do
  log_debug "Processing file: $f"

  if [[ ! -f "$f" ]]; then
    log_error "File not found: $f"
    print_fail "Not found: $f"
    ((fail+=1))
    continue
  fi

  log_debug "File exists"
  log_debug "File size bytes=$(wc -c < "$f" 2>/dev/null || printf 'unknown')"
```

This helps confirm whether the script is dying because of a path issue, spaces in filenames, permissions, or an unexpected file type.

## 6. Log video/image detection

Your script has an `is_video()` helper that detects extensions like `mp4`, `avi`, `mov`, `mkv`, `ts`, and `m4v`. [\[onedrive.live.com\]](https://onedrive.live.com?cid=576E26223C2D9485&id=576E26223C2D9485!s6ee6d5b417bd404ebe86901277f730f5)

Right before choosing the endpoint, add:

```bash
if is_video "$f"; then
  log_debug "Detected input type: video"
  endpoint="$JETSON_OCR_URL/ocr/video"
else
  log_debug "Detected input type: image"
  endpoint="$JETSON_OCR_URL/ocr"
fi

log_debug "Selected endpoint=$endpoint"
```

If your failure is “after OCR detection passes,” this is one of the most important places to log. It confirms whether the script chose the video endpoint or image endpoint.

## 7. Log output filename construction

Based on the fetched script content, the area around `base`, `out`, and `endpoint` is especially suspicious. The script is supposed to derive a base filename and write a `.txt` output, but the fetched content around that area appears malformed/truncated. [\[onedrive.live.com\]](https://onedrive.live.com?cid=576E26223C2D9485&id=576E26223C2D9485!s6ee6d5b417bd404ebe86901277f730f5)

I would explicitly add:

```bash
base="$(basename "${f%.*}")"
out="$OUTPUT_DIR/${base}.txt"

log_debug "base=$base"
log_debug "out=$out"
log_debug "OUTPUT_DIR exists? $( [[ -d "$OUTPUT_DIR" ]] && echo yes || echo no )"
```

This catches a common failure point: output path not being what you expect.

## 8. Log the actual curl POST, status, and response length

This is probably the most useful block. Instead of only capturing the response body, capture HTTP status too.

Replace your Jetson POST call with a debug-friendly version like this:

```bash
tmp_response="$(mktemp)"
log_debug "Posting file to Jetson OCR"
log_debug "curl endpoint=$endpoint"
log_debug "curl file=$f"

http_code="$(
  curl -sS \
    -o "$tmp_response" \
    -w '%{http_code}' \
    -X POST \
    -F "file=@${f}" \
    "$endpoint"
)"
curl_rc=$?

log_debug "curl exit code=$curl_rc"
log_debug "HTTP status=$http_code"
log_debug "Response bytes=$(wc -c < "$tmp_response" 2>/dev/null || printf 'unknown')"

if [[ "$curl_rc" -ne 0 || "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
  log_error "Jetson OCR request failed: curl_rc=$curl_rc http_code=$http_code"
  log_error "Response body:"
  sed 's/^/[OCR RESPONSE] /' "$tmp_response" >&2
  ((fail+=1))
  rm -f "$tmp_response"
  continue
fi

response="$(cat "$tmp_response")"
rm -f "$tmp_response"
```

This will tell you whether the Jetson service is returning a non-200 response, malformed JSON, or an error body that your Python parser later chokes on.

## 9. Validate JSON before handing it to the parser

Your script pipes the Jetson response into Python and expects JSON fields like `text`, `summary`, `frames`, `timestamp_sec`, and `frame`. [\[onedrive.live.com\]](https://onedrive.live.com?cid=576E26223C2D9485&id=576E26223C2D9485!s6ee6d5b417bd404ebe86901277f730f5)

Before the existing Python output writer, add:

```bash
log_debug "Validating JSON response"

if ! printf '%s' "$response" | python3 -m json.tool >/dev/null 2>&1; then
  log_error "Response is not valid JSON"
  printf '%s\n' "$response" | sed 's/^/[BAD JSON] /' >&2
  ((fail+=1))
  continue
fi

log_debug "JSON response is valid"
```

If the service returns HTML, plaintext, a traceback, or an empty response, this catches it before your output writer explodes.

## 10. Log which parser branch is used

Right before the video/image Python writer blocks:

```bash
if is_video "$f"; then
  log_debug "Writing video OCR output to $out"
  # existing video parser
else
  log_debug "Writing image OCR output to $out"
  # existing image parser
fi

parser_rc=$?
log_debug "Python parser exit code=$parser_rc"

if [[ "$parser_rc" -ne 0 ]]; then
  log_error "Python parser failed for $f"
  ((fail+=1))
  continue
fi
```

If the crash is after OCR detection and after the POST succeeds, the next likely culprit is the Python JSON parsing/writing section.

## 11. Add local backend logging too

Your local backend checks for `tesseract`, prints the version/language, creates the output directory, and loops through files. [\[onedrive.live.com\]](https://onedrive.live.com?cid=576E26223C2D9485&id=576E26223C2D9485!s6ee6d5b417bd404ebe86901277f730f5)

Inside `run_local`, add:

```bash
log_debug "Entering run_local"
log_debug "OCR_LANG=${OCR_LANG:-<unset>}"
log_debug "OUTPUT_DIR=$OUTPUT_DIR"
log_debug "FILES count=${#FILES[@]}"
```

Inside the local loop:

```bash
log_debug "Local OCR processing file=$f"

if [[ ! -f "$f" ]]; then
  log_error "File not found: $f"
  print_fail "Not found: $f"
  ((fail+=1))
  continue
fi

base="$(basename "${f%.*}")"
out="$OUTPUT_DIR/${base}.txt"

log_debug "Local OCR output=$out"

tesseract "$f" "${out%.txt}" -l "$OCR_LANG"
tess_rc=$?

log_debug "tesseract exit code=$tess_rc"

if [[ "$tess_rc" -ne 0 ]]; then
  log_error "tesseract failed for $f"
  ((fail+=1))
  continue
fi
```

## Suspicious areas I would inspect closely

From the uploaded [img-to-text.sh](https://onedrive.live.com?cid=576E26223C2D9485\&id=576E26223C2D9485!s6ee6d5b417bd404ebe86901277f730f5\&EntityRepresentationId=e99cdf9d-9c9b-46ce-b50d-702f5f62d5b1), these are the parts I would verify first:

1. **Config path**

   The fetched content shows the config path area as `~/.config/scripts-hub/config` in comments, but the script body appears malformed in the retrieved rendering around `_CFG`. Verify your local file really uses:

   ```bash
   _CFG="$HOME/.config/scripts-hub/config"
   ```

2. **Defaults**

   Verify these are not empty placeholders:

   ```bash
   OCR_BACKEND="${OCR_BACKEND:-local}"
   JETSON_OCR_URL="${JETSON_OCR_URL:-http://10.0.100.30:8000}"
   OCR_LANG="${OCR_LANG:-eng}"
   ```

3. **Health check**

   Make sure it looks like this:

   ```bash
   health="$(curl -fsS "$JETSON_OCR_URL/health" 2>/dev/null)"
   ```

4. **Output path construction**

   Around the Jetson loop, make sure it has a real output path:

   ```bash
   base="$(basename "${f%.*}")"
   out="$OUTPUT_DIR/${base}.txt"
   ```

5. **POST endpoint**

   Make sure image and video endpoints are explicitly assigned and logged:

   ```bash
   if is_video "$f"; then
     endpoint="$JETSON_OCR_URL/ocr/video"
   else
     endpoint="$JETSON_OCR_URL/ocr"
   fi
   ```

6. **Python JSON parsing**

   Add JSON validation before the Python writer. If the Jetson service returns an error response, the Python parser is where it will likely blow up.

## Minimal debug patch I would add first

If you only want the fastest useful logging, add this:

```bash
DEBUG="${DEBUG:-0}"
log_debug() {
  [[ "$DEBUG" == "1" ]] || return 0
  printf '[DEBUG] %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}
log_error() {
  printf '[ERROR] %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}
trap 'rc=$?; log_error "Failed at line $LINENO with exit code $rc. Command: $BASH_COMMAND"; exit $rc' ERR
```

Then in `run_jetson`:

```bash
log_debug "Entering run_jetson"
log_debug "JETSON_OCR_URL=$JETSON_OCR_URL"
log_debug "OUTPUT_DIR=$OUTPUT_DIR"
log_debug "FILES count=${#FILES[@]}"

health="$(curl -fsS "$JETSON_OCR_URL/health" 2>/dev/null)" || {
  log_error "Health check failed for $JETSON_OCR_URL/health"
  print_warn "Jetson OCR not reachable at $JETSON_OCR_URL"
  run_local
  return
}

log_debug "Health response: $health"
```

And inside the Jetson file loop:

```bash
log_debug "Processing file=$f"

base="$(basename "${f%.*}")"
out="$OUTPUT_DIR/${base}.txt"

if is_video "$f"; then
  endpoint="$JETSON_OCR_URL/ocr/video"
  log_debug "Detected video; endpoint=$endpoint"
else
  endpoint="$JETSON_OCR_URL/ocr"
  log_debug "Detected image; endpoint=$endpoint"
fi

tmp_response="$(mktemp)"
http_code="$(
  curl -sS -o "$tmp_response" -w '%{http_code}' \
    -X POST -F "file=@${f}" "$endpoint"
)"
curl_rc=$?

log_debug "curl_rc=$curl_rc http_code=$http_code response_bytes=$(wc -c < "$tmp_response")"

if [[ "$curl_rc" -ne 0 || "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
  log_error "OCR request failed for $f"
  sed 's/^/[OCR RESPONSE] /' "$tmp_response" >&2
  rm -f "$tmp_response"
  ((fail+=1))
  continue
fi

response="$(cat "$tmp_response")"
rm -f "$tmp_response"

if ! printf '%s' "$response" | python3 -m json.tool >/dev/null 2>&1; then
  log_error "OCR response was not valid JSON for $f"
  printf '%s\n' "$response" | sed 's/^/[BAD JSON] /' >&2
  ((fail+=1))
  continue
fi

log_debug "OCR response JSON valid; writing output=$out"
```

That should show exactly whether it dies on **endpoint selection**, **curl upload**, **HTTP response**, **JSON validity**, or **Python output writing**.
