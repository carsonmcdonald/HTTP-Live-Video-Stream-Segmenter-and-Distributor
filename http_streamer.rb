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
require 'hs_config'
require 'hs_encoder'

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

# **************************************************************
#
# Main
#
# **************************************************************

if ARGV.length != 1
  puts "Usage: http_streamer.rb <config file>"
  exit 1
end

config = HSConfig::load( ARGV[0] )

log = log_setup( config )

log.info('HTTP Streamer started')

hstransfer = HSTransfer::init_and_start_transfer_thread( log, config )

HSEncoder::init_and_start_encoding( log, config, hstransfer )

hstransfer.stop_transfer_thread

log.info('HTTP Streamer terminated')
