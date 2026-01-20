class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Use UUIDs as primary keys
  self.implicit_order_column = :created_at
end
