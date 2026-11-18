#!/usr/bin/env bash
# Baut die beiden Netz-Bibliotheken für „Zimmer online“ (docs/PLAN_ZIMMER_ONLINE.md, docs/ZIMMER_SICHERHEIT.md W7)
# reproduzierbar aus fest gepinnten Quellen der offiziellen Repos:
#
#   assets/net/uzai-secp256k1.dll    libsecp256k1 (nur schnorrsig + extrakeys)      – BIP-340-Signatur der Nostr-Hülle
#   assets/net/uzai-datachannel.dll  libdatachannel + libjuice + usrsctp + Mbed TLS – WebRTC-Datenkanal (ohne Medien,
#                                    ohne WebSocket, ohne TURN-/STUN-Server, nur UDP)
#
# Beide werden NUR in der AppContainer-Sandbox geladen (helper/uzai-helper.ps1, UzNetzLib), nie in Uzai.
#
# Quellen: Jede Datei steht mit SHA-256 in tools/netzlibs/quellen.txt und kommt von
# https://raw.githubusercontent.com/<repo>/<commit>/<pfad> (Commits unten, je ein Release-Tag; usrsctp hat seit
# 0.9.5.0 (2021) keinen Tag mehr – gepinnt ist der offizielle sctplab-Commit, dessen Quelltext libdatachannel v0.24.6
# mitbringt). Stimmt eine Prüfsumme nicht, bricht der Bau ab.
#
# Kreuzbau für Windows x64 mit mingw-w64 (gcc, posix-Fäden), alles statisch außer Windows-Systembibliotheken;
# Härtung: /DYNAMICBASE, /HIGHENTROPYVA, /NXCOMPAT, -fstack-protector-strong, -D_FORTIFY_SOURCE=2, ohne Zeitstempel.
# Dazu eine Linux-Fassung derselben Quellen NUR für die Tests (build/netzlibs-linux/, nie ins Paket).
#
#   tools/bau_netzlibs.sh                 Quellen holen/prüfen, Windows- und Linux-Fassung bauen, DLLs nach assets/net/
#   tools/bau_netzlibs.sh --linux         nur die Linux-Fassung (für die Tests)
#   tools/bau_netzlibs.sh --pruefen       Windows-Fassung in einen Zwischenordner bauen und mit assets/net/ vergleichen
#   tools/bau_netzlibs.sh --liste         tools/netzlibs/quellen.txt neu schreiben (nur beim Wechsel einer Fassung: die
#                                         Ablage vorher selbst aus den gepinnten Commits füllen und prüfen)
#   UZAI_NETZLIBS_QUELLEN=<ordner>        Ablage der geprüften Quellen (Standard: build/netzlibs-quellen)
#
# Werkzeuge: curl, sha256sum, x86_64-w64-mingw32-gcc-posix/-g++-posix (apt: g++-mingw-w64-x86-64-posix), gcc/g++.
# Bit-gleich nachgebaut (--pruefen) mit Ubuntu 24.04: gcc-mingw-w64-x86-64-posix 13.2.0-6ubuntu1+26.1, binutils-mingw-w64
# 2.41.90.20240122, mingw-w64-x86-64-dev 11.0.1 (CRT msvcrt.dll); andere Fassungen bauen dieselben Quellen, aber nicht
# bit-gleich. Feste Bildbasis (ASLR verschiebt sie), -frandom-seed je Datei, keine Pfade und Zeitstempel in der DLL.
set -eu
PROJ=$(cd "$(dirname "$0")/.." && pwd)
HIER="$PROJ/tools/netzlibs"
MODUS=${1:-alles}
QUELLEN=${UZAI_NETZLIBS_QUELLEN:-$PROJ/build/netzlibs-quellen}
JOBS=$(nproc 2>/dev/null || echo 2)

# Bibliothek → Repo, Tag, Commit (der Commit, auf den der Tag zeigt).
declare -A REPO=(
	[secp256k1]="bitcoin-core/secp256k1"            # v0.7.1
	[libdatachannel]="paullouisageneau/libdatachannel" # v0.24.6
	[libjuice]="paullouisageneau/libjuice"          # v1.7.4 (= Submodul von libdatachannel v0.24.6)
	[usrsctp]="sctplab/usrsctp"                      # kein Tag; Quelltext = Submodul von libdatachannel v0.24.6
	[mbedtls]="Mbed-TLS/mbedtls"                     # v3.6.7 (LTS)
	[plog]="SergiusTheBest/plog"                     # 1.1.11
)
declare -A COMMIT=(
	[secp256k1]=1a53f4961f337b4d166c25fce72ef0dc88806618
	[libdatachannel]=6b1e2e620f1e37f0eafeee702eaea0043cb305fd
	[libjuice]=b89c792e3612faf2f12cf35bcc56857313a06be3
	[usrsctp]=881513ab3fc75b4c53ffce7b22b08e7b07fcc67a
	[mbedtls]=068ff080b369adfac81509f9b57b2afabaf82dc5
	[plog]=e5c033e317a01b2703d13aab42288d09b2efdafc
)

# --- Quellen holen und prüfen ---------------------------------------------------------------------------------------
holen() {
	mkdir -p "$QUELLEN"
	local fehlt=0 n=0
	while read -r sha pfad; do
		[ -z "$sha" ] && continue
		case "$sha" in \#*) continue ;; esac
		n=$((n + 1))
		local lib=${pfad%%/*} rest=${pfad#*/}
		[ -n "${REPO[$lib]:-}" ] || { echo "unbekannte Bibliothek: $pfad"; exit 1; }
		case "$rest" in *..*|/*) echo "Pfad nicht erlaubt: $pfad"; exit 1 ;; esac
		local ziel="$QUELLEN/$pfad"
		if [ ! -f "$ziel" ] || [ "$(sha256sum "$ziel" | cut -c1-64)" != "$sha" ]; then
			mkdir -p "$(dirname "$ziel")"
			curl -fsS --proto =https --tlsv1.2 --retry 3 -o "$ziel.neu" \
				"https://raw.githubusercontent.com/${REPO[$lib]}/${COMMIT[$lib]}/$rest" || { echo "Download gescheitert: $pfad"; exit 1; }
			mv "$ziel.neu" "$ziel"
		fi
		if [ "$(sha256sum "$ziel" | cut -c1-64)" != "$sha" ]; then
			echo "PRÜFSUMME FALSCH: $pfad"
			rm -f "$ziel"
			fehlt=1
		fi
	done < "$HIER/quellen.txt"
	[ "$fehlt" = 0 ] || exit 1
	[ "$n" -gt 0 ] || { echo "tools/netzlibs/quellen.txt ist leer"; exit 1; }
	echo "Quellen: $n Dateien, alle Prüfsummen stimmen"
}

# --- Übersetzen -----------------------------------------------------------------------------------------------------
# uebersetzen <ausgabe-ordner> <compiler> <flags…> -- <quellen…>   (parallel, je Datei ein Objekt)
uebersetzen() {
	local aus=$1 cc=$2
	shift 2
	local flags=()
	while [ "$1" != "--" ]; do flags+=("$1"); shift; done
	shift
	mkdir -p "$aus"
	# Objektname und -frandom-seed nur aus dem Pfad in der Ablage: keine Zufalls- oder Ortsanteile in der DLL.
	printf '%s\n' "$@" | xargs -P "$JOBS" -I{} sh -c '
		q="$1"; shift; aus="$1"; shift; cc="$1"; shift; wurzel="$1"; shift
		rel=${q#"$wurzel"/}
		o="$aus/$(echo "$rel" | tr / _).o"
		"$cc" "$@" -frandom-seed="$rel" -MD -MF "$o.d" -c "$q" -o "$o" || { echo "FEHLER: $q"; exit 255; }
	' _ {} "$aus" "$cc" "$QUELLEN" "${flags[@]}"
}

bauen() {   # bauen windows|linux <ziel-ordner>
	local ziel=$2 S="$QUELLEN"
	local tmp
	tmp=$(mktemp -d)
	local CC CXX GEMEIN LINK_DLL SECP_AUS RTC_AUS
	if [ "$1" = windows ]; then
		CC=x86_64-w64-mingw32-gcc-posix
		CXX=x86_64-w64-mingw32-g++-posix
		GEMEIN=(-O2 -ffunction-sections -fdata-sections -fstack-protector-strong -D_FORTIFY_SOURCE=2 -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00 -DWIN32_LEAN_AND_MEAN
			-fno-ident -ffile-prefix-map="$S"=src -Wformat -Wformat-security -w)
		LINK_DLL=(-shared -static -s -Wl,--gc-sections -Wl,--dynamicbase -Wl,--high-entropy-va -Wl,--nxcompat -Wl,--no-insert-timestamp -Wl,--disable-auto-image-base -Wl,--image-base=0x180000000
			-Wl,--disable-auto-import -Wl,--enable-reloc-section)
		SECP_AUS="$tmp/uzai-secp256k1.dll"
		RTC_AUS="$tmp/uzai-datachannel.dll"
	else
		CC=gcc
		CXX=g++
		GEMEIN=(-O2 -ffunction-sections -fdata-sections -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -D_GNU_SOURCE -ffile-prefix-map="$S"=src -w)
		LINK_DLL=(-shared -s -Wl,--gc-sections -Wl,-z,relro,-z,now,-z,noexecstack)
		SECP_AUS="$tmp/libuzai-secp256k1.so"
		RTC_AUS="$tmp/libuzai-datachannel.so"
	fi
	local o="$tmp/obj"

	# libsecp256k1: nur schnorrsig und extrakeys (kein ecdh, keine recovery, kein musig, kein ellswift).
	uebersetzen "$o/secp" "$CC" "${GEMEIN[@]}" -std=c89 -fvisibility=hidden -DSECP256K1_BUILD -DSECP256K1_DLL_EXPORT \
		-DENABLE_MODULE_EXTRAKEYS=1 -DENABLE_MODULE_SCHNORRSIG=1 -DECMULT_WINDOW_SIZE=8 -DCOMB_BLOCKS=11 -DCOMB_TEETH=6 \
		-I"$S/secp256k1/include" -I"$S/secp256k1/src" -- \
		"$S/secp256k1/src/secp256k1.c" "$S/secp256k1/src/precomputed_ecmult.c" "$S/secp256k1/src/precomputed_ecmult_gen.c"
	if [ "$1" = windows ]; then
		"$CC" "${LINK_DLL[@]}" -o "$SECP_AUS" "$o"/secp/*.o
	else
		"$CC" "${LINK_DLL[@]}" -Wl,--version-script="$HIER/secp256k1.map" -o "$SECP_AUS" "$o"/secp/*.o
	fi

	# Mbed TLS mit der schmalen Konfiguration.
	local MBED=(-DMBEDTLS_CONFIG_FILE='"mbedtls_uzai.h"' -I"$HIER" -I"$S/mbedtls/include" -I"$S/mbedtls/library")
	uebersetzen "$o/mbedtls" "$CC" "${GEMEIN[@]}" -std=c99 "${MBED[@]}" -- "$S"/mbedtls/library/*.c

	# usrsctp nur mit AF_CONN (kein INET/INET6: keine eigenen Sockets, kein UDP-Kapseln).
	local SCTP=(-D__Userspace__ -DSCTP_SIMPLE_ALLOCATOR -DSCTP_PROCESS_LEVEL_LOCKS -I"$S/usrsctp/usrsctplib")
	if [ "$1" = windows ]; then SCTP+=(-DSCTP_STDINT_INCLUDE='<stdint.h>'); else SCTP+=(-DHAVE_SYS_QUEUE_H -DHAVE_LINUX_IF_ADDR_H -DHAVE_LINUX_RTNETLINK_H -DHAVE_NETINET_IP_ICMP_H -DHAVE_STDATOMIC_H); fi
	local sctp_q=()
	for f in netinet/sctp_asconf.c netinet/sctp_auth.c netinet/sctp_bsd_addr.c netinet/sctp_callout.c netinet/sctp_cc_functions.c \
		netinet/sctp_crc32.c netinet/sctp_indata.c netinet/sctp_input.c netinet/sctp_output.c netinet/sctp_pcb.c netinet/sctp_peeloff.c \
		netinet/sctp_sha1.c netinet/sctp_ss_functions.c netinet/sctp_sysctl.c netinet/sctp_timer.c netinet/sctp_userspace.c \
		netinet/sctp_usrreq.c netinet/sctputil.c netinet6/sctp6_usrreq.c user_environment.c user_mbuf.c user_recv_thread.c user_socket.c; do
		sctp_q+=("$S/usrsctp/usrsctplib/$f")
	done
	uebersetzen "$o/sctp" "$CC" "${GEMEIN[@]}" -std=gnu99 "${SCTP[@]}" -- "${sctp_q[@]}"

	# libjuice ohne Server (kein TURN-/STUN-Server, nichts lauscht), ohne Protokoll-Ausgabe.
	local juice_q=()
	for f in addr agent crc32 const_time conn conn_poll conn_thread conn_mux base64 hash hmac ice juice log random server stun timestamp tcp turn udp; do
		juice_q+=("$S/libjuice/src/$f.c")
	done
	uebersetzen "$o/juice" "$CC" "${GEMEIN[@]}" -std=gnu11 -DJUICE_STATIC -DJUICE_EXPORTS -DNO_SERVER -DRELEASE=1 -DUSE_NETTLE=0 \
		-I"$S/libjuice/include" -I"$S/libjuice/include/juice" -I"$S/libjuice/src" -- "${juice_q[@]}"

	# libdatachannel ohne Medien und WebSocket, Mbed TLS, libjuice; Protokoll ausgebaut (nichts auf stdout).
	local rtc_q=()
	for f in candidate channel configuration datachannel dependencydescriptor description iceudpmuxlistener mediahandler global message \
		peerconnection rtcpreceivingsession track websocket websocketserver rtppacketizationconfig rtcpsrreporter rtppacketizer \
		rtpdepacketizer h264rtppacketizer h264rtpdepacketizer nalunit h265rtppacketizer h265rtpdepacketizer h265nalunit av1rtppacketizer \
		rtcpnackresponder rtp capi plihandler pacinghandler rembhandler; do
		rtc_q+=("$S/libdatachannel/src/$f.cpp")
	done
	for f in certificate channel datachannel dtlssrtptransport dtlstransport icetransport iceudpmuxlistener init peerconnection logcounter \
		sctptransport threadpool tls track utils processor sha pollinterrupter pollservice http httpproxytransport tcpserver tcptransport \
		tlstransport transport verifiedtlstransport websocket websocketserver wstransport wshandshake; do
		rtc_q+=("$S/libdatachannel/src/impl/$f.cpp")
	done
	uebersetzen "$o/rtc" "$CXX" "${GEMEIN[@]}" -std=c++17 -DNOMINMAX -DRTC_STATIC -DRTC_EXPORTS -DRTC_ENABLE_WEBSOCKET=0 -DRTC_ENABLE_MEDIA=0 \
		-DUSE_MBEDTLS=1 -DUSE_GNUTLS=0 -DUSE_NICE=0 -DRTC_SYSTEM_JUICE=0 -DJUICE_STATIC -DPLOG_DISABLE_LOGGING "${MBED[@]}" "${SCTP[@]}" \
		-I"$S/libdatachannel/include" -I"$S/libdatachannel/include/rtc" -I"$S/libdatachannel/src" -I"$S/libjuice/include" -I"$S/plog/include" -- \
		"${rtc_q[@]}"
	if [ "$1" = windows ]; then
		"$CXX" "${LINK_DLL[@]}" -o "$RTC_AUS" "$HIER/datachannel.def" "$o"/rtc/*.o "$o"/juice/*.o "$o"/sctp/*.o "$o"/mbedtls/*.o \
			-lws2_32 -liphlpapi -lbcrypt
	else
		"$CXX" "${LINK_DLL[@]}" -Wl,--version-script="$HIER/datachannel.map" -o "$RTC_AUS" "$o"/rtc/*.o "$o"/juice/*.o "$o"/sctp/*.o \
			"$o"/mbedtls/*.o -lpthread
	fi
	mkdir -p "$ziel"
	cp "$SECP_AUS" "$RTC_AUS" "$ziel/"
	# Nachweis der Härtung in den Objekten (die DLL ist gestrippt): Stack-Schutz und Fortify sind wirklich drin.
	local ssp fort
	ssp=$(cat "$o"/*/*.o | grep -c -a "__stack_chk_fail" || true)
	fort=$(cat "$o"/*/*.o | grep -c -a "__memcpy_chk\|__snprintf_chk\|__memset_chk" || true)
	[ "$ssp" -gt 0 ] && [ "$fort" -gt 0 ] || { echo "$1: Stack-Schutz ($ssp) oder Fortify ($fort) fehlt"; exit 1; }
	echo "$1: Objekte mit Stack-Schutz und Fortify (Treffer $ssp / $fort)"
	# Für --liste: alle wirklich gelesenen Quelldateien (aus den Abhängigkeiten des Compilers).
	if [ -n "${LISTE_AUS:-}" ]; then cat "$o"/*/*.o.d | tr ' \\' '\n\n' | grep -F "$S/" | sort -u | xargs realpath -m -s --relative-to="$S" >> "$LISTE_AUS"; fi
	rm -rf "$tmp"
}

# --- Liste der Quellen neu schreiben (nur beim Wechsel einer Fassung; Quellen aus einer geprüften Ablage) -------------
liste() {
	LISTE_AUS=$(mktemp)
	export LISTE_AUS
	local t
	t=$(mktemp -d)
	bauen windows "$t"
	bauen linux "$t"
	for f in secp256k1/COPYING libdatachannel/LICENSE libjuice/LICENSE usrsctp/LICENSE.md mbedtls/LICENSE plog/LICENSE; do echo "$f" >> "$LISTE_AUS"; done
	{
		echo "# Quellen für tools/bau_netzlibs.sh: SHA-256 und Pfad (<bibliothek>/<pfad im Repo>), erzeugt mit --liste."
		sort -u "$LISTE_AUS" | grep -v '^$' | while read -r f; do echo "$(sha256sum "$QUELLEN/$f" | cut -c1-64)  $f"; done
	} > "$HIER/quellen.txt"
	rm -rf "$t" "$LISTE_AUS"
	echo "quellen.txt: $(grep -vc '^#' "$HIER/quellen.txt") Dateien"
}

# --- Nachweis: Härtung, Exporte, Importe ----------------------------------------------------------------------------
nachweis() {   # nachweis <dll>
	local d=$1
	command -v llvm-readobj >/dev/null || { echo "llvm-readobj fehlt (Nachweis übersprungen)"; return 0; }
	local k
	k=$(llvm-readobj --file-headers "$d")
	for f in IMAGE_DLL_CHARACTERISTICS_DYNAMIC_BASE IMAGE_DLL_CHARACTERISTICS_HIGH_ENTROPY_VA IMAGE_DLL_CHARACTERISTICS_NX_COMPAT; do
		echo "$k" | grep -q "$f" || { echo "$(basename "$d"): $f FEHLT"; exit 1; }
	done
	echo "$k" | grep -q "TimeDateStamp: 1970-01-01 00:00:00 (0x0)" || { echo "$(basename "$d"): Zeitstempel gesetzt"; exit 1; }
	# Nur Windows-Systembibliotheken als Importe (keine mingw-Laufzeit-DLLs).
	local imp
	imp=$(llvm-readobj --coff-imports "$d" | sed -n 's/^  Name: //p' | sort -u | tr '\n' ' ')
	for i in $imp; do
		case "$i" in KERNEL32.dll|msvcrt.dll|WS2_32.dll|IPHLPAPI.DLL|bcrypt.dll|ADVAPI32.dll|api-ms-win-*) ;; *) echo "$(basename "$d"): fremder Import $i"; exit 1 ;; esac
	done
	local nexp
	nexp=$(llvm-readobj --coff-exports "$d" | grep -c "^  Name: " || true)
	echo "$(basename "$d"): DYNAMICBASE HIGHENTROPYVA NXCOMPAT ok, ohne Zeitstempel, Importe: $imp, Exporte: $nexp"
}

case "$MODUS" in
	--liste)
		liste
		;;
	--linux)
		holen
		bauen linux "$PROJ/build/netzlibs-linux"
		ls -l "$PROJ/build/netzlibs-linux"
		;;
	--pruefen)
		holen
		t=$(mktemp -d)
		bauen windows "$t"
		ok=1
		for n in uzai-secp256k1.dll uzai-datachannel.dll; do
			a=$(sha256sum "$t/$n" | cut -c1-64); b=$(sha256sum "$PROJ/assets/net/$n" | cut -c1-64)
			[ "$a" = "$b" ] && echo "$n: eingecheckte Datei stimmt ($a)" || { echo "$n: eingecheckt $b, gebaut $a"; ok=0; }
		done
		rm -rf "$t"
		[ "$ok" = 1 ]
		;;
	*)
		holen
		bauen windows "$PROJ/assets/net"
		bauen linux "$PROJ/build/netzlibs-linux"
		for n in uzai-secp256k1.dll uzai-datachannel.dll; do
			nachweis "$PROJ/assets/net/$n"
			echo "$n  $(stat -c %s "$PROJ/assets/net/$n") Byte  SHA-256 $(sha256sum "$PROJ/assets/net/$n" | cut -c1-64)"
		done
		;;
esac
