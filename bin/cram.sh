#!/bin/bash
# starts the optimizer

ME=`basename $0`
BINDIR=`dirname $0`
BINDIR=${BINDIR:-.}
JSDIR="$BINDIR"/../js
TMPDIR=$(mktemp -t cram -d)

# optimization for jsrun.sh
JSTMP=$(mktemp -t cram)
export JSTMP

USAGE="$ME -r root_module_id -e path_to_js_engine -c config_file"

COLLECTOR="$BINDIR"/collector.sh
BUILDER="$BINDIR"/builder.sh
JSRUN="$BINDIR/jsrun.sh"

# parse options

for arg in "$@"
do

	case "$arg" in

		-r)
			shift
			ROOTID=$1
			shift
		;;

		-e|--engine)
			shift
			JSENGINE=$1
			export JSENGINE
			shift
		;;

		-c|--config)
			shift
			CONFIG=$(echo $(cat "$1")) #echo removes line feeds!
			shift
		;;

		-h|--help)
			echo "$USAGE"
			exit 0
		;;

	esac

done

if [[ -n "$CONFIG" ]];then
	# FIXME: Need a better way to extract json params from config
	DESTURL=$("$BINDIR/jsrun.sh" "var c=$CONFIG; print(c.destUrl);")
fi

# all shell-driven js engines must have at least print() and load()
# the following var holds name=bool pairs of other js engine
# capabilities

ENGINECAPS=$("$JSENGINE" "$JSDIR/jsEngineCaps.js")

echo "js engine capabilites = $ENGINECAPS"

if [[ ! "$ENGINECAPS" =~ hasJson=true  ]]; then
	#rhino needs this, jsc does not
	JSON="$JSDIR"/json2.js
fi

export JSRUN ENGINECAPS JSON BINDIR JSDIR CONFIG DESTURL

# HACK: Not great, but we end up with back-to-back arrays, so replace ][ with
# a comma to form a single array
MODULEINFO=$("$COLLECTOR" "$ROOTID")
RV=$?
if [ $RV -ne 0 ];then
	exit $RV
else
	MODULEINFO=${MODULEINFO//][/,}
fi

echo "moduleinfo =" "$MODULEINFO"

# some js engines can't fetch text resources (jsc)
# so we have to prefetch them into a js module

if [[ ! "$ENGINECAPS" =~ hasReadFile=true ]]; then

	# create a temporary prefetch loader javascript module
	FETCHER="$TMPDIR"/prefetcher.js
	RESOLVER="$JSDIR"/Resolver.js
echo "prefetcher stub generated: $FETCHER"

	# append a copy of the base prefetchLoader module
	cat "$JSDIR"/prefetcher.js > "$FETCHER"

	# prefetch all modules and resources as function calls into prefetch loader
	URLS=$("$JSRUN" "var resolver = new Resolver('', $CONFIG); print(fetcher.extractUrls($MODULEINFO, resolver));" "$FETCHER" "$RESOLVER")

	# for each module/resource: fetcher.store("text data");
	ORIGIFS=$IFS
	IFS=","
	for URL in $URLS
	do
		JSCODE=$(cat "$URL" | "$BINDIR"/jsescape.sh)
		echo "fetcher.store(\"$URL\", \"$JSCODE\");" >> "$FETCHER"
	done
	IFS=$ORIGIFS

else

	FETCHER="$JSDIR"/readFileFetcher.js

fi

export FETCHER

# we're ready to build!

"$BUILDER" "$MODULEINFO"