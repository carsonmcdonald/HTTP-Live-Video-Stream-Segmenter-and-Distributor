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
require 'socket'
require 'ftools'
require 'rubygems'
require 'right_aws'

def create_index(segment_duration, output_prefix, http_prefix, first_segment, last_segment, stream_end)
  File.open("tmp.index.m3u8", 'w') do |index_file| 
    index_file.write("#EXTM3U\n")
    index_file.write("#EXT-X-TARGETDURATION:#{segment_duration}\n")
    index_file.write("#EXT-X-MEDIA-SEQUENCE:#{last_segment >= 5 ? last_segment-4 : 1}\n")

  first_segment.upto(last_segment) do | segment_index |
    if segment_index > last_segment - 5
      index_file.write("#EXTINF:#{segment_duration}\n")
      index_file.write("#{http_prefix}#{output_prefix}-%05u.ts\n" % segment_index)
    end
  end

    index_file.write("#EXT-X-ENDLIST") if stream_end
  end
end

def push_to_s3(index, output_directory, bucket_name, key_prefix, output_prefix, last_segment)
  s3 = RightAws::S3Interface.new('<AWS Key>', '<AWS Secret>')

  video_filename = "#{output_directory}/#{output_prefix}-%05u.ts" % last_segment
  puts "Pushing #{video_filename} to s3://#{bucket_name}/#{key_prefix}/#{output_prefix}-%05u.ts" % last_segment
  s3.put(bucket_name, "#{key_prefix}/#{output_prefix}-%05u.ts" % last_segment, File.open(video_filename), {'x-amz-acl' => 'public-read', 'content-type' => 'video/MP2T'})
  puts "Done pushing video file"
  
  puts "Pushing tmp.index.m3u8 to s3://#{bucket_name}/#{key_prefix}/#{index}"
  s3.put(bucket_name, index, File.open("tmp.index.m3u8"), {'x-amz-acl' => 'public-read', 'content-type' => 'video/MP2T'})
  puts "Done pushing index file"
end

queue = Queue.new

server_thread = Thread.new do
  server = TCPServer.new('0.0.0.0', 10234)
  while (session = server.accept)
    input = session.gets
    queue << input
    session.close
  end    
end

upload_thread = Thread.new do
  while (value = queue.pop)
    (index, output_directory, segment_duration, output_prefix, http_prefix, first_segment, last_segment, stream_end, bucket_name, key_prefix) = value.strip.split(%r{,\s*})
    if last_segment.to_i > 0
      create_index(segment_duration.to_i, output_prefix, http_prefix, first_segment.to_i, last_segment.to_i, stream_end.to_i == 1)
      push_to_s3(index, output_directory, bucket_name, key_prefix, output_prefix, last_segment.to_i)
    end
  end
end

server_thread.join
