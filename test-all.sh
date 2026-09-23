#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

export NO_PROXY="${NO_PROXY:-*}"
export no_proxy="${no_proxy:-*}"

GW="${GATEWAY_URL:-http://127.0.0.1:8072}"
CORR="eazybank-correlation-id: test-all"
MOBILE="43544$(printf '%05d' $((RANDOM % 100000)))"
HIT_LOG="$(mktemp)"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\033[0m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  CYAN=$'\033[36m'
else
  RESET="" BOLD="" DIM="" RED="" GREEN="" YELLOW="" CYAN=""
fi

pass=0
fail=0

say() {
  printf "%s%s[%s]%s %s\n" "$BOLD" "$1" "$2" "$RESET" "$3"
}

mark() {
  printf '%s %s %s\n' "$1" "$2" "$3" >> "$HIT_LOG"
}

json_get() {
  local json="$1" key="$2"
  printf '%s' "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

json_num() {
  local json="$1" key="$2"
  printf '%s' "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" | head -n 1
}

request() {
  local method="$1"
  local url="$2"
  local data="${3:-}"
  local ctype="${4:-application/json}"
  local tmp
  tmp="$(mktemp)"
  local code
  if [[ -n "$data" ]]; then
    code="$(curl --noproxy '*' -sS -o "$tmp" -w '%{http_code}' -X "$method" \
      -H "$CORR" -H "Content-Type: ${ctype}" --max-time 20 \
      --data "$data" "$url" || true)"
  else
    code="$(curl --noproxy '*' -sS -o "$tmp" -w '%{http_code}' -X "$method" \
      -H "$CORR" --max-time 20 \
      "$url" || true)"
  fi
  LAST_BODY="$(cat "$tmp")"
  rm -f "$tmp"
  LAST_CODE="$code"
}

expect() {
  local name="$1"
  local spec="$2"
  local method="$3"
  local path="$4"
  local url="$5"
  local want="$6"
  local data="${7:-}"
  local ctype="${8:-application/json}"
  request "$method" "$url" "$data" "$ctype"
  mark "$spec" "$method" "$path"
  if [[ " $want " == *" $LAST_CODE "* ]]; then
    pass=$((pass + 1))
    say "$GREEN" "PASS" "$name ${DIM}${method} ${path} -> ${LAST_CODE}${RESET}"
    return 0
  fi
  fail=$((fail + 1))
  say "$RED" "FAIL" "$name ${DIM}${method} ${path} -> ${LAST_CODE} (want ${want})${RESET}"
  if [[ -n "$LAST_BODY" ]]; then
    printf '%s\n' "${DIM}${LAST_BODY:0:240}${RESET}"
  fi
  return 1
}

contains() {
  local name="$1"
  local needle="$2"
  if printf '%s' "$LAST_BODY" | grep -q -- "$needle"; then
    pass=$((pass + 1))
    say "$GREEN" "PASS" "$name ${DIM}body contains ${needle}${RESET}"
    return 0
  fi
  fail=$((fail + 1))
  say "$RED" "FAIL" "$name ${DIM}missing ${needle}${RESET}"
  return 1
}

printf "\n%s%s Eazy Bank%s  full API check\n" "$BOLD" "$CYAN" "$RESET"
say "$YELLOW" "INFO" "Gateway ${BOLD}${GW}${RESET}  mobile ${BOLD}${MOBILE}${RESET}"

printf "\n"
say "$CYAN" "RUN " "Accounts"
expect "create" accounts POST /api/create "${GW}/eazybank/accounts/api/create" "201" \
  "{\"name\":\"Test User\",\"email\":\"test@eazybank.com\",\"mobileNumber\":\"${MOBILE}\"}"
expect "create duplicate" accounts POST /api/create "${GW}/eazybank/accounts/api/create" "400" \
  "{\"name\":\"Test User\",\"email\":\"test@eazybank.com\",\"mobileNumber\":\"${MOBILE}\"}"
expect "fetch" accounts GET /api/fetch "${GW}/eazybank/accounts/api/fetch?mobileNumber=${MOBILE}" "200"
contains "fetch name" "Test User"
ACCOUNT_NUMBER="$(json_num "$LAST_BODY" "accountNumber")"
if [[ -z "$ACCOUNT_NUMBER" ]]; then
  fail=$((fail + 1))
  say "$RED" "FAIL" "account number missing"
else
  pass=$((pass + 1))
  say "$GREEN" "PASS" "account number ${BOLD}${ACCOUNT_NUMBER}${RESET}"
  expect "update" accounts PUT /api/update "${GW}/eazybank/accounts/api/update" "200" \
    "{\"name\":\"Test User\",\"email\":\"updated@eazybank.com\",\"mobileNumber\":\"${MOBILE}\",\"accountsDto\":{\"accountNumber\":${ACCOUNT_NUMBER},\"accountType\":\"Savings\",\"branchAddress\":\"123 NewYork\"}}"
  expect "fetch after update" accounts GET /api/fetch "${GW}/eazybank/accounts/api/fetch?mobileNumber=${MOBILE}" "200"
  contains "email updated" "updated@eazybank.com"
fi
expect "contact-info" accounts GET /api/contact-info "${GW}/eazybank/accounts/api/contact-info" "200"
contains "contact payload" "contactDetails"
expect "build-info" accounts GET /api/build-info "${GW}/eazybank/accounts/api/build-info" "200"
expect "java-version" accounts GET /api/java-version "${GW}/eazybank/accounts/api/java-version" "200"

printf "\n"
say "$CYAN" "RUN " "Cards"
expect "create" cards POST /api/create "${GW}/eazybank/cards/api/create?mobileNumber=${MOBILE}" "201"
expect "fetch" cards GET /api/fetch "${GW}/eazybank/cards/api/fetch?mobileNumber=${MOBILE}" "200"
CARD_NUMBER="$(json_get "$LAST_BODY" "cardNumber")"
if [[ -z "$CARD_NUMBER" ]]; then
  fail=$((fail + 1))
  say "$RED" "FAIL" "card number missing"
else
  pass=$((pass + 1))
  say "$GREEN" "PASS" "card number ${BOLD}${CARD_NUMBER}${RESET}"
  expect "update" cards PUT /api/update "${GW}/eazybank/cards/api/update" "200" \
    "{\"mobileNumber\":\"${MOBILE}\",\"cardNumber\":\"${CARD_NUMBER}\",\"cardType\":\"Credit Card\",\"totalLimit\":200000,\"amountUsed\":1000,\"availableAmount\":199000}"
  expect "fetch after update" cards GET /api/fetch "${GW}/eazybank/cards/api/fetch?mobileNumber=${MOBILE}" "200"
  contains "limit updated" "200000"
fi
expect "contact-info" cards GET /api/contact-info "${GW}/eazybank/cards/api/contact-info" "200"
expect "build-info" cards GET /api/build-info "${GW}/eazybank/cards/api/build-info" "200"
expect "java-version" cards GET /api/java-version "${GW}/eazybank/cards/api/java-version" "200"

printf "\n"
say "$CYAN" "RUN " "Loans"
expect "create" loans POST /api/create "${GW}/eazybank/loans/api/create?mobileNumber=${MOBILE}" "201"
expect "fetch" loans GET /api/fetch "${GW}/eazybank/loans/api/fetch?mobileNumber=${MOBILE}" "200"
LOAN_NUMBER="$(json_get "$LAST_BODY" "loanNumber")"
if [[ -z "$LOAN_NUMBER" ]]; then
  fail=$((fail + 1))
  say "$RED" "FAIL" "loan number missing"
else
  pass=$((pass + 1))
  say "$GREEN" "PASS" "loan number ${BOLD}${LOAN_NUMBER}${RESET}"
  expect "update" loans PUT /api/update "${GW}/eazybank/loans/api/update" "200" \
    "{\"mobileNumber\":\"${MOBILE}\",\"loanNumber\":\"${LOAN_NUMBER}\",\"loanType\":\"Home Loan\",\"totalLoan\":150000,\"amountPaid\":5000,\"outstandingAmount\":145000}"
  expect "fetch after update" loans GET /api/fetch "${GW}/eazybank/loans/api/fetch?mobileNumber=${MOBILE}" "200"
  contains "amount updated" "150000"
fi
expect "contact-info" loans GET /api/contact-info "${GW}/eazybank/loans/api/contact-info" "200"
expect "build-info" loans GET /api/build-info "${GW}/eazybank/loans/api/build-info" "200"
expect "java-version" loans GET /api/java-version "${GW}/eazybank/loans/api/java-version" "200"

printf "\n"
say "$CYAN" "RUN " "Customer details"
expect "fetchCustomerDetails" accounts GET /api/fetchCustomerDetails \
  "${GW}/eazybank/accounts/api/fetchCustomerDetails?mobileNumber=${MOBILE}" "200"
contains "includes card" "cardNumber"
contains "includes loan" "loanNumber"

printf "\n"
say "$CYAN" "RUN " "Message"
expect "info" message GET /api/info "${GW}/eazybank/message/api/info" "200"
contains "messaging flag" "messagingEnabled"

printf "\n"
say "$CYAN" "RUN " "Gateway"
expect "home" gateway GET / "${GW}/" "200"
expect "contactSupport GET" gateway GET /contactSupport "${GW}/contactSupport" "200"
expect "contactSupport POST" gateway POST /contactSupport "${GW}/contactSupport" "200"
expect "contactSupport PUT" gateway PUT /contactSupport "${GW}/contactSupport" "200"
expect "contactSupport DELETE" gateway DELETE /contactSupport "${GW}/contactSupport" "200"
expect "contactSupport PATCH" gateway PATCH /contactSupport "${GW}/contactSupport" "200"
contains "fallback text" "contact support"

printf "\n"
say "$CYAN" "RUN " "Config server"
CFG="${GW}/eazybank/configserver"
expect "name/profiles" configserver GET "/{name}/{profiles}" "${CFG}/accounts/prod" "200"
contains "accounts prod" "contactDetails"
expect "cards prod" configserver GET "/{name}/{profiles}" "${CFG}/cards/prod" "200"
expect "loans prod" configserver GET "/{name}/{profiles}" "${CFG}/loans/prod" "200"
expect "name/profiles/label" configserver GET "/{name}/{profiles}/{label}" "${CFG}/accounts/prod/main" "200"
expect "name/profile/path" configserver GET "/{name}/{profile}/{path}" "${CFG}/accounts/prod/application" "200"
expect "name/profile/label/**" configserver GET "/{name}/{profile}/{label}/**" "${CFG}/accounts/prod/main/application" "200 404"
expect "name-profiles.yml" configserver GET "/{name}-{profiles}.yml" "${CFG}/accounts-prod.yml" "200"
expect "name-profiles.yaml" configserver GET "/{name}-{profiles}.yaml" "${CFG}/accounts-prod.yaml" "200"
expect "name-profiles.json" configserver GET "/{name}-{profiles}.json" "${CFG}/accounts-prod.json" "200"
expect "name-profiles.properties" configserver GET "/{name}-{profiles}.properties" "${CFG}/accounts-prod.properties" "200"
expect "label/name-profiles.yml" configserver GET "/{label}/{name}-{profiles}.yml" "${CFG}/main/accounts-prod.yml" "200"
expect "label/name-profiles.yaml" configserver GET "/{label}/{name}-{profiles}.yaml" "${CFG}/main/accounts-prod.yaml" "200"
expect "label/name-profiles.json" configserver GET "/{label}/{name}-{profiles}.json" "${CFG}/main/accounts-prod.json" "200"
expect "label/name-profiles.properties" configserver GET "/{label}/{name}-{profiles}.properties" "${CFG}/main/accounts-prod.properties" "200"
expect "encrypt status" configserver GET /encrypt/status "${CFG}/encrypt/status" "200"
expect "key" configserver GET /key "${CFG}/key" "404"
contains "no public key" "No public key available"
expect "encrypt" configserver POST /encrypt "${CFG}/encrypt" "200" "eazybank-test" "text/plain"
CIPHER="$LAST_BODY"
expect "decrypt" configserver POST /decrypt "${CFG}/decrypt" "200" "$CIPHER" "text/plain"
contains "decrypt plaintext" "eazybank-test"
expect "encrypt named" configserver POST "/encrypt/{name}/{profiles}" "${CFG}/encrypt/accounts/prod" "200" "eazybank-test" "text/plain"
NAMED_CIPHER="$LAST_BODY"
expect "decrypt named" configserver POST "/decrypt/{name}/{profiles}" "${CFG}/decrypt/accounts/prod" "200" "$NAMED_CIPHER" "text/plain"
expect "key named" configserver GET "/key/{name}/{profiles}" "${CFG}/key/accounts/prod" "404"

printf "\n"
say "$CYAN" "RUN " "Deletes"
expect "loan delete" loans DELETE /api/delete "${GW}/eazybank/loans/api/delete?mobileNumber=${MOBILE}" "200"
expect "card delete" cards DELETE /api/delete "${GW}/eazybank/cards/api/delete?mobileNumber=${MOBILE}" "200"
expect "account delete" accounts DELETE /api/delete "${GW}/eazybank/accounts/api/delete?mobileNumber=${MOBILE}" "200"
expect "account gone" accounts GET /api/fetch "${GW}/eazybank/accounts/api/fetch?mobileNumber=${MOBILE}" "404"
expect "card gone" cards GET /api/fetch "${GW}/eazybank/cards/api/fetch?mobileNumber=${MOBILE}" "404"
expect "loan gone" loans GET /api/fetch "${GW}/eazybank/loans/api/fetch?mobileNumber=${MOBILE}" "404"

printf "\n"
say "$CYAN" "RUN " "OpenAPI coverage"
required=(
  "accounts GET /api/build-info"
  "accounts GET /api/contact-info"
  "accounts POST /api/create"
  "accounts DELETE /api/delete"
  "accounts GET /api/fetch"
  "accounts GET /api/fetchCustomerDetails"
  "accounts GET /api/java-version"
  "accounts PUT /api/update"
  "cards GET /api/build-info"
  "cards GET /api/contact-info"
  "cards POST /api/create"
  "cards DELETE /api/delete"
  "cards GET /api/fetch"
  "cards GET /api/java-version"
  "cards PUT /api/update"
  "loans GET /api/build-info"
  "loans GET /api/contact-info"
  "loans POST /api/create"
  "loans DELETE /api/delete"
  "loans GET /api/fetch"
  "loans GET /api/java-version"
  "loans PUT /api/update"
  "message GET /api/info"
  "gateway GET /"
  "gateway GET /contactSupport"
  "gateway POST /contactSupport"
  "gateway PUT /contactSupport"
  "gateway DELETE /contactSupport"
  "gateway PATCH /contactSupport"
  "configserver POST /decrypt"
  "configserver POST /decrypt/{name}/{profiles}"
  "configserver POST /encrypt"
  "configserver GET /encrypt/status"
  "configserver POST /encrypt/{name}/{profiles}"
  "configserver GET /key"
  "configserver GET /key/{name}/{profiles}"
  "configserver GET /{label}/{name}-{profiles}.json"
  "configserver GET /{label}/{name}-{profiles}.properties"
  "configserver GET /{label}/{name}-{profiles}.yaml"
  "configserver GET /{label}/{name}-{profiles}.yml"
  "configserver GET /{name}-{profiles}.json"
  "configserver GET /{name}-{profiles}.properties"
  "configserver GET /{name}-{profiles}.yaml"
  "configserver GET /{name}-{profiles}.yml"
  "configserver GET /{name}/{profiles}"
  "configserver GET /{name}/{profiles}/{label}"
  "configserver GET /{name}/{profile}/{label}/**"
  "configserver GET /{name}/{profile}/{path}"
)

covered=0
missing=0
for op in "${required[@]}"; do
  if grep -qxF "$op" "$HIT_LOG"; then
    covered=$((covered + 1))
  else
    missing=$((missing + 1))
    say "$RED" "MISS" "$op"
  fi
done
if (( missing == 0 )); then
  pass=$((pass + 1))
  say "$GREEN" "PASS" "every OpenAPI operation was called ${DIM}${covered}/${#required[@]}${RESET}"
else
  fail=$((fail + 1))
  say "$RED" "FAIL" "untested OpenAPI operations ${DIM}${covered}/${#required[@]}${RESET}"
fi
rm -f "$HIT_LOG"

printf "\n"
total=$((pass + fail))
if (( fail == 0 )); then
  say "$GREEN" "DONE" "${BOLD}${pass}${RESET} passed, ${fail} failed  ${DIM}(${total} checks)${RESET}"
  exit 0
fi
say "$RED" "FAIL" "${pass} passed, ${BOLD}${fail}${RESET} failed  ${DIM}(${total} checks)${RESET}"
exit 1
