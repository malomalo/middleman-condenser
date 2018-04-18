require 'middleman-core'

class Middleman::Condenser < ::Middleman::Extension

  class Middleware
    def initialize(app, middleman)
      @app = app
      @middleman = middleman
      @condenser = Condenser::Server.new(@middleman.instance_variable_get(:@condenser))
      @prefix = middleman.extensions[:condenser].options[:prefix]
    end
    
    def call(env)
      if env['PATH_INFO'].start_with?(@prefix)
        env['PATH_INFO'].delete_prefix!(@prefix)
        @condenser.call(env)
      else
        @app.call(env)
      end
    end
  end
  
  option :path, [], 'Source directories'
  option :prefix, '/assets', 'Directory where the assets will be served from'

  def initialize(app, options_hash={}, &block)
    # Call super to build options from the options_hash
    super

    # Require libraries only when activated
    require 'condenser'
    require 'condenser/server'

    cache = Condenser::Cache::FileStore.new(File.join(app.root, 'tmp/cache'))
    @condenser = Condenser.new(app.root, cache: cache)
    app.use(Middleware, app)
    
    Middleman::Application.send(:attr_reader, :condenser)
    app.instance_variable_set(:@condenser, @condenser)
    
    options[:path].each { |p| @condenser.append_path(p) }
    
    # Append sources
    asset_dir = File.join(app.source_dir, 'assets')
    if File.exist?(asset_dir) && File.directory?(asset_dir)
      Dir.each_child(asset_dir).each do |child|
        child = File.join(asset_dir, child)
        @condenser.append_path(child) if File.directory?(child)
      end
    end
  end
  
  def before_build(builder)
    builder.instance_variable_set(:@parallel, false)
    @required_assets = []
  end
  
  def export(file)
    @required_assets << file if @required_assets
  end

  def after_configuration
    # Do something
  end

  def manipulate_resource_list resources
    resources.reject do |resource|
      resource.path.start_with?(options[:prefix])
    end
  end
  
  def before_clean(builder)
    build_dir = File.join(app.config[:build_dir], options[:prefix])
    
    manifest = Condenser::Manifest.new(@condenser, build_dir)
    puts @required_assets.inspect
    manifest.compile(@required_assets).each do |a|
      puts a.inspect
      builder.instance_variable_get(:@to_clean).delete_if! { |x| a.to_s == a }
    end
  end


  helpers do
    def asset_path(kind, source=nil, options={})
      accept = case kind
      when :css
        'text/css'
      when :js
        'application/javascript'
      end
      
      source = kind if source.nil?
      
      asset = app.condenser.find_export(source, accept: accept)
      app.extensions[:condenser].export(source)
      "/#{app.extensions[:condenser].options[:prefix].gsub(/^\//, '')}/#{asset.path}"
    end

    def image_tag(source, options = {})
      puts 'xx'
      if options[:size] && (options[:height] || options[:width])
        raise ArgumentError, "Cannot pass a :size option with a :height or :width option"
      end

      src = options[:src] = asset_path(source)

      options[:width], options[:height] = extract_dimensions(options.delete(:size)) if options[:size]
      puts options.inspect
      tag("img", options)
    end
  
    def extract_dimensions(size)
      size = size.to_s
      if /\A\d+x\d+\z/.match?(size)
        size.split("x")
      elsif /\A\d+\z/.match?(size)
        [size, size]
      end
    end
  end
  
end