require "middleman-core"

::Middleman::Extensions.register :condenser do
  require "middleman/condenser"
  ::Middleman::Condenser
end

::Middleman::Extensions.instance_variable_get(:@auto_activate)[:before_configuration].delete_if { |i| i.name == :sass_renderer}
::Middleman::Extensions.registered.delete(:sass_renderer)
