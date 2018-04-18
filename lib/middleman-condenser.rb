require "middleman-core"

::Middleman::Extensions.register :condenser do
  require "middleman/condenser"
  ::Middleman::Condenser
end
