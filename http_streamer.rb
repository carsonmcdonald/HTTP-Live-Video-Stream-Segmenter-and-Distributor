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

# **************************************************************
#
# Main
#
# **************************************************************

hsencoder = nil

trap('INT') { hsencoder.stop_encoding if !hsencoder.nil?  }

if ARGV.length != 1
  puts "Usage: http_streamer.rb <config file>"
  exit 1
end

begin
  config = HSConfig::load( ARGV[0] )
rescue
  exit 1
end

log = HSConfig::log_setup( config )

log.info('HTTP Streamer started')

hstransfer = HSTransfer::init_and_start_transfer_thread( log, config )

hsencoder = HSEncoder.new(log, config, hstransfer)
hsencoder.start_encoding

hstransfer.stop_transfer_thread

log.info('HTTP Streamer terminated')
