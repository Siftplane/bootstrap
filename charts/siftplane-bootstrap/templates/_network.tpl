{{/* Helm has no IP parser. Count IPv6 groups, including compression and IPv4 tails,
     before emitting a Context or NetworkPolicy that Kubernetes/the installer cannot read. */}}
{{- define "bootstrap.ip" -}}
{{- $address := . -}}
{{- $ipv4 := "^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$" -}}
{{- if contains ":" $address -}}
{{- $halves := splitList "::" $address -}}
{{- if gt (len $halves) 2 -}}{{ fail "multiple IPv6 compression markers" }}{{- end -}}
{{- $count := 0 -}}
{{- range $side, $half := $halves -}}
{{- if ne $half "" -}}
{{- $groups := splitList ":" $half -}}
{{- range $index, $group := $groups -}}
{{- if contains "." $group -}}
{{- if or (ne (int $side) (int (sub (len $halves) 1))) (ne (int $index) (int (sub (len $groups) 1))) (not (regexMatch $ipv4 $group)) -}}{{ fail "invalid IPv6 embedded IPv4 address" }}{{- end -}}
{{- $count = add $count 2 -}}
{{- else -}}
{{- if not (regexMatch "^[0-9a-fA-F]{1,4}$" $group) -}}{{ fail "invalid IPv6 group" }}{{- end -}}
{{- $count = add $count 1 -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if or (and (eq (len $halves) 2) (ge $count 8)) (and (eq (len $halves) 1) (ne $count 8)) -}}{{ fail "invalid IPv6 group count" }}{{- end -}}
{{- else -}}
{{- if not (regexMatch $ipv4 $address) -}}{{ fail "invalid IPv4 address" }}{{- end -}}
{{- end -}}
{{- end -}}

{{- define "bootstrap.cidr" -}}
{{- $parts := splitList "/" . -}}
{{- if ne (len $parts) 2 -}}{{ fail "invalid network CIDR" }}{{- end -}}
{{- $address := index $parts 0 -}}
{{- include "bootstrap.ip" $address -}}
{{- $prefix := index $parts 1 -}}
{{- $bits := 32 -}}
{{- if contains ":" $address -}}{{- $bits = 128 -}}{{- end -}}
{{- if or (not (regexMatch "^[1-9][0-9]{0,2}$" $prefix)) (gt (int $prefix) $bits) -}}{{ fail "invalid network CIDR prefix" }}{{- end -}}
{{- $parsed := include "bootstrap.words" $address | fromJson -}}
{{- if ne $address (include "bootstrap.canonical" $parsed) -}}{{ fail "network CIDRs must use canonical address spelling" }}{{- end -}}
{{- range $index, $word := $parsed.words -}}
{{- $networkBits := max 0 (min (int $parsed.width) (sub (int $prefix) (mul $index (int $parsed.width)))) -}}
{{- $divisor := 1 -}}
{{- range until (int (sub (int $parsed.width) $networkBits)) -}}{{- $divisor = mul $divisor 2 -}}{{- end -}}
{{- if ne (mod (int $word) $divisor) 0 -}}{{ fail "network CIDRs must have zero host bits" }}{{- end -}}
{{- end -}}
{{- end -}}

{{/* Numeric words stay at most16bits, avoiding template integer precision loss for IPv6. */}}
{{- define "bootstrap.half" -}}
{{- $words := list -}}
{{- $digits := dict "0" 0 "1" 1 "2" 2 "3" 3 "4" 4 "5" 5 "6" 6 "7" 7 "8" 8 "9" 9 "a" 10 "b" 11 "c" 12 "d" 13 "e" 14 "f" 15 -}}
{{- if ne . "" -}}
{{- range splitList ":" . -}}
{{- if contains "." . -}}
{{- $octets := splitList "." . -}}
{{- $words = append $words (add (mul (int (index $octets 0)) 256) (int (index $octets 1))) -}}
{{- $words = append $words (add (mul (int (index $octets 2)) 256) (int (index $octets 3))) -}}
{{- else -}}
{{- $value := 0 -}}
{{- range splitList "" (lower .) -}}{{- $value = add (mul $value 16) (index $digits .) -}}{{- end -}}
{{- $words = append $words $value -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{ dict "words" $words | toJson }}
{{- end -}}

{{- define "bootstrap.words" -}}
{{- include "bootstrap.ip" . -}}
{{- $words := list -}}
{{- $width := 8 -}}
{{- if contains ":" . -}}
{{- $width = 16 -}}
{{- $halves := splitList "::" . -}}
{{- $left := (include "bootstrap.half" (first $halves) | fromJson).words -}}
{{- $words = $left -}}
{{- if eq (len $halves) 2 -}}
{{- $right := (include "bootstrap.half" (last $halves) | fromJson).words -}}
{{- range until (int (sub 8 (add (len $left) (len $right)))) -}}{{- $words = append $words 0 -}}{{- end -}}
{{- $words = concat $words $right -}}
{{- end -}}
{{- else -}}
{{- range splitList "." . -}}{{- $words = append $words (int .) -}}{{- end -}}
{{- end -}}
{{ dict "words" $words "width" $width | toJson }}
{{- end -}}

{{- define "bootstrap.canonical" -}}
{{- $words := .words -}}
{{- if eq (int .width) 8 -}}
{{ join "." $words }}
{{- else -}}
{{- $mapped := eq (int (index $words 5)) 65535 -}}
{{- range slice $words 0 5 -}}{{- if ne (int .) 0 -}}{{- $mapped = false -}}{{- end -}}{{- end -}}
{{- if $mapped -}}
{{ printf "::ffff:%d.%d.%d.%d" (div (int (index $words 6)) 256) (mod (int (index $words 6)) 256) (div (int (index $words 7)) 256) (mod (int (index $words 7)) 256) }}
{{- else -}}
{{- $parts := list -}}
{{- $bestStart := 0 -}}{{- $bestLength := 0 -}}{{- $run := 0 -}}
{{- range $index, $word := $words -}}
{{- $parts = append $parts (printf "%x" (int $word)) -}}
{{- if eq (int $word) 0 -}}
{{- $run = add $run 1 -}}
{{- if gt $run $bestLength -}}{{- $bestLength = $run -}}{{- $bestStart = sub (add $index 1) $run -}}{{- end -}}
{{- else -}}{{- $run = 0 -}}{{- end -}}
{{- end -}}
{{- if ge $bestLength 2 -}}
{{ printf "%s::%s" (join ":" (slice $parts 0 (int $bestStart))) (join ":" (slice $parts (int (add $bestStart $bestLength)))) }}
{{- else -}}{{ join ":" $parts }}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "bootstrap.membership" -}}
{{- $address := include "bootstrap.words" .address | fromJson -}}
{{- $covered := false -}}
{{- range .cidrs -}}
{{- include "bootstrap.cidr" . -}}
{{- $cidr := splitList "/" . -}}
{{- $network := include "bootstrap.words" (first $cidr) | fromJson -}}
{{- $prefix := int (last $cidr) -}}
{{- $matches := eq (int $address.width) (int $network.width) -}}
{{- if $matches -}}
{{- range $index, $word := $address.words -}}
{{- $networkBits := max 0 (min (int $address.width) (sub $prefix (mul $index (int $address.width)))) -}}
{{- $divisor := 1 -}}
{{- range until (int (sub (int $address.width) $networkBits)) -}}{{- $divisor = mul $divisor 2 -}}{{- end -}}
{{- if ne (div (int $word) $divisor) (div (int (index $network.words $index)) $divisor) -}}{{- $matches = false -}}{{- end -}}
{{- end -}}
{{- end -}}
{{- if $matches -}}{{- $covered = true -}}{{- end -}}
{{- end -}}
{{- if not $covered -}}{{ fail "literal endpoint address must be covered by its network CIDRs" }}{{- end -}}
{{- end -}}

{{- define "bootstrap.endpoint" -}}
{{- $authority := trimSuffix "/" (trimPrefix "https://" .url) -}}
{{- $port := 443 -}}
{{- if regexMatch ":[0-9]+$" $authority -}}
{{- $port = int (trimPrefix ":" (regexFind ":[0-9]+$" $authority)) -}}
{{- end -}}
{{- if or (lt $port 1) (gt $port 65535) (ne $port (int .network.port)) -}}{{ fail "endpoint URL port must match its network port (1..65535)" }}{{- end -}}
{{- if hasPrefix "[" $authority -}}
{{- $address := trimPrefix "[" (first (splitList "]" $authority)) -}}
{{- include "bootstrap.membership" (dict "address" $address "cidrs" .network.cidrs) -}}
{{- else -}}
{{- $host := first (splitList ":" $authority) -}}
{{- $last := last (splitList "." $host) -}}
{{- if or (regexMatch "^[0-9]+$" $last) (regexMatch "^0[xX][0-9a-fA-F]+$" $last) -}}
{{- include "bootstrap.membership" (dict "address" $host "cidrs" .network.cidrs) -}}
{{- else -}}
{{- if gt (len $host) 253 -}}{{ fail "endpoint hostname exceeds 253 bytes" }}{{- end -}}
{{- range splitList "." $host -}}
{{- if or (gt (len .) 63) (not (regexMatch "^[a-zA-Z0-9]([-a-zA-Z0-9]*[a-zA-Z0-9])?$" .)) -}}{{ fail "invalid endpoint hostname" }}{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
