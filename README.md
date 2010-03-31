iPhone HTTP Streaming Server
============================

For a detailed overview see the [http live video segmenter](http://www.ioncannon.net/projects/http-live-video-stream-segmenter-and-distributor/) page.

## DESCRIPTION

This project is an attempt to make it easier to set up a live streaming server using Apple's HTTP streaming protocol.

The project includes a ruby script and a C program that use FFMpeg to encode and segment an input video stream in the correct format for use with the HTTP streaming protocol.

## FEATURES

- Creates both single and variable bitrate outputs
- Transfer encoded segments via copy, FTP, SCP or transfer to AWS S3
- Sending the INT signal to the segmenter process will cause it to terminate gracefully 

## REQUIREMENTS

FFMpeg is the primary external requirement for the ruby script. The segmenter needs libavformat to compile and that can be obtained by installing FFMpeg. The script also needs the following gems installed if you want to be able to use SCP or S3 as transfer options:

- *Net::SCP*
	See http://net-ssh.rubyforge.org/ for more information. To intall run gem install net-scp

- *RightScale AWS*
	See http://rubyforge.org/projects/rightscale for more information. To install run gem install right_aws

## INSTALL

You will need to compile the segmenter first. Assuming that you have all the needed libraries installed this is as easy as doing a make in the root directory. 

You may copy the script and the segmenter binary to any location you want. You will need to let the script know where to find the segmenter binary in the configuration file.

## CONFIGURATION

A quick overview of the configuration options:

- *temp_dir* 
	Where the script will put segments before they are transfered to their final destination
- *segment_prefix* 
	The prefix added to each stream segment 
- *index_prefix* 
	The prefix added to the index
- *log_type* 
	The logging type to use. Options are: STDOUT, FILE
- *log_file* 
	If using the FILE logging type where to put the log file
- *log_level* 
	The level of logging to output. Options are: DEBUG, INFO, WARN, ERROR
- *input_location* 
	Where the origin video is coming from. This can be a file, a pipe, a device or any other media that is consumable by FFMpeg or the given source consumer. See the source_command option as well.
- *segment_length* 
	The video segment length in seconds
- *url_prefix* 
	This is the URL where the stream (ts) files will end up
- *index_segment_count* 
	How many segments to keep in the index
- *source_command* 
	The command used to push video the encoders
- *segmenter_binary* 
	The location of the segmenter
- *encoding_profile* 
	Specifies what encoding profile to use. It can be either a single entry, 'ep_128k', or an array, [ 'ep_128k', 'ep_386k', 'ep_512k' ], for multi-bitrate outputs.
- *transfer_profile* 
	The transfer profile to use after each segment is produced

Encoding profiles are given a name and have two options following that name:

- *ffmpeg_command*
	The command to use for this encoding profile
- *bandwidth* 
	The amount of bandwidth required to transfer this encoding

Transfer profiles are given a name in the same way encoding profiles are and have various options following their name.

### For S3 based transfers:
- *transfer_type*
	Must be set to 's3'
- *bucket_name* 
	The S3 bucket to put the segments in
- *key_prefix* 
	A prefix to attach to the start of each segment stream0001
- *aws_api_key* 
	The AWS api key for S3
- *aws_api_secret* 
	The AWS api secret for S3

### For FTP based transfers:
- *transfer_type*
	Must be set to 'ftp'
- *remote_host*
	The remote host to ftp the segments to
- *user_name*
	The user to use to log into the ftp site
- *password*
	The password to use to log into the ftp site
- *directory*
	The directory to change to before starting the ftp upload

### For SCP based transfers:
- *transfer_type*
	Must be set to 'scp'
- *remote_host*
	The host to scp to
- *user_name*
	The user to use in the scp
- *password*
	The password to use for scp. This is optional, if it isn't provided the scp will be done using a previously generated private key.
- *directory*
	The directory to change to before uploading the segment

### For copy based transfers:
- *transfer_type*
	Must be set to 'copy'
- *directory*
	The destination directory to copy the segment to

## LICENSE

Copyright (c) 2009 Carson McDonald

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License version 2
as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
