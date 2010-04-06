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

require 'hs_transfer'

require 'thread'
require 'ftools'
require 'open3'

class HSEncoder

  def initialize(log, config, hs_transfer)
    @hs_transfer = hs_transfer
    @log = log
    @config = config
  end

  def start_encoding
    encoding_threads = []

    if @config['encoding_profile'].is_a?(Array)
      run_multirate_encoding( encoding_threads )
    else
      run_single_encoder( encoding_threads )
    end

    encoding_threads.each do |encoding_thread|
      encoding_thread.join
    end
  end

  def stop_encoding
    @log.info("Stoping encoder.")
    begin
      @stop_stdin.print 'q' if !@stop_stdin.nil?
    rescue
    end
  end

  private 

  def process_master_encoding(encoding_pipes)
    command = @config['source_command'] % @config['input_location']

    @log.debug("Executing: #{command}")

    stderr_thread = nil

    Open3.popen3(command) do |stdin, stdout, stderr|
      @stop_stdin = stdin
      stderr_thread = Thread.new do
        stderr.each("\r") do |line|
          if line =~ /ffmpeg/i 
            @log.debug("Master encoder: #{line}")
          end

          if line =~ /error/i
            @log.error("Master encoder: #{line}")
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

    @log.debug("Return code from master encoding: #{$?}")

    encoding_pipes.each do |out|
      out.close
    end

    raise CommandExecutionException if $?.exitstatus != 0
  end

  def execute_ffmpeg_and_segmenter(command, encoding_profile, encoding_pipes)
    @log.debug("Executing: #{command}")

    Open3.popen3(command) do |stdin, stdout, stderr|
      if encoding_pipes != nil
        encoding_pipes << stdin
      else
        @stop_stdin = stdin
      end

      stderr.each("\r") do |line|
        if line =~ /segmenter: (.*)/i
          @log.debug("Segment command #{encoding_profile}: *#{$1}*")
          @hs_transfer << $1
        end

        if line =~ /ffmpeg/i 
          @log.debug("Encoder #{encoding_profile}: #{line}")
        end
  
        if line =~ /error/i
          @log.error("Encoder #{encoding_profile}: #{line}")
        end
      end
    end

    @log.debug("Return code from #{encoding_profile}: #{$?}")

    raise CommandExecutionException if $?.exitstatus != 0
  end

  def process_encoding(encoding_profile, input_location, encoding_pipes)
    encoding_config = @config[encoding_profile]

    command_ffmpeg = encoding_config['ffmpeg_command'] % [input_location, @config['segmenter_binary'], @config['segment_length'], @config['temp_dir'], @config['segment_prefix'] + '_' + encoding_profile, encoding_profile]

    begin
      execute_ffmpeg_and_segmenter(command_ffmpeg, encoding_profile, encoding_pipes)
    rescue
      @log.error("Encoding error: " + $!)
    end
  end

  def run_multirate_encoding( encoding_threads )
    # Have the transfer thread create and transfer the multirate index
    @hs_transfer << HSTransfer::MULTIRATE_INDEX
  
    encoding_pipes = []

    # Start a new thread for each encoding profile
    @config['encoding_profile'].each do |profile_name|
      encoding_threads << Thread.new do
        @log.info('Encoding thread started: ' + profile_name);

        process_encoding(profile_name, '-', encoding_pipes)

        @log.info('Encoding thread terminated: ' + profile_name);
      end
    end

    # Start a new master encoding thread that will feed the profile encoder threads
    encoding_threads << Thread.new do
      @log.info('Master encoding thread started');

      begin
        process_master_encoding(encoding_pipes)
      rescue
        @log.error("Master encoding error: " + $!)

        encoding_pipes.each do |out|
          begin
            out.close
          rescue
          end
        end
      end

      @log.info('Master encoding thread terminated');
    end
  end

  def run_single_encoder( encoding_threads )
    encoding_threads << Thread.new do
      @log.info('Encoding thread started');

      process_encoding(@config['encoding_profile'], @config['input_location'], nil)
  
      @log.info('Encoding thread terminated');
    end
  end

end
