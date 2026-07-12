#!/usr/bin/env bash
#
# audit-public-access.sh
# ---------------------
# Scans Azure resource groups (from a JSON config) for resources with public
# access enabled, then lists associated NICs and private endpoints.
#
# Prerequisites:
#   - az cli installed and logged in (az login)
#   - jq installed
#
# Usage:
#   chmod +x audit-public-access.sh
#   ./audit-public-access.sh config.json
#   ./audit-public-access.sh config.json --output report.txt   # optional file output

set -euo pipefail

# ──────────────────────────────────────────────
# Usage
# ──────────────────────────────────────────────
usage() {
  printf 'Usage: %s <config.json> [--output <file>]\n\n' "$0"
  printf '  <config.json>    JSON file listing resource groups to audit\n'
  printf '  --output <file>  Write report to file (default: stdout)\n'
  exit 1
}

[[ $# -eq 0 || "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage

# ──────────────────────────────────────────────
# Argument parsing
# ──────────────────────────────────────────────
CONFIG_FILE="$1"
OUTPUT_FILE=""

if [[ "${2:-}" == "--output" ]]; then
  OUTPUT_FILE="${3:?--output requires a filename}"
fi

# ──────────────────────────────────────────────
# Dependency checks
# ──────────────────────────────────────────────
for cmd in az jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is required but not installed." >&2
    exit 1
  fi
done

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: Config file '$CONFIG_FILE' not found." >&2
  exit 1
fi

# Validate JSON structure
if ! jq -e '.resource_groups | length > 0' "$CONFIG_FILE" &>/dev/null; then
  echo "ERROR: Config file must contain a non-empty 'resource_groups' array." >&2
  exit 1
fi

# ──────────────────────────────────────────────
# Logging helper -- writes to stdout and optionally to a file
# ──────────────────────────────────────────────
log() {
  local msg="$*"
  echo -e "$msg"
  if [[ -n "$OUTPUT_FILE" ]]; then
    echo -e "$msg" >> "$OUTPUT_FILE"
  fi
}

SEPARATOR="============================================================================"
SUBSEP="----------------------------------------------------------------------------"

# Truncate output file if specified
[[ -n "$OUTPUT_FILE" ]] && : > "$OUTPUT_FILE"

log "$SEPARATOR"
log "  AZURE PUBLIC-ACCESS AUDIT REPORT"
log "  Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
log "$SEPARATOR"
log ""

# ──────────────────────────────────────────────
# Function: check if a resource is publicly accessible
#   Returns a short reason string, or empty if not public.
# ──────────────────────────────────────────────
check_public_access() {
  local resource_json="$1"

  # publicAccess == true  (Storage Blob containers, etc.)
  local pa
  pa=$(echo "$resource_json" | jq -r '.properties.publicAccess // empty' 2>/dev/null)
  if [[ "$pa" == "true" || "$pa" == "Blob" || "$pa" == "Container" ]]; then
    echo "publicAccess=$pa"
    return
  fi

  # publicNetworkAccess == Enabled  (SQL, Cosmos, Cognitive Services, etc.)
  local pna
  pna=$(echo "$resource_json" | jq -r '.properties.publicNetworkAccess // empty' 2>/dev/null)
  if [[ "${pna,,}" == "enabled" || "${pna,,}" == "true" ]]; then
    echo "publicNetworkAccess=$pna"
    return
  fi

  # networkRuleSet.defaultAction == Allow  (Service Bus, Event Hub, Key Vault, etc.)
  local nrs
  nrs=$(echo "$resource_json" | jq -r '.properties.networkRuleSet.defaultAction // empty' 2>/dev/null)
  if [[ "${nrs,,}" == "allow" ]]; then
    echo "networkRuleSet.defaultAction=Allow"
    return
  fi

  # networkAcls.defaultAction == Allow  (Storage Accounts, etc.)
  local na
  na=$(echo "$resource_json" | jq -r '.properties.networkAcls.defaultAction // empty' 2>/dev/null)
  if [[ "${na,,}" == "allow" ]]; then
    echo "networkAcls.defaultAction=Allow"
    return
  fi

  # Public IP on a NIC (Virtual Machines / Load Balancers)
  local has_public_ip
  has_public_ip=$(echo "$resource_json" | jq -r '
    [.properties.ipConfigurations[]? |
     select(.properties.publicIPAddress != null)] | length' 2>/dev/null)
  if [[ "$has_public_ip" -gt 0 ]] 2>/dev/null; then
    echo "publicIPAddress attached"
    return
  fi

  echo ""
}

# ──────────────────────────────────────────────
# Function: find NICs associated with a resource
# ──────────────────────────────────────────────
get_associated_nics() {
  local subscription_id="$1"
  local rg_name="$2"
  local resource_id="$3"

  az network nic list \
    --subscription "$subscription_id" \
    --resource-group "$rg_name" \
    --query "[?contains(to_string(properties), '${resource_id}')].{name:name, id:id, privateIp:ipConfigurations[0].privateIpAddress, publicIp:ipConfigurations[0].publicIpAddress.id}" \
    --output json 2>/dev/null || echo "[]"
}

# ──────────────────────────────────────────────
# Function: find private endpoints associated with a resource
# ──────────────────────────────────────────────
get_associated_private_endpoints() {
  local subscription_id="$1"
  local rg_name="$2"
  local resource_id="$3"

  az network private-endpoint list \
    --subscription "$subscription_id" \
    --resource-group "$rg_name" \
    --query "[?privateLinkServiceConnections[?privateLinkServiceId=='${resource_id}']].{name:name, id:id, subnet:subnet.id, fqdns:customDnsConfigs[].fqdn}" \
    --output json 2>/dev/null || echo "[]"
}

# ──────────────────────────────────────────────
# Main loop -- iterate over config entries
# ──────────────────────────────────────────────
TOTAL_PUBLIC=0
TOTAL_RESOURCES=0
RG_COUNT=$(jq '.resource_groups | length' "$CONFIG_FILE")

for (( i=0; i<RG_COUNT; i++ )); do
  RG_NAME=$(jq -r ".resource_groups[$i].name" "$CONFIG_FILE")
  SUB_ID=$(jq -r  ".resource_groups[$i].subscription_id" "$CONFIG_FILE")

  log "+$SUBSEP"
  log "| Resource Group : $RG_NAME"
  log "| Subscription   : $SUB_ID"
  log "+$SUBSEP"
  log ""

  # Set the active subscription
  if ! az account set --subscription "$SUB_ID" 2>/dev/null; then
    log "  [WARNING] Unable to set subscription '$SUB_ID'. Skipping."
    log ""
    continue
  fi

  # -- List ALL resources in the resource group (full detail) --
  RESOURCES_JSON=$(az resource list \
    --subscription "$SUB_ID" \
    --resource-group "$RG_NAME" \
    --output json 2>/dev/null || echo "[]")

  RESOURCE_COUNT=$(echo "$RESOURCES_JSON" | jq 'length')
  log "  Total resources in group: $RESOURCE_COUNT"
  log ""

  if [[ "$RESOURCE_COUNT" -eq 0 ]]; then
    log "  (no resources found)"
    log ""
    continue
  fi

  TOTAL_RESOURCES=$((TOTAL_RESOURCES + RESOURCE_COUNT))
  PUBLIC_IN_RG=0

  for (( j=0; j<RESOURCE_COUNT; j++ )); do
    RESOURCE_NAME=$(echo "$RESOURCES_JSON" | jq -r ".[$j].name")
    RESOURCE_TYPE=$(echo "$RESOURCES_JSON" | jq -r ".[$j].type")
    RESOURCE_ID=$(echo "$RESOURCES_JSON"   | jq -r ".[$j].id")

    # Get full resource detail (the list view may not include all properties)
    RESOURCE_DETAIL=$(az resource show \
      --ids "$RESOURCE_ID" \
      --output json 2>/dev/null || echo "{}")

    REASON=$(check_public_access "$RESOURCE_DETAIL")

    if [[ -z "$REASON" ]]; then
      continue
    fi

    PUBLIC_IN_RG=$((PUBLIC_IN_RG + 1))
    TOTAL_PUBLIC=$((TOTAL_PUBLIC + 1))

    log "  [PUBLIC] RESOURCE #${TOTAL_PUBLIC}"
    log "     Name : $RESOURCE_NAME"
    log "     Type : $RESOURCE_TYPE"
    log "     ID   : $RESOURCE_ID"
    log "     Why  : $REASON"
    log ""

    # -- Associated NICs --
    log "     [NICs] Associated Network Interfaces:"
    NICS_JSON=$(get_associated_nics "$SUB_ID" "$RG_NAME" "$RESOURCE_ID")
    NIC_COUNT=$(echo "$NICS_JSON" | jq 'length')

    if [[ "$NIC_COUNT" -eq 0 ]]; then
      log "        (none found in this resource group)"
    else
      for (( k=0; k<NIC_COUNT; k++ )); do
        NIC_NAME=$(echo "$NICS_JSON" | jq -r ".[$k].name")
        NIC_PRIV=$(echo "$NICS_JSON" | jq -r ".[$k].privateIp // \"n/a\"")
        NIC_PUB=$(echo  "$NICS_JSON" | jq -r ".[$k].publicIp  // \"none\"")
        log "        * $NIC_NAME  (private: $NIC_PRIV, publicIP ref: $NIC_PUB)"
      done
    fi
    log ""

    # -- Associated Private Endpoints --
    log "     [PE] Associated Private Endpoints:"
    PE_JSON=$(get_associated_private_endpoints "$SUB_ID" "$RG_NAME" "$RESOURCE_ID")
    PE_COUNT=$(echo "$PE_JSON" | jq 'length')

    if [[ "$PE_COUNT" -eq 0 ]]; then
      log "        (none -- resource has NO private endpoint)"
    else
      for (( k=0; k<PE_COUNT; k++ )); do
        PE_NAME=$(echo "$PE_JSON"  | jq -r ".[$k].name")
        PE_SUBNET=$(echo "$PE_JSON"| jq -r ".[$k].subnet // \"n/a\"")
        PE_FQDNS=$(echo "$PE_JSON" | jq -r ".[$k].fqdns // [] | join(\", \")")
        log "        * $PE_NAME"
        log "          Subnet : $PE_SUBNET"
        log "          FQDNs  : ${PE_FQDNS:-n/a}"
      done
    fi
    log ""
    log "     $SUBSEP"
    log ""
  done

  if [[ "$PUBLIC_IN_RG" -eq 0 ]]; then
    log "  [OK] No publicly accessible resources found in this group."
    log ""
  fi
done

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
log "$SEPARATOR"
log "  SUMMARY"
log "  Resource groups scanned : $RG_COUNT"
log "  Total resources scanned : $TOTAL_RESOURCES"
log "  Public resources found  : $TOTAL_PUBLIC"
log "$SEPARATOR"

if [[ -n "$OUTPUT_FILE" ]]; then
  echo ""
  echo "Report written to: $OUTPUT_FILE"
fi