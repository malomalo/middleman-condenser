require 'middleman-core'

class Middleman::Condenser < ::Middleman::Extension

  class Middleware
    def initialize(app, middleman)
      @app = app
      @middleman = middleman
      @condenser = Condenser::Server.new(@middleman.instance_variable_get(:@condenser), logger: @middleman.logger)
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

    cache = Condenser::Cache::FileStore.new(File.join(app.root, 'tmp/cache/assets'))
    @condenser = Condenser.new(cache: cache)
    if app.development?
      @condenser.unregister_minifier('application/javascript')
      @condenser.unregister_minifier('text/css')
    end
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
    
    # Append npm sources
    @condenser.append_npm_path(app.root)
    
    @condenser.instance_variable_set(:@middleman_app, app)
    @condenser.context_class.class_eval do
      def method_missing(method, *args, &block)
        if !@middleman_context
          app = @environment.instance_variable_get(:@middleman_app)
          @middleman_context = app.template_context_class.new(app, {}, {})
        end
        @middleman_context.__send__(method, *args, &block)
      end
    end
    
  end
  
  def before_build(builder)
    builder.instance_variable_set(:@parallel, false)
    @required_assets = Set.new
  end
  
  def export(file)
    @required_assets << file if @required_assets
  end

  def after_configuration
    host = app.config[:host]&.end_with?('/') ? app.config[:host] : "#{app.config[:host]}/"
    @condenser.context_class.class_eval <<~RUBY
      def asset_path(path, options = {})
        "#{host}" + path.delete_prefix('/')
      end
    RUBY
  end
  
  def after_build(b)
    @required_assets.each do |asset|
      puts @condenser.find_export(asset).write(File.join(app.config[:build_dir], options[:prefix]))
    end
  end

  def manipulate_resource_list resources
    resources.reject do |resource|
      resource.path.start_with?(options[:prefix].sub(/^\//, ''))
    end
  end
  
  def before_clean(builder)
    build_dir = File.join(app.config[:build_dir], options[:prefix])
    
    manifest = Condenser::Manifest.new(@condenser, build_dir)
    manifest.compile(@required_assets).each do |a|
      builder.instance_variable_get(:@to_clean).delete_if! { |x| a.to_s == a }
    end
  end


  helpers do
    def asset_path(kind, source=nil, options={})
      accept = case kind
      when :css
        source << ".#{kind}" if !source.end_with?(kind.to_s)
        'text/css'
      when :js
        source << ".#{kind}" if !source.end_with?(kind.to_s)
        'application/javascript'
      end
      
      source = kind if source.nil?

      asset = app.condenser.find_export(source, accept: accept)
      if asset
        app.extensions[:condenser].export(source)
        "/#{app.extensions[:condenser].options[:prefix].gsub(/^\//, '')}/#{asset.path}"
      else
        super
      end
    end

    def image_tag(source, options = {})
      if options[:size] && (options[:height] || options[:width])
        raise ArgumentError, "Cannot pass a :size option with a :height or :width option"
      end

      src = options[:src] = asset_path(source)

      options[:width], options[:height] = extract_dimensions(options.delete(:size)) if options[:size]
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
