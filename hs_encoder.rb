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
require 'ftools'
require 'open3'

class HSEncoder

  def initialize(transfer_queue)
    @transfer_queue = transfer_queue
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

  def execute_ffmpeg_and_segmenter(log, command, encoding_profile, encoding_pipes)
    log.debug("Executing: #{command}")

    Open3.popen3(command) do |stdin, stdout, stderr, test|
      encoding_pipes << stdin if encoding_pipes != nil

      stderr.each("\r") do |line|
        if line =~ /segmenter: (.*)/i
          log.debug("Segment command #{encoding_profile}: *#{$1}*")
          @transfer_queue << $1
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

  def process_encoding(log, config, encoding_profile, input_location, encoding_pipes)
    encoding_config = config[encoding_profile]

    command_ffmpeg = encoding_config['ffmpeg_command'] % [input_location, config['segmenter_binary'], config['segment_length'], config['temp_dir'], config['segment_prefix'] + '_' + encoding_profile, encoding_profile]

    begin
      execute_ffmpeg_and_segmenter(log, command_ffmpeg, encoding_profile, encoding_pipes)
    rescue
      log.error("Encoding error: " + $!)
    end
  end

  def run_encoder(log, config)
    encoding_threads = []

    if config['encoding_profile'].is_a?(Array)
      hstransfer.create_and_transfer_multirate_index(log, config)
  
      encoding_pipes = []

      config['encoding_profile'].each do |profile_name|
        encoding_threads << Thread.new do
          log.info('Encoding thread started: ' + profile_name);

          process_encoding(log, config, profile_name, '-', encoding_pipes)

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

        process_encoding(log, config, config['encoding_profile'], config['input_location'], nil)
    
        log.info('Encoding thread terminated');
      end
    end

    encoding_threads.each do |encoding_thread|
      encoding_thread.join
    end
  end
end
