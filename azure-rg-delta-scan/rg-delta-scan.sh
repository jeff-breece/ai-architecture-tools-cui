#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# rg-delta-scan.sh
# Purpose : Inventory + delta analysis across a set of Azure Resource Groups
# Author  : Jeff Breece / Marzetti Platform Engineering
# Notes   : Read-only. Focus on network resources (NIC/PEP/PDNS/VNET/NSG/RT/PIP).
#           Extend by adding a Subscription column and looping az account set.
# =============================================================================

usage() {
  cat <<EOF
Usage: $0 -f <rg_list.csv> [-o <output_dir>] [-s <subscription>]

  -f  Path to CSV file listing RG names (one per line; header optional)
  -o  Output directory (default: ./rg-scan-<timestamp>)
  -s  Subscription ID or name (optional; uses current context if omitted)
  -h  Show this help
EOF
  exit 1
}

INPUT_CSV=""
OUTPUT_DIR=""
SUBSCRIPTION=""
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

while getopts "f:o:s:h" opt; do
  case "$opt" in
    f) INPUT_CSV="$OPTARG" ;;
    o) OUTPUT_DIR="$OPTARG" ;;
    s) SUBSCRIPTION="$OPTARG" ;;
    h|*) usage ;;
  esac
done

[[ -z "$INPUT_CSV" ]] && usage
[[ ! -f "$INPUT_CSV" ]] && { echo "ERROR: input file not found: $INPUT_CSV" >&2; exit 2; }

OUTPUT_DIR="${OUTPUT_DIR:-./rg-scan-${TIMESTAMP}}"
mkdir -p "$OUTPUT_DIR"

LOG_FILE="$OUTPUT_DIR/scan.log"
INVENTORY_CSV="$OUTPUT_DIR/inventory.csv"
MATRIX_CSV="$OUTPUT_DIR/inventory_matrix.csv"
NETWORK_CSV="$OUTPUT_DIR/network_details.csv"
SUMMARY_TXT="$OUTPUT_DIR/summary.txt"

log() {
  local msg="[$(date +'%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" | tee -a "$LOG_FILE" >/dev/null
  echo "$msg"
}

log "=== RG Delta Scan started ==="
log "Input CSV  : $INPUT_CSV"
log "Output dir : $OUTPUT_DIR"

# -------- Preflight --------
command -v az >/dev/null 2>&1 || { log "ERROR: az CLI not found"; exit 3; }
command -v jq >/dev/null 2>&1 || { log "ERROR: jq not found";      exit 3; }

if [[ -n "$SUBSCRIPTION" ]]; then
  az account set --subscription "$SUBSCRIPTION"
fi
CURRENT_SUB=$(az account show --query "{name:name,id:id}" -o json)
log "Subscription: $(echo "$CURRENT_SUB" | jq -r '.name + " (" + .id + ")"')"

# -------- Parse RG list (skip header row, blank lines, CR, whitespace) --------
mapfile -t RG_LIST < <(
  sed 's/\r//g' "$INPUT_CSV" \
  | awk -F',' 'NF>0 {
      gsub(/^[ \t]+|[ \t]+$/, "", $1);
      lc=tolower($1);
      if ($1 != "" && lc != "resourcegroup" && lc != "resource_group" && lc != "name" && lc != "rg")
        print $1
    }'
)

if [[ ${#RG_LIST[@]} -eq 0 ]]; then
  log "ERROR: no resource groups found in input CSV"
  exit 4
fi
log "Resource groups to scan: ${#RG_LIST[@]}"

# -------- CSV headers --------
echo "ResourceGroup,ResourceType,ResourceName,Location,Category,Id" > "$INVENTORY_CSV"

# Network CSV: generic Detail columns; semantics vary by ResourceType (see legend)
echo "ResourceGroup,Category,ResourceType,ResourceName,Detail1,Detail2,Detail3,Detail4" > "$NETWORK_CSV"
cat >> "$LOG_FILE" <<'LEGEND'

network_details.csv column legend:
  NIC            : Detail1=SubnetId, Detail2=PrivateIP,     Detail3=AttachedResourceId, Detail4=NsgId
  PrivateEndpoint: Detail1=SubnetId, Detail2=TargetPlsId,   Detail3=GroupIds,           Detail4=Fqdn(first)
  PrivateDnsZone : Detail1=RecordSets, Detail2=VNetLinks,   Detail3=,                   Detail4=
  VNet           : Detail1=AddrSpace, Detail2=Subnets,      Detail3=CustomDNS,          Detail4=
  NSG            : Detail1=RuleCount, Detail2=SubnetCount,  Detail3=NicCount,           Detail4=
  RouteTable     : Detail1=RouteCount,Detail2=SubnetCount,  Detail3=,                   Detail4=
  PublicIP       : Detail1=IPAddress, Detail2=AllocMethod,  Detail3=SkuName,            Detail4=

LEGEND

# -------- Categorization helper --------
classify() {
  local rt="$1"
  case "$rt" in
    Microsoft.Network/*)                            echo "Network" ;;
    Microsoft.Compute/*)                            echo "Compute" ;;
    Microsoft.Storage/*)                            echo "Storage" ;;
    Microsoft.KeyVault/*)                           echo "Security" ;;
    Microsoft.Web/*|Microsoft.Logic/*)              echo "AppPlatform" ;;
    Microsoft.Sql/*|Microsoft.DBfor*|\
    Microsoft.DocumentDB/*|Microsoft.Synapse/*|\
    Microsoft.DataFactory/*|Microsoft.Databricks/*|\
    Microsoft.Kusto/*)                              echo "Data" ;;
    Microsoft.Insights/*|Microsoft.OperationalInsights/*|\
    Microsoft.AlertsManagement/*)                   echo "Observability" ;;
    Microsoft.ManagedIdentity/*)                    echo "Identity" ;;
    *)                                              echo "Other" ;;
  esac
}

PIVOT_TMP=$(mktemp)
trap 'rm -f "$PIVOT_TMP"' EXIT

# =============================================================================
# Main scan loop
# =============================================================================
for RG in "${RG_LIST[@]}"; do
  log "--- Scanning RG: $RG ---"

  if ! az group show --name "$RG" -o none 2>/dev/null; then
    log "WARN: RG not found or no access: $RG"
    continue
  fi

  # ---------- Full inventory ----------
  RESOURCES_JSON=$(az resource list --resource-group "$RG" -o json)
  COUNT=$(echo "$RESOURCES_JSON" | jq 'length')
  log "  Resources found: $COUNT"

  # Use process substitution so the loop runs in the current shell
  while IFS=$'\t' read -r TYPE NAME LOC ID; do
    CAT=$(classify "$TYPE")
    printf '%s,"%s","%s","%s","%s","%s"\n' \
      "$RG" "$TYPE" "$NAME" "$LOC" "$CAT" "$ID" >> "$INVENTORY_CSV"
    echo "${RG}|${TYPE}" >> "$PIVOT_TMP"
  done < <(echo "$RESOURCES_JSON" | jq -r '.[] | [.type, .name, (.location // ""), .id] | @tsv')

  # ---------- Network deep dive ----------
  log "  Deep-diving network resources..."

  # NICs
  az network nic list -g "$RG" -o json 2>/dev/null \
    | jq -r --arg RG "$RG" '
        .[] | [$RG, "Network", "NIC", .name,
               ((.ipConfigurations // [])[0].subnet.id // ""),
               ((.ipConfigurations // [])[0].privateIPAddress // ""),
               (.virtualMachine.id // .privateEndpoint.id // ""),
               (.networkSecurityGroup.id // "")] | @csv' >> "$NETWORK_CSV" || true

  # Private Endpoints
  az network private-endpoint list -g "$RG" -o json 2>/dev/null \
    | jq -r --arg RG "$RG" '
        .[] | [$RG, "Network", "PrivateEndpoint", .name,
               (.subnet.id // ""),
               (((.privateLinkServiceConnections // [])[0].privateLinkServiceId)
                 // ((.manualPrivateLinkServiceConnections // [])[0].privateLinkServiceId) // ""),
               (((.privateLinkServiceConnections // [])[0].groupIds // []) | join(";")),
               (((.customDnsConfigs // [])[0].fqdn) // "")] | @csv' >> "$NETWORK_CSV" || true

  # Private DNS Zones
  az network private-dns zone list -g "$RG" -o json 2>/dev/null \
    | jq -r --arg RG "$RG" '
        .[] | [$RG, "Network", "PrivateDnsZone", .name,
               (.numberOfRecordSets|tostring),
               (.numberOfVirtualNetworkLinks|tostring),
               "", ""] | @csv' >> "$NETWORK_CSV" || true

  # VNets
  az network vnet list -g "$RG" -o json 2>/dev/null \
    | jq -r --arg RG "$RG" '
        .[] | [$RG, "Network", "VNet", .name,
               ((.addressSpace.addressPrefixes // []) | join(";")),
               (((.subnets // []) | map(.name)) | join(";")),
               ((.dhcpOptions.dnsServers // []) | join(";")),
               ""] | @csv' >> "$NETWORK_CSV" || true

  # NSGs
  az network nsg list -g "$RG" -o json 2>/dev/null \
    | jq -r --arg RG "$RG" '
        .[] | [$RG, "Network", "NSG", .name,
               ((.securityRules // []) | length | tostring),
               ((.subnets // []) | length | tostring),
               ((.networkInterfaces // []) | length | tostring),
               ""] | @csv' >> "$NETWORK_CSV" || true

  # Route Tables
  az network route-table list -g "$RG" -o json 2>/dev/null \
    | jq -r --arg RG "$RG" '
        .[] | [$RG, "Network", "RouteTable", .name,
               ((.routes // []) | length | tostring),
               ((.subnets // []) | length | tostring),
               "", ""] | @csv' >> "$NETWORK_CSV" || true

  # Public IPs
  az network public-ip list -g "$RG" -o json 2>/dev/null \
    | jq -r --arg RG "$RG" '
        .[] | [$RG, "Network", "PublicIP", .name,
               (.ipAddress // "unassigned"),
               (.publicIPAllocationMethod // ""),
               (.sku.name // ""), ""] | @csv' >> "$NETWORK_CSV" || true

  log "  RG scan complete: $RG"
done

# =============================================================================
# Build inventory matrix (ResourceType × RG counts + delta column)
# =============================================================================
log "Building inventory matrix (pivot)..."

TYPES_TMP=$(mktemp)
RGS_TMP=$(mktemp)
awk -F'|' '{print $2}' "$PIVOT_TMP" | sort -u > "$TYPES_TMP"
printf '%s\n' "${RG_LIST[@]}" > "$RGS_TMP"

# Header
{
  printf "ResourceType"
  while IFS= read -r RG; do printf ",%s" "$RG"; done < "$RGS_TMP"
  printf ",Delta(max-min)\n"
} > "$MATRIX_CSV"

# Data rows
while IFS= read -r TYPE; do
  ROW="\"$TYPE\""
  MIN=999999
  MAX=0
  while IFS= read -r RG; do
    COUNT=$(grep -Fxc "${RG}|${TYPE}" "$PIVOT_TMP" || true)
    ROW="${ROW},${COUNT}"
    (( COUNT < MIN )) && MIN=$COUNT
    (( COUNT > MAX )) && MAX=$COUNT
  done < "$RGS_TMP"
  DELTA=$((MAX - MIN))
  echo "${ROW},${DELTA}" >> "$MATRIX_CSV"
done < "$TYPES_TMP"

rm -f "$TYPES_TMP" "$RGS_TMP"

# =============================================================================
# Summary
# =============================================================================
{
  echo "RG Delta Scan Summary"
  echo "Generated : $(date)"
  echo "Subscription: $(echo "$CURRENT_SUB" | jq -r '.name + " (" + .id + ")"')"
  echo ""
  echo "Resource Groups scanned: ${#RG_LIST[@]}"
  for RG in "${RG_LIST[@]}"; do
    N=$(grep -c "^${RG}," "$INVENTORY_CSV" || true)
    printf "  - %-55s %s resources\n" "$RG" "$N"
  done
  echo ""
  echo "Output files:"
  echo "  Log             : $LOG_FILE"
  echo "  Inventory (long): $INVENTORY_CSV"
  echo "  Matrix  (pivot) : $MATRIX_CSV"
  echo "  Network detail  : $NETWORK_CSV"
} | tee "$SUMMARY_TXT"

log "=== RG Delta Scan complete ==="
