require 'simplecov'
require 'coveralls'

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
  Coveralls::SimpleCov::Formatter,
  SimpleCov::Formatter::HTMLFormatter
]

SimpleCov.start do
  add_filter '/spec/'
end

require 'pry'
require 'mongoid-rspec'
require 'database_cleaner'
require 'history_tracker'
require 'history_tracker/matchers'

# active_record
load File.dirname(__FILE__) + '/support/active_record/schema.rb'
load File.dirname(__FILE__) + '/support/active_record/models.rb'

# mongoid
load File.dirname(__FILE__) + '/support/mongoid/connection.rb'
load File.dirname(__FILE__) + '/support/mongoid/models.rb'

# support
Dir["./spec/support/*.rb"].each { |f| require f }

RSpec.configure do |config|
  config.filter_run focus: true
  config.run_all_when_everything_filtered = true
  config.include Mongoid::Matchers, type: :mongoid

  config.before(:suite) do
    DatabaseCleaner[:active_record].strategy = :transaction
    DatabaseCleaner[:active_record].clean_with(:truncation)
  end

  config.around(:each) do |example|
    # Clean/Reset Mongoid DB prior to running the tests
    Mongoid.default_session.drop

    DatabaseCleaner[:active_record].cleaning do
      example.run
    end
  end
end

current_user = User.create!(email: 'chamnap@yoolk.com')
HistoryTracker.current_modifier = current_user