require 'active_record'
require 'active_model'

class ApplicationRecord < ActiveRecord::Base
  include ActiveModel::Validations

  primary_abstract_class
end
