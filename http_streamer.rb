#!/usr/bin/env ruby
#
# Copyright (c) 2009 Carson McDonald
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 2
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

require 'thread'
require 'logger'
require 'yaml'
require 'pp'
require 'ftools'
require 'open3'

require 'rubygems'
require 'net/scp'
require 'net/ftp'
require 'right_aws'

def log_setup(config)
  if config['log_type'] == 'FILE'
    log = Logger.new(config['log_file'])
  else
    log = Logger.new(STDOUT)
  end

  case config['log_level']
    when 'DEBUG'
      log.level = Logger::DEBUG
    when 'INFO'
      log.level = Logger::INFO
    when 'WARN'
      log.level = Logger::WARN
    when 'ERROR'
      log.level = Logger::ERROR
    else
      log.level = Logger::DEBUG
  end

  return log
end

def config_sanity_check(config)
# TODO
end

def transfer_file(log, config, source_file, destination_file)
   transfer_config = config[config['transfer_profile']]

   case transfer_config['transfer_type']
     when 'copy'
       File.copy(source_file, transfer_config['directory'] + '/' + destination_file)
     when 'ftp'
       Net::FTP.open(transfer_config['remote_host']) do |ftp|
         ftp.login(transfer_config['user_name'], transfer_config['password'])
         files = ftp.chdir(transfer_config['directory'])
         ftp.putbinaryfile(source_file, destination_file)
       end
     when 'scp'
       if transfer_config.has_key?('password')
         Net::SCP.upload!(transfer_config['remote_host'], transfer_config['user_name'], source_file, transfer_config['directory'] + '/' + destination_file, :password => transfer_config['password'])
       else
         Net::SCP.upload!(transfer_config['remote_host'], transfer_config['user_name'], source_file, transfer_config['directory'] + '/' + destination_file)
       end
     when 's3'
       s3 = RightAws::S3Interface.new(transfer_config['aws_api_key'], transfer_config['aws_api_secret'])

       content_type = source_file =~ /.*\.m3u8$/ ? 'application/x-mpegURL' : 'video/MP2T'

       log.debug("Content type: #{content_type}")

       s3.put(transfer_config['bucket_name'], "#{transfer_config['key_prefix']}/#{destination_file}", File.open(source_file), {'x-amz-acl' => 'public-read', 'content-type' => content_type})
     else
       log.error("Unknown transfer type: #{transfer_config['transfer_type']}")
   end

   File.unlink(source_file)
end

def create_and_transfer_multirate_index(log, config)
  File.open("tmp.index.multi.m3u8", 'w') do |index_file|
    index_file.write("#EXTM3U\n")

    config['encoding_profile'].each do |encoding_profile_name|
      encoding_profile = config[encoding_profile_name]
      index_file.write("#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=#{encoding_profile['bandwidth']}\n")
      index_name = "%s_%s.m3u8" % [config['index_prefix'], encoding_profile_name]
      index_file.write("#{config['url_prefix']}#{index_name}\n")
    end
  end

  transfer_file(log, config, "tmp.index.multi.m3u8", "#{config["index_prefix"]}_multi.m3u8")
end

def create_index(log, index_segment_count, segment_duration, output_prefix, encoding_profile, http_prefix, first_segment, last_segment, stream_end)
  log.debug('Creating index');

  File.open("tmp.index.#{encoding_profile}.m3u8", 'w') do |index_file|
    index_file.write("#EXTM3U\n")
    index_file.write("#EXT-X-TARGETDURATION:#{segment_duration}\n")
    index_file.write("#EXT-X-MEDIA-SEQUENCE:#{last_segment >= index_segment_count ? last_segment-(index_segment_count-1) : 1}\n")

    first_segment.upto(last_segment) do | segment_index |
      if segment_index > last_segment - index_segment_count
        index_file.write("#EXTINF:#{segment_duration},\n")
        index_file.write("#{http_prefix}#{output_prefix}_#{encoding_profile}-%05u.ts\n" % segment_index)
      end
    end

    index_file.write("#EXT-X-ENDLIST") if stream_end
  end

  log.debug('Done creating index');
end

def run_transfer(log, config, value)
  (first_segment, last_segment, stream_end, encoding_profile) = value.strip.split(%r{,\s*})
  create_index(log, config['index_segment_count'], config['segment_length'], config['segment_prefix'], encoding_profile, config['url_prefix'], first_segment.to_i, last_segment.to_i, stream_end.to_i == 1)

  # Transfer the index
  final_index = "%s_%s.m3u8" % [config['index_prefix'], encoding_profile]
  transfer_file(log, config, "tmp.index.#{encoding_profile}.m3u8", "#{final_index}")

  # Transfer the video stream
  video_filename = "#{config['temp_dir']}/#{config['segment_prefix']}_#{encoding_profile}-%05u.ts" % last_segment.to_i
  dest_video_filename = "#{config['segment_prefix']}_#{encoding_profile}-%05u.ts" % last_segment.to_i
  transfer_file(log, config, video_filename, dest_video_filename)
end

def execute_ffmpeg_and_segmenter(log, transfer_queue, command, encoding_profile, encoding_pipes)
  log.debug("Executing: #{command}")

  Open3.popen3(command) do |stdin, stdout, stderr, test|
    encoding_pipes << stdin if encoding_pipes != nil

    stderr.each("\r") do |line|
      if line =~ /segmenter: (.*)/i
        log.debug("Segment command #{encoding_profile}: *#{$1}*")
        transfer_queue << $1
      end

      if line =~ /ffmpeg/i 
        log.debug("Encoder #{encoding_profile}: #{line}")
      end

      if line =~ /error/i
        log.error("Encoder #{encoding_profile}: #{line}")
      end
    end
  end

  log.debug("Return code from #{encoding_profile}: #{$?}")

  raise CommandExecutionException if $?.exitstatus != 0
end

def process_master_encoding(log, config, encoding_pipes)
  command = config['source_command'] % config['input_location']

  log.debug("Executing: #{command}")

  stderr_thread = nil

  Open3.popen3(command) do |stdin, stdout, stderr, test|
    stderr_thread = Thread.new do
      stderr.each("\r") do |line|
        if line =~ /ffmpeg/i 
          log.debug("Master encoder: #{line}")
        end

        if line =~ /error/i
          log.error("Master encoder: #{line}")
        end
      end
    end

    while !stdout.eof do 
      output = stdout.read(1024 * 100)
      encoding_pipes.each do |out|
        out.print output
      end
    end
  end

  stderr_thread.join

  log.debug("Return code from master encoding: #{$?}")

  encoding_pipes.each do |out|
    out.close
  end

  raise CommandExecutionException if $?.exitstatus != 0
end

def process_encoding(log, config, transfer_queue, encoding_profile, input_location, encoding_pipes)
  encoding_config = config[encoding_profile]

  command_ffmpeg = encoding_config['ffmpeg_command'] % [input_location, config['segmenter_binary'], config['segment_length'], config['temp_dir'], config['segment_prefix'] + '_' + encoding_profile, encoding_profile]

  begin
    execute_ffmpeg_and_segmenter(log, transfer_queue, command_ffmpeg, encoding_profile, encoding_pipes)
  rescue
    log.error("Encoding error: " + $!)
  end
end

# **************************************************************
#
# Main
#
# **************************************************************

if ARGV.length != 1
  puts "Usage: http_streamer.rb <config file>"
  exit 1
end

config = YAML::load( File.open(ARGV[0]) )

config_sanity_check(config)

log = log_setup(config)

log.info('HTTP Streamer started')

transfer_queue = Queue.new

transfer_thread = Thread.new do
  log.info('Transfer thread started');
  while (value = transfer_queue.pop)
    break if value == 'quit'
    log.info('Transfer initiated');
    log.debug(value)

    begin
      run_transfer(log, config, value)
    rescue
      log.error("Error running transfer: " + $!)
    end

    log.info('Transfer done');
  end
  log.info('Transfer thread terminated');
end

encoding_threads = []

if config['encoding_profile'].is_a?(Array)
  create_and_transfer_multirate_index(log, config)
  
  encoding_pipes = []

  config['encoding_profile'].each do |profile_name|
    encoding_threads << Thread.new do
      log.info('Encoding thread started: ' + profile_name);

      process_encoding(log, config, transfer_queue, profile_name, '-', encoding_pipes)

      log.info('Encoding thread terminated: ' + profile_name);
    end
  end

  encoding_threads << Thread.new do
    log.info('Master encoding thread started');

    begin
      process_master_encoding(log, config, encoding_pipes)
    rescue
      log.error("Master encoding error: " + $!)

      encoding_pipes.each do |out|
        out.close
      end
    end

    log.info('Master encoding thread terminated');
  end
else
  encoding_threads << Thread.new do
    log.info('Encoding thread started');

    process_encoding(log, config, transfer_queue, config['encoding_profile'], config['input_location'], nil)
    
    log.info('Encoding thread terminated');
  end
end

encoding_threads.each do |encoding_thread|
  encoding_thread.join
end
transfer_queue << 'quit'
transfer_thread.join

log.info('HTTP Streamer terminated')
