stream2podcast
==============

Stream2podcast is a shell script wrapper for streamripper designed to run from cron.

What does all this this mean to you? Stream2podcast will record your favorite streaming radio show and share it as a podcast.
For example, you could record a late night show and listen to it on your iPhone (or other podcast client) during your morning commute. 

Before trying to run stream2podcast you should copy and then edit the config file to work in your environment.
By default stream2podcast will look for a config file at ~/stream2podcast.conf but you can specify another config file with the -c option.

Stream2podcast will run happily from the command line but you really should set it up in a cron job so you can get on with your life.
For example:
0 20 * * 6  ~/stream2podcast.sh -c ~/prairiehome.conf
