#!/bin/env sh

tmp_path='/data/local/tmp'
crt_path="$tmp_path/http-toolkit-ca-certificate.crt"
dos2unix "$crt_path"

crt_hash="$(openssl x509 -inform PEM -subject_hash_old -in "$crt_path" -noout)"
hash_path="$tmp_path/$crt_hash.0"
openssl x509 -in "$crt_path" >"$hash_path"
openssl x509 -in "$crt_path" -fingerprint -text -noout >>"$hash_path"
