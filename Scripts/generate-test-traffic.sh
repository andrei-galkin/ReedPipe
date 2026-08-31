#!/usr/bin/env bash

set -uo pipefail

readonly proxy_url="${REEDPIPE_PROXY_URL:-http://127.0.0.1:8080}"
readonly ca_certificate="${REEDPIPE_CA_CERTIFICATE:-${HOME}/.reedpipe/ReedPipeRootCA.pem}"
readonly connect_timeout="${REEDPIPE_CONNECT_TIMEOUT:-5}"
readonly request_timeout="${REEDPIPE_REQUEST_TIMEOUT:-20}"

readonly -a http_cases=(
    "200|GET|http://example.com/|"
    "200|GET|http://example.org/|"
    "200|GET|http://example.net/|"
    "502|GET|http://127.0.0.1:1/reedpipe-expected-connect-failure|"
    '200|POST|http://httpbin.org/post|{"source":"reedpipe","protocol":"http"}'
    "200|DELETE|http://httpbin.org/delete|"
    "204|GET|http://httpbin.org/status/204|"
    "200|GET|http://detectportal.firefox.com/success.txt|"
    "204|GET|http://connectivitycheck.gstatic.com/generate_204|"
    "200|GET|http://www.msftconnecttest.com/connecttest.txt|"
)

readonly -a https_cases=(
    "200|GET|https://example.com/|"
    "200|GET|https://example.org/|"
    "200|GET|https://example.net/|"
    '200|POST|https://postman-echo.com/post|{"source":"reedpipe","protocol":"https"}'
    "200|DELETE|https://postman-echo.com/delete|"
    "503|GET|https://httpbin.org/status/503|"
    '200|PATCH|https://postman-echo.com/patch|{"source":"reedpipe","operation":"patch-test"}'
    "200|GET|https://www.swift.org/|"
    "200|GET|https://api.github.com/zen|"
    "200|GET|https://www.cloudflare.com/cdn-cgi/trace|"
)

readonly total_requests=$((${#http_cases[@]} + ${#https_cases[@]}))

if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl is not installed" >&2
    exit 1
fi

if [[ ! -r "${ca_certificate}" ]]; then
    echo "error: ReedPipe CA certificate is not readable: ${ca_certificate}" >&2
    echo "Start ReedPipe once to generate it, or set REEDPIPE_CA_CERTIFICATE." >&2
    exit 1
fi

request_index=0
successful_requests=0
expected_error_responses=0
failed_requests=0

run_request() {
    local -r protocol="$1"
    local -r method="$2"
    local -r url="$3"
    local -r expected_status="$4"
    local -r request_body="$5"
    local -a arguments=(
        --silent
        --show-error
        --output /dev/null
        --http1.1
        --noproxy ""
        --connect-timeout "${connect_timeout}"
        --max-time "${request_timeout}"
        --proxy "${proxy_url}"
        --request "${method}"
        --write-out "%{http_code}|connect=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s"
    )

    if [[ "${protocol}" == "HTTPS" ]]; then
        arguments+=(--cacert "${ca_certificate}")
    fi

    if [[ -n "${request_body}" ]]; then
        arguments+=(
            --header "Content-Type: application/json"
            --data-raw "${request_body}"
        )
    fi

    ((request_index += 1))
    printf '\n[%02d/%02d] %s %s %s\n' \
        "${request_index}" \
        "${total_requests}" \
        "${protocol}" \
        "${method}" \
        "${url}"

    local result
    if result="$(curl "${arguments[@]}" "${url}")"; then
        local -r actual_status="${result%%|*}"
        local -r timings="${result#*|}"
        if [[ "${actual_status}" != "${expected_status}" ]]; then
            printf '  FAIL expected-status=%s actual-status=%s %s\n' \
                "${expected_status}" \
                "${actual_status}" \
                "${timings}"
            ((failed_requests += 1))
        elif ((actual_status >= 400)); then
            printf '  EXPECTED-ERROR status=%s %s\n' "${actual_status}" "${timings}"
            ((expected_error_responses += 1))
        else
            printf '  PASS status=%s %s\n' "${actual_status}" "${timings}"
            ((successful_requests += 1))
        fi
    else
        local -r curl_status=$?
        printf '  FAIL curl-exit=%d result=%s\n' "${curl_status}" "${result}"
        ((failed_requests += 1))
    fi
}

echo "ReedPipe traffic smoke test"
echo "Proxy: ${proxy_url}"
echo "CA:    ${ca_certificate}"

for test_case in "${http_cases[@]}"; do
    IFS='|' read -r expected_status method url request_body <<<"${test_case}"
    run_request "HTTP" "${method}" "${url}" "${expected_status}" "${request_body}"
done

for test_case in "${https_cases[@]}"; do
    IFS='|' read -r expected_status method url request_body <<<"${test_case}"
    run_request "HTTPS" "${method}" "${url}" "${expected_status}" "${request_body}"
done

printf '\nFinished: %d passed, %d expected error responses, %d unexpected failures, %d total.\n' \
    "${successful_requests}" \
    "${expected_error_responses}" \
    "${failed_requests}" \
    "${total_requests}"

if ((failed_requests > 0)); then
    exit 1
fi
