# DataMapper's aggregate (count, min, max...) support adds its SQL handling by including a
# module into a module that the adapter class already includes. Since Ruby 3.0 that module
# lands behind the adapter's own method, so aggregate queries hit the plain one and fail.
# Putting it in front again restores the behaviour Ruby 2.x gave.
adapter = DataMapper::Adapters::DataObjectsAdapter
unless adapter.ancestors.first == adapter && adapter.instance_method(:property_to_column_name).owner.name.to_s.include?('Aggregates')
  adapter.prepend(Module.new do
    def property_to_column_name(property, qualify)
      if property.is_a?(DataMapper::Query::Operator)
        aggregate_field_statement(property.operator, property.target, qualify)
      else
        super
      end
    end
  end)
end
