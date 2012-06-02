#!/usr/bin/env ruby
#
# Copyright (c) 2011 Thomas Christensen
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
require 'hs_config'

if ARGV.length != 1
  puts "Usage: http_cleaner.rb <config file>"
  exit 1
end

begin
  config = HSConfig::load( ARGV[0] )
rescue
  exit 1
end

log = HSConfig::log_setup( config )

log.info('HTTP Cleaner started')

transfer_config = config[config['transfer_profile']]
streamdir = transfer_config['directory'] + '/'
indexfile = "%s_%s.m3u8" % [config['index_prefix'], config['encoding_profile']]

latestseq = 0
latestfile = ''
nextline = 0

def purge(dir, pattern, timestamp) 
    puts 'Deleting '+pattern+' files in '+dir+' older than '
    puts timestamp
    Dir.chdir(dir)
    Dir.glob(pattern).each do|f|
        curts = File.mtime(f)
        if curts < timestamp and !File.directory?(f)
            puts 'Purging '+f
            File.delete(f)
        end
    end    
end

File.open(streamdir+indexfile).each do |line|
    if nextline == 1 and latestfile == ''
        latestfile = line.strip
        nextline = 0
    end
    if line[/#EXTINF:5,/]
        nextline = 1        
    end
end
puts 'Looking for time stamp on '+streamdir+latestfile

# Create file name

lastchange = File.mtime(streamdir+latestfile)
purge(streamdir,'*.ts',lastchange)

log.info('HTTP Cleaner stopped')


