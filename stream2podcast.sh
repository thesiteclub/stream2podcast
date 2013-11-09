#! /bin/bash

DEBUG=0
YEAR="`date +%Y`"
VERSION=1
CONFIG=~/conf/stream2podcast.conf
RSS_ONLY=0
LOG=~/log/stream2podcast.`date +%F`.log

# TODO: Define insane values for all important variables from the config file.
# Check to ensure all are set. Set sane defaults for the rest.

################################################################################

log () {
	echo `date +%T` "$@"
}

################################################################################

dep_check () {
	for APP in streamripper eyeD3; do
		which $APP > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			log $APP 'could not be found. Please install it.'
			exit 1
		fi
	done
}

################################################################################

rip_stream () {
	log 'Recording to' $RSS_DIR/$STREAM_FILE

	 streamripper "$STREAM_URL" --quiet -o always -A -a $RSS_DIR/$STREAM_FILE \
	-l $STREAM_LENGTH

	if [ $? -ne 0 ]; then
		log 'Stream ripping failed. I quit.'
		exit 1
	fi

	# Streamripper creates .cue files which we don't want nor need
	/bin/rm -f $RSS_DIR/*.cue
}

################################################################################

add_tags () {
	log 'Adding ID3 tags to' $RSS_DIR/$STREAM_FILE

	eyeD3 --no-color --add-image="${IMAGE}:OTHER" -Y $YEAR \
	-a "$STREAM_AUTHOR" -G Podcast $RSS_DIR/$STREAM_FILE > /dev/null

	if [ $? -ne 0 ]; then
		log 'ID3 tagging failed. I quit.'
		exit 1
	fi
}

################################################################################

build_rss () {
	log 'Building rss feed'
	# Replace old rss feed with new header
	(
		echo '<?xml version="1.0"?>'
		echo '<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">'
		echo '<channel>'
		echo '<title>'${RSS_TITLE}'</title>'
		echo '<link>'${RSS_URL}'</link>'
		echo '<description>'${RSS_DESCRIP}'</description>'
		echo '<language>en-us</language>'
		echo '<copyright></copyright>'
		echo '<itunes:image href="'$IMAGE'" />'
		echo '<lastBuildDate>'`date`'</lastBuildDate>'
		echo '<webMaster>'$RSS_EMAIL'</webMaster>'
		echo '<ttl>1</ttl>'
	) > $RSS_DIR/rss

	# Add entries for each file
	for FILE in `ls -1 ${RSS_DIR}/*.mp3`; do
		FILE_DATE="`date -r $FILE`"
		FILE_NAME="`/bin/basename ${FILE}`"
		FILE_SIZE=`stat -c '%s' $FILE`
		(
			echo '<item>'
			echo '<title>'${FILE_NAME}'</title>'
			echo '<pubDate>'${FILE_DATE}'</pubDate>'
			echo '<itunes:duration>2:03:00</itunes:duration>'
			echo '<itunes:author>'$STREAM_AUTHOR'</itunes:author>'
			echo '<guid>'${FILE_NAME}'</guid>'
			echo '<enclosure url="'${RSS_URL}/${FILE_NAME}'" length="'${FILE_SIZE}'" type="audio/mpeg"/>'
			echo '</item>'
		) >> $RSS_DIR/rss
	done

	echo '</channel>' >> $RSS_DIR/rss
	echo '</rss>' >> $RSS_DIR/rss
}

################################################################################

cleanup_recordings () {
	log 'Deleting old recordings'

	# Delete old files
	if [ $MAX_AGE -gt 0 ]; then
		find $RSS_DIR -maxdepth 1 -name '*.mp3' -ctime +$MAX_AGE -type f | \
			xargs /bin/rm
	fi

	# Delete files beyond $MAX_NUM. Sorted by name. Should this by date?
	if [ $MAX_NUM -gt 0 ]; then
		find $RSS_DIR -maxdepth 1 -name '*.mp3' -type f | sort -r | \
			tail -n +$MAX_NUM | xargs /bin/rm
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
		CONFIG=$OPTARG
		;;
	'D')
		DEBUG=1
		;;
	'r')
		RSS_ONLY=1
		;;
	'V')
		echo $VERSION
		exit 0
		;;
	'?')
		usage
		exit 1
		;;
	esac
done

if [ ! -e $CONFIG ]; then
	log "Config file ($CONFIG) does not exist. I quit."
	exit 1
fi

source $CONFIG

if [ $DEBUG -eq 0 ]; then
	exec >> $LOG 2>&1
fi

log 'stream2podcast started'

if [ ! -d $RSS_DIR ]; then
	log "RSS_DIR ($RSS_DIR) does not exist. I quit."
	exit 1
fi

# Check for dependancies
dep_check

if [ $RSS_ONLY -eq 0 ]; then
	# Record stream
	rip_stream

	# Set ID3 tags, including image
	add_tags
fi

cleanup_recordings

# Create RSS feed
build_rss

log 'Finished at' `date`
