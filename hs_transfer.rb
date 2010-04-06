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

require 'rubygems'

class HSTransfer

  QUIT='quit'
  MULTIRATE_INDEX='mr_index'

  def self.init_and_start_transfer_thread(log, config)
    hstransfer = HSTransfer.new(log, config)
    hstransfer.start_transfer_thread
    return hstransfer
  end

  def <<(transfer_item)
    @transfer_queue << transfer_item
  end

  def stop_transfer_thread
    @transfer_queue << QUIT
    @transfer_thread.join
  end

  def initialize(log, config)
    @transfer_queue = Queue.new
    @log = log
    @config = config
  end

  def start_transfer_thread
    @transfer_thread = Thread.new do
      @log.info('Transfer thread started');
      while (value = @transfer_queue.pop)
        @log.info("Transfer initiated with value = *#{value}*");

        if value == QUIT
          break
        elsif value == MULTIRATE_INDEX
          create_and_transfer_multirate_index
        else
          begin
            create_index_and_run_transfer(value)
          rescue
            @log.error("Error running transfer: " + $!)
          end
        end

        @log.info('Transfer done');
      end
      @log.info('Transfer thread terminated');
    end
  end

  def self.can_scp
    begin
      require 'net/scp'
      return true
    rescue LoadError
      return false
    end
  end

  def self.can_ftp
    begin
      require 'net/ftp'
      return true
    rescue LoadError
      return false
    end
  end

  def self.can_s3
    begin
      require 'right_aws'
      return true
    rescue LoadError
      return false
    end
  end

  private

  def create_and_transfer_multirate_index
    @log.debug('Creating multirate index')
    File.open("tmp.index.multi.m3u8", 'w') do |index_file|
      index_file.write("#EXTM3U\n")

      @config['encoding_profile'].each do |encoding_profile_name|
        encoding_profile = @config[encoding_profile_name]
        index_file.write("#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=#{encoding_profile['bandwidth']}\n")
        index_name = "%s_%s.m3u8" % [@config['index_prefix'], encoding_profile_name]
        index_file.write("#{@config['url_prefix']}#{index_name}\n")
      end
    end

    @log.debug('Transfering multirate index')
    transfer_file("tmp.index.multi.m3u8", "#{@config["index_prefix"]}_multi.m3u8")
  end

  def create_index(index_segment_count, segment_duration, output_prefix, encoding_profile, http_prefix, first_segment, last_segment, stream_end)
    @log.debug('Creating index');

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

      index_file.write("#EXT-X-ENDLIST\n") if stream_end
    end

    @log.debug('Done creating index');
  end

  def create_index_and_run_transfer(value)
    (first_segment, last_segment, stream_end, encoding_profile) = value.strip.split(%r{,\s*})
    create_index(@config['index_segment_count'], @config['segment_length'], @config['segment_prefix'], encoding_profile, @config['url_prefix'], first_segment.to_i, last_segment.to_i, stream_end.to_i == 1)

    # Transfer the index
    final_index = "%s_%s.m3u8" % [@config['index_prefix'], encoding_profile]
    transfer_file("tmp.index.#{encoding_profile}.m3u8", "#{final_index}")

    # Transfer the video stream
    video_filename = "#{@config['temp_dir']}/#{@config['segment_prefix']}_#{encoding_profile}-%05u.ts" % last_segment.to_i
    dest_video_filename = "#{@config['segment_prefix']}_#{encoding_profile}-%05u.ts" % last_segment.to_i
    transfer_file(video_filename, dest_video_filename)
  end

  def transfer_file(source_file, destination_file)
     transfer_config = @config[@config['transfer_profile']]

     case transfer_config['transfer_type']
       when 'copy'
         File.copy(source_file, transfer_config['directory'] + '/' + destination_file)
       when 'ftp'
         require 'net/ftp'
         Net::FTP.open(transfer_config['remote_host']) do |ftp|
           ftp.login(transfer_config['user_name'], transfer_config['password'])
           files = ftp.chdir(transfer_config['directory'])
           ftp.putbinaryfile(source_file, destination_file)
         end
       when 'scp'
         require 'net/scp'
         if transfer_config.has_key?('password')
           Net::SCP.upload!(transfer_config['remote_host'], transfer_config['user_name'], source_file, transfer_config['directory'] + '/' + destination_file, :password => transfer_config['password'])
         else
           Net::SCP.upload!(transfer_config['remote_host'], transfer_config['user_name'], source_file, transfer_config['directory'] + '/' + destination_file)
         end
       when 's3'
         require 'right_aws'
         s3 = RightAws::S3Interface.new(transfer_config['aws_api_key'], transfer_config['aws_api_secret'])

         content_type = source_file =~ /.*\.m3u8$/ ? 'application/vnd.apple.mpegurl' : 'video/MP2T'

         @log.debug("Content type: #{content_type}")

         s3.put(transfer_config['bucket_name'], "#{transfer_config['key_prefix']}/#{destination_file}", File.open(source_file), {'x-amz-acl' => 'public-read', 'content-type' => content_type})
       else
         @log.error("Unknown transfer type: #{transfer_config['transfer_type']}")
     end

     File.unlink(source_file)
  end

end
