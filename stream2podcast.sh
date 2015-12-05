#! /bin/bash

DEBUG=0
YEAR=$(date +%Y)
VERSION=1
CONFIG=~/conf/stream2podcast.conf
RSS_ONLY=0
SOX_MP3_OK=0
LOG=~/log/stream2podcast.$(date +%F).log

# TODO: Define insane values for all important variables from the config file.
# Check to ensure all are set. Set sane defaults for the rest.

MAX_AGE=0
MAX_FILES=0

################################################################################

log () {
	echo "$(date +%T) $@"
}

################################################################################

dep_check () {
	local app=''
	for app in soxi streamripper eyeD3; do
		which "$app" > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			log "$app could not be found. Please install it."
			exit 1
		fi
	done

	# Check for MP3 support in sox/soxi
	# Unfortunately, it always returns 1, regardless of if it supports MP3.
	sox --help-format mp3 | grep 'Cannot find a format called'
	if [ $? -ne 0 ]; then
		SOX_MP3_OK=1
	fi
}

################################################################################

# Streamripper can't handle playlist (.m3u) files. These are usually just a list
# of URLs we can stream from. We will do our best to pick one from the list.

handle_m3u () {
	echo "$STREAM_URL" | grep '.m3u$' > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		return
	fi

	log "STREAM_URL is a .m3u playlist. Attempting to pick a URL from that list."
	local playlist=$(mktemp)
	curl -s "$STREAM_URL" -o "$playlist" > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		log "Fatal error: Could not download STREAM_URL ($STREAM_URL)."
		/bin/rm "$playlist"
		exit 1
	fi
	STREAM_URL=$(grep '^http' "$playlist" | tail -1)
	/bin/rm "$playlist"
}

################################################################################

rip_stream () {
	log "Recording to $RSS_DIR/$STREAM_FILE"

	 streamripper "$STREAM_URL" --quiet -o always -A -a "$RSS_DIR/$STREAM_FILE" \
	-l "$STREAM_LENGTH"

	# This failed when we got a 404 from the server. Perhaps streamripper
	# doesn't follow convention and use a non-zero exit code to indicate errors?
	# I'd really rather not have to parse stderr to see if we failed...
	#
	# error -5 [Could not connect to the stream. Try checking that the stream is
	# up and that your proxy settings are correct.]

	if [ $? -ne 0 ]; then
		log 'Stream ripping failed. I quit.'
		exit 1
	fi

	# Streamripper creates .cue files which we don't want nor need
	find "$RSS_DIR" -maxdepth 1 -name '*.cue' -print0 | xargs -0r /bin/rm
}

################################################################################

add_tags () {
	log "Adding ID3 tags to $RSS_DIR/$STREAM_FILE"

	eyeD3 --add-image="${IMAGE}:OTHER" -Y "$YEAR" \
	-a "$STREAM_AUTHOR" -G Podcast "$RSS_DIR/$STREAM_FILE" > /dev/null

	if [ $? -ne 0 ]; then
		log 'ID3 tagging failed. I quit.'
		exit 1
	fi
}

################################################################################

build_rss () {
	local file

	log 'Building rss feed'
	# Replace old rss feed with new header
	(
		echo '<?xml version="1.0"?>'
		echo '<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">'
		echo '<channel>'
		echo "<title>$RSS_TITLE</title>"
		echo "<link>$RSS_URL</link>"
		echo "<description>$RSS_DESCRIP</description>"
		echo '<language>en-us</language>'
		echo '<copyright></copyright>'
		echo "<itunes:image href='$IMAGE' />"
		echo "<lastBuildDate>$(date)</lastBuildDate>"
		echo "<webMaster>$RSS_EMAIL</webMaster>"
		echo '<ttl>1</ttl>'
	) > "$RSS_DIR/rss"

	# Add entries for each file
	# TODO: Convert this loop to use null terminated file names
	for file in $(find "$RSS_DIR" -maxdepth 1 -name '*.mp3' | sort -rg); do
		local file_date=$(date -r "$file")
		local file_name=$(basename "$file")
		local file_size=$(stat -c '%s' "$file")
		local file_duration=0:00:00

		if [ $SOX_MP3_OK -eq 1 ]; then
			file_duration=$(soxi -d "$file" 2>&1)
			if [ $? -eq 0 ]; then
				file_duration=$(echo "$file_duration" | tail -1)
			fi
		fi

		(
			echo '<item>'
			echo "<title>$file_name</title>"
			echo "<pubDate>$file_date</pubDate>"
			echo "<itunes:duration>2:03:00</itunes:duration>"
			echo "<itunes:author>$STREAM_AUTHOR</itunes:author>"
			echo "<guid>$file_name</guid>"
			echo "<enclosure url='$RSS_URL/$file_name' length='$file_size' type='audio/mpeg'/>"
			echo '</item>'
		) >> "$RSS_DIR/rss"
	done

	echo '</channel>' >> "$RSS_DIR/rss"
	echo '</rss>' >> "$RSS_DIR/rss"
}

################################################################################

cleanup_recordings () {
	log 'Deleting old recordings'

	# Delete old files
	if [ $MAX_AGE -gt 0 ]; then
		find "$RSS_DIR" -maxdepth 1 -name '*.mp3' -ctime +$MAX_AGE -type f -print0 | \
			xargs -0r /bin/rm
	fi

	# Delete files beyond $MAX_FILES. Sorted by name. Should this by date?
	if [ $MAX_FILES -gt 0 ]; then
		find "$RSS_DIR" -maxdepth 1 -name '*.mp3' -type f -print0 | sort -z | \
			cut -d '' -f 1-10 | xargs -0r /bin/rm
	fi
}

################################################################################

usage()
{
	echo "usage: stream2podcast.sh [options]"
	echo "	-c FILE	   Use FILE as the config file. Default is $CONFIG"
	echo '	-D		   Debug (log to stdout, not file)'
	echo '	-r		   Rebuild rss file'
	echo '	-V		   Version'
	exit 1
}

################################################################################

while getopts 'c:DrV' o; do
	case "$o" in
	'c')
		CONFIG="$OPTARG"
		;;
	'D')
		DEBUG=1
		;;
	'r')
		RSS_ONLY=1
		;;
	'V')
		echo "$VERSION"
		exit 0
		;;
	'?')
		usage
		exit 1
		;;
	esac
done

if [ ! -e "$CONFIG" ]; then
	log "Config file ($CONFIG) does not exist. I quit."
	exit 1
fi

source "$CONFIG"

if [ $DEBUG -eq 0 ]; then
	exec >> "$LOG" 2>&1
fi

log 'stream2podcast started'

if [ ! -d "$RSS_DIR" ]; then
	log "RSS_DIR ($RSS_DIR) does not exist. I quit."
	exit 1
fi

# Check for dependancies
dep_check

if [ $RSS_ONLY -eq 0 ]; then
	# If we are given a playlist, pick a URL from it
	handle_m3u

	# Record stream
	rip_stream

	# Set ID3 tags, including image
	add_tags
fi

cleanup_recordings

# Create RSS feed
build_rss

log "Finished at $(date)"
