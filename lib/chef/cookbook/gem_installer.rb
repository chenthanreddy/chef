#--
# Copyright:: Copyright (c) 2010-2016 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "bundler"
require "bundler/inline"

class Chef
  class Cookbook
    class GemInstaller

      # @return [Chef::EventDispatch::Dispatcher] the client event dispatcher
      attr_accessor :events
      # @return [Chef::CookbookCollection] the cookbook collection
      attr_accessor :cookbook_collection

      def initialize(cookbook_collection, events)
        @cookbook_collection = cookbook_collection
        @events = events
      end

      # Installs the gems into the omnibus gemset.
      #
      def install
        cookbook_gems = []

        cookbook_collection.each do |cookbook_name, cookbook_version|
          cookbook_gems += cookbook_version.metadata.gems
        end

        events.cookbook_gem_start(cookbook_gems)

        unless cookbook_gems.empty?
          begin
            inline_gemfile do
              source Chef::Config[:rubygems_url]
              cookbook_gems.each do |args|
                gem(*args)
              end
            end
          rescue Exception => e
            events.cookbook_gem_failed(e)
            raise
          end
        end

        events.cookbook_gem_finished
      end

      # Bundler::UI object so that we can intercept and log the output
      # of the in-memory bundle install that we are going to do.
      #
      class ChefBundlerUI < Bundler::UI::Silent
        attr_accessor :events

        def initialize(events)
          @events = events
          super()
        end

        def confirm(msg, newline = nil)
          # looks like "Installing time_ago_in_words 0.1.1" when installing
          if msg =~ /Installing\s+(\S+)\s+(\S+)/
            events.cookbook_gem_installing($1, $2)
          end
          Chef::Log.info(msg)
        end

        def error(msg, newline = nil)
          Chef::Log.error(msg)
        end

        def debug(msg, newline = nil)
          Chef::Log.debug(msg)
        end

        def info(msg, newline = nil)
          # looks like "Using time_ago_in_words 0.1.1" when using, plus other misc output
          if msg =~ /Using\s+(\S+)\s+(\S+)/
            events.cookbook_gem_using($1, $2)
          end
          Chef::Log.info(msg)
        end

        def warn(msg, newline = nil)
          Chef::Log.warn(msg)
        end
      end

      private

      # Helper to handle older bundler versions that do not support injecting the UI
      # object.  On older bundler versions, we work, but you get no output other than
      # on STDOUT.
      #
      def inline_gemfile(&block)
        # requires https://github.com/bundler/bundler/pull/4245
        gemfile(true, ui: ChefBundlerUI.new(events), &block)
      rescue ArgumentError # Method#arity doesn't inspect optional arguments, so we rescue
        # requires bundler 1.10.0
        gemfile(true, &block)
      end
    end
  end
end
