#!/usr/bin/env make -R
# Expects to be in /var/lib/zkreplay

default:
	echo "Please specify one of demos, stats, summaries, or a more specific target."
	false

ZKDIR:=/var/lib/zkreplay/Zero-K

SHELL:=/bin/bash

# XXX: Assumes that ZKDIR contains exactly one hyphen, and that the spring version is separated by another hyphen.
LATESTSPRING:=$(shell ls -1d $(ZKDIR)/engine/linux64/* | sort --key=1,2d --key=3n --field-separator=- | tail -1)
ifndef PRDOWNLOADER
#ifeq ($(LATESTSPRING),104.0.1-1477-g8ecf38a)
# Workaround for 104.0.1-1477-g8ecf38a's pr-downloader failing to --download-game
PRDOWNLOADER:=$(ZKDIR)/engine/linux64/104.0.1-1435-g79d77ca/pr-downloader
#else
#PRDOWNLOADER:=$(LATESTSPRING)/pr-downloader
#endif
endif

-include demos/index.mk
# BATTLEIDS is the set of battle IDs that we can get from the index
# ALLBATTLEIDS is BATTLEIDS, plus what we already have locally.
ALLBATTLEIDS:=$(BATTLEIDS) $(shell find demos -mindepth 1 -type d | sed 's_^.*/\([^\/*]\)_\1_' | grep -vxFf demos/exclude.txt)
REPLAYS:=$(addprefix demos/,$(addsuffix /replay.sdfz, $(ALLBATTLEIDS)))
RDETAILS:=$(addprefix demos/,$(addsuffix /detail.html, $(ALLBATTLEIDS)))
EVENTS:=$(addprefix stats/,$(addsuffix /events.log, $(ALLBATTLEIDS)))
EVENTDEPS:=$(addprefix demos/,$(addsuffix /events.log.deps, $(ALLBATTLEIDS)))
SUMMARIES:=$(addprefix summaries/,$(addsuffix /summary.json, $(ALLBATTLEIDS)))

demos: demos/index.mk fetch-replays $(REPLAYS) $(RDETAILS)

stats: $(EVENTS)

summaries: $(SUMMARIES) summaries/all.json

.PHONY: default demos stats summaries fetch-replays demos/index.mk
.SECONDARY:

fetch-replays: $(REPLAYS) $(RDETAILS)

# XXX: Automatic regeneration disabled until we work out how to throttle this
demos/index.mk.in:
	seq 0 40 800 | xargs -n1 -d \\n -I {} curl -s "https://zero-k.info/Battles?Title=MM+&Map=&PlayersFrom=2&PlayersTo=2&Age=0&Mission=2&Bots=2&Rank=8&Victory=0&Offset={}" | sed -n "s_^.*<a href='/Battles/Detail/\([0-9]\+\)'.*\$$_\1_p" | paste -d\  -s - | sed 's/^/BATTLEIDS:=/' > demos/index.mk.tmp
	mv -f demos/index.mk.tmp demos/index.mk.in

# If we can't find a zero-k.info URL to download a map from, instead look for 'Manual downloads:', and if the next line has a link, use that.
# This is exactly as fragile as it sounds, but it seems to work for all existing maps, and new maps seem to have a zk link anyway.
define mapmanualfallback
/Manual downloads:/{
n
s_^.*<a href='\([^']\+\)'.*$$_\1_p
}
endef

define getspringversion
/Engine version:/{
n
n
n
s_^ *\([-a-zA-Z0-9_.]\+\)$$_\1_p
}
endef

define getzkversion
/Game version:/{
n
n
n
s_^ *\([-a-zA-Z0-9_. ]\+\)$$_\1_p
}
endef

export getspringversion
export getzkversion
# This tries to build a dependency file once we have the battle detail available.
demos/%/events.log.deps: demos/%/detail.html
	MAPID=$$(sed -n 's_^.*<a href="/Maps/Detail/\([0-9]\+\)".*$$_\1_p' "$<") && echo "demos/$*/replay.sdfz: | maps/$${MAPID}.html" > "$@.tmp"
	SPRINGVERSION=$$(sed -n "$${getspringversion}" demos/$*/detail.html) && echo "demos/$*/replay.sdfz: | $(ZKDIR)/engine/linux64/$${SPRINGVERSION}/spring-headless" >> "$@.tmp"
	ZKVERSION=$$(sed -n "$${getzkversion}" demos/$*/detail.html) && echo "$${ZKVERSION}" && echo "demos/$*/replay.sdfz: | games/$$(sed 's/ /\\ /g' <<< "$${ZKVERSION}")" >> "$@.tmp"
	mv -f "$@.tmp" "$@"

# Index for rapid downloader.
$(ZKDIR)/rapid/repos.springrts.com/zk/versions.gz:
	$(PRDOWNLOADER) --filesystem-writepath "$(ZKDIR)"

# Download different Zero-K versions.
games/%: | $(ZKDIR)/rapid/repos.springrts.com/zk/versions.gz
	mkdir -p games
	ZKHASH=$$(zgrep -F "$*" "$(ZKDIR)/rapid/repos.springrts.com/zk/versions.gz" | grep '^zk:git:' | cut -f2 -d, ) && echo && echo "Downloading "$*" hash $${ZKHASH}..." && echo && $(PRDOWNLOADER) --download-game "$*" --filesystem-writepath "$(ZKDIR)" && test -e "$(ZKDIR)/packages/$${ZKHASH}.sdp" && ln -sf "$(ZKDIR)/packages/$${ZKHASH}.sdp" "$@"

# Download different springrts versions.
# pr-downloader variant reverted until it can be reworked to fit the zk directory structure?
#$(ZKDIR)/engine/linux64/%/spring-headless:
#	$(PRDOWNLOADER) --download-engine "spring $* maintenance" --filesystem-writepath "$(ZKDIR)"

$(ZKDIR)/engine/linux64/%/spring-headless:
	WORK=$$(mktemp -d) && echo; echo "=== Attempting to fetching spring engine version $*" ===; echo; curl -s "https://springrts.com/dl/buildbot/default/maintenance/$*/linux64/spring_%7bmaintenance%7d$*_minimal-portable-linux64-static.7z" > "$${WORK}/$*.7z" && cd "$(ZKDIR)/engine/linux64" && mkdir "$*" && cd "$*" && 7z x "$${WORK}/$*.7z" && chmod -R o-w . && chmod -R g+rX . ; rm -rf "$${WORK}"; test -x "$(ZKDIR)/engine/linux64/$*/spring-headless"

# Download different maps.
export mapmanualfallback
maps/%.html:
	BASE=$$(pwd) && if [ ! -f "maps/$*.html" ]; then echo; echo "=== Attempting to fetch map $*... ==="; echo; cd maps/ && curl -s -R "https://zero-k.info/Maps/Detail/$*" > "$*.html" && cd "$(ZKDIR)/maps" && (sed -n "s_^.*<a href='\(https://zero-k.info/content/maps/[^']\+.sd[7z]\)'.*\$$_\1_p" "$${BASE}/maps/$*.html" ; sed -n "$${mapmanualfallback}" "$${BASE}/maps/$*.html") | head -1 | xargs -n1 -d \\n curl -s -O -R; fi || (echo "FAILED getting map ID $*" ; rm -f "$${BASE}/$@" ; mv -f "$${BASE}/maps/$*.html" "$${BASE}/maps/FAILED.$*.html" ; false)

# Finally, link replays to the Zero-K version, engine version, and map that it depends on.
-include $(EVENTDEPS)

demos/%/detail.html:
	mkdir -p "$(dir $@)" && cd "$(dir $@)" && curl -s "https://zero-k.info/Battles/Detail/$*" > detail.html

# replay.sdfz is a symlink to the full replay with a more accessible name
# This recipe downloads the replay file as part of the process
demos/%/replay.sdfz: | demos/%/detail.html
	# Scrape the battle detail page for the "Manual download" replay link, extract it, urlencode the filename, reconstruct the full URL, download it, then symlink replay.sdfz to the result
	mkdir -p "$(dir $@)" && cd "$(dir $@)" && cat "detail.html" | sed -n "s_^.*<a href='/replays/\(.*\.sdfz\)'>Manual download</a>.*\$$_\1_p" | tr -d \\n | jq -sRr @uri | sed 's_^.*$$_https://zero-k.info/replays/&_' | xargs -n1 -d \\n curl -s -O -R && ls -1t *.sdfz | grep -vx replay.sdfz | head -1 | xargs -n1 -d \\n -I{} ln -sf {} replay.sdfz


# Process the replay
stats/%/spring.log stats/%/events.log: demos/%/replay.sdfz
	mkdir -p "$(dir $@)"
	mkdir -p "$(ZKDIR)/LuaUI/Logs/replay_stats/$*/"
	set -o pipefail && WORK=$$(mktemp -d) && trap 'rm -rf "$${WORK}"' EXIT && SPRINGVERSION=$$(sed -n "$${getspringversion}" demos/$*/detail.html) && cat "$(ZKDIR)/springsettings.cfg" <(echo ZKHeadlessReplay=$*) > "$${WORK}/springsettings.$*.cfg" && /usr/bin/time -v "$(ZKDIR)/engine/linux64/$${SPRINGVERSION}/spring-headless" -write-dir "$(ZKDIR)" -config "$${WORK}/springsettings.$*.cfg" $< 2>&1 > stats/$*/spring.log
	test -e "$(ZKDIR)/LuaUI/Logs/replay_stats/$*/events.log" && mv -f "$(ZKDIR)/LuaUI/Logs/replay_stats/$*/events.log" "stats/$*/events.log"

# Postprocess the events from the replay
summaries/%/summary.json: stats/%/events.log postprocess.py
	mkdir -p "$(dir $@)"
	python3 postprocess.py "$<" "$*" > "$@".tmp
	mv -f "$@".tmp "$@"

summaries/all.json: $(SUMMARIES)
	( echo -n [ && cat summaries/*/summary.json | paste -s -d, - && echo -n ] ) > "$@.tmp"
	mv -f --backup=numbered "$@.tmp" "$@"
