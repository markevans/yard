module YARD
  module CLI
    # A local documentation server
    # @since 0.6.0
    class Server < Command
      # @return [Hash] a list of options to pass to the doc server
      attr_accessor :options
      
      # @return [Hash] a list of options to pass to the web server
      attr_accessor :server_options
      
      # @return [Hash] a list of library names and yardoc files to serve
      attr_accessor :libraries
      
      # @return [Adapter] the adapter to use for loading the web server
      attr_accessor :adapter
      
      def description
        "Runs a local documentation server"
      end
      
      def run(*args)
        self.libraries = {}
        self.options = SymbolHash.new(false).update(
          :single_library => true,
          :caching => false
        )
        self.server_options = {:Port => 8808}
        optparse(*args)
        
        select_adapter
        adapter.new(libraries, options, server_options).start
      end
      
      private
      
      def select_adapter
        return adapter if adapter
        require 'rubygems'
        require 'rack'
        self.adapter = YARD::Server::RackAdapter
      rescue LoadError
        self.adapter = YARD::Server::WebrickAdapter
      end
      
      def add_libraries(args)
        (0...args.size).step(2) do |index|
          library, yardoc = args[index], args[index + 1]
          yardoc ||= '.yardoc'
          if File.exist?(yardoc)
            libraries[library] ||= []
            libraries[library] << YARD::Server::LibraryVersion.new(library, nil, yardoc)
          else
            log.warn "Cannot find yardoc db for #{library}: #{yardoc}"
          end
        end
      end
      
      def add_gems
        require 'rubygems'
        Gem.source_index.find_name('').each do |spec|
          libraries[spec.name] ||= []
          libraries[spec.name] << YARD::Server::LibraryVersion.new(spec.name, spec.version.to_s, nil, :gem)
        end
      end
      
      def optparse(*args)
        opts = OptionParser.new
        opts.banner = 'Usage: yard server [options] [[library yardoc_file] ...]'
        opts.separator ''
        opts.separator 'Example: yard server yard .yardoc ruby-core ../ruby/.yardoc'
        opts.separator 'The above example serves documentation for YARD and Ruby-core'
        opts.separator ''
        opts.separator 'If no library/yardoc_file is specified, the server uses'
        opts.separator 'the name of the current directory and `.yardoc` respectively'
        opts.separator ''
        opts.separator "General Options:"
        opts.on('-e', '--load FILE', 'A Ruby script to load before the source tree is parsed.') do |file|
          if !require(file.gsub(/\.rb$/, ''))
            log.error "The file `#{file}' was already loaded, perhaps you need to specify the absolute path to avoid name collisions."
            exit
          end
        end
        opts.on('-m', '--multi-library', 'Serves documentation for multiple libraries') do
          options[:single_library] = false
        end
        opts.on('-c', '--cache', 'Caches all documentation to document root (see --docroot)') do
          options[:caching] = true
        end
        opts.on('-r', '--reload', 'Reparses the library code on each request') do
          options[:incremental] = true
        end
        opts.on('-g', '--gems', 'Serves documentation for installed gems') do
          add_gems
        end
        opts.separator ''
        opts.separator "Web Server Options:"
        opts.on('-d', '--daemon', 'Daemonizes the server process') do
          server_options[:daemonize] = true
        end
        opts.on('-p PORT', '--port', 'Serves documentation on PORT') do |port|
          server_options[:Port] = port.to_i
        end
        opts.on('--docroot DOCROOT', 'Uses DOCROOT as document root') do |docroot|
          server_options[:DocumentRoot] = File.expand_path(docroot)
        end
        opts.on('-a', '--adapter ADAPTER', 'Use the ADAPTER (full Ruby class) for web server') do |adapter|
          if adapter.downcase == 'webrick'
            self.adapter = YARD::Server::WebrickAdapter
          elsif adapter.downcase == 'rack'
            self.adapter = YARD::Server::RackAdapter
          else
            self.adapter = eval(adapter)
          end
        end
        opts.on('-s', '--server TYPE', 'Use a specific server type eg. thin,mongrel,cgi (Rack specific)') do |type|
          server_options[:server] = type
        end
        common_options(opts)
        parse_options(opts, args)
        
        if args.empty? && libraries.empty?
          if !File.exist?('.yardoc')
            log.enter_level(Logger::INFO) do
              log.info "No .yardoc file found in current directory, parsing source before starting server..."
            end
            Yardoc.run('-n')
          end
          add_libraries([File.basename(Dir.pwd), '.yardoc'])
        else
          add_libraries(args)
          options[:single_library] = false if libraries.size > 1
        end
      end
    end
  end
end