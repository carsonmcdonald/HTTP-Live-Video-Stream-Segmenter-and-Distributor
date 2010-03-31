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

require 'yaml'

class HSConfig

  def self.load( config_file )
    HSConfig.new( config_file )
  end

  def initialize(config_file)
    @config = YAML::load( File.open(ARGV[0]) )
    sanity_check(@config)
  end

  def [](index)
    @config[index]
  end

  private 

  def sanity_check(config)
    # TODO
  end

end
