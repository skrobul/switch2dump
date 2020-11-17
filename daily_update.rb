#!/usr/bin/env ruby
require 'dotenv/load'
require 'capybara'
require 'date'
require 'capybara/dsl'
require 'logger'
require 'selenium/webdriver'
require 'date'
require 'csv'
require 'sequel'

DB = Sequel.connect(ENV['DATABASE_URL'])
DB.loggers << Logger.new($stdout)
class Gas < Sequel::Model; end
Gas.unrestrict_primary_key

Capybara.register_driver :chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.default_driver = Capybara.javascript_driver = :chrome

module Switch2
  BillEntry = Struct.new(:date, :type, :amount) do
    def parsed_date
      Date.parse(date)
    end

    def numeric_amount
      Integer(amount.split.first)
    end
  end

 class Interface
   include Capybara::DSL

   attr_reader :username, :logger
   def initialize(username:, password:)
     @username = username
     @password = password
     @logger = Logger.new($stdout)
   end

   def login
     logger.debug 'Logging in'
     visit 'https://my.switch2.co.uk/Login'
     fill_in 'UserName', with: @username
     find('#loginButton').click
     fill_in 'Password', with: @password
     sleep 1
     find('#nextStepButton').click
     if page.has_content? 'Welcome'
       logger.debug 'Logged in'
       true
     end
     false
   end

   def download_statement
     visit 'https://my.switch2.co.uk/MeterReadings/History'
#     find('#PageSize').select('All')
#     find('#ReloadButton').click
     find_all('.meter-reading-history-table-data-row').map do |el|
       logger.debug 'Iterating over element'
       date, rtype = el
                     .find_all('.meter-reading-history-table-data-row-item')
                     .map(&:text)

       amount = el
                .find('.meter-reading-history-table-data-amount-row-item')
                .text
       BillEntry.new(date, rtype, amount)
     end
   end

   def logout
     find('.signout').click
   end

   def save_statement(results)
     results.each do |entry|
       record = Gas.find_or_create(date: entry.parsed_date)
       record.update(value: entry.numeric_amount)
     end
   end
 end
end

if $PROGRAM_NAME == __FILE__

  sw2 = Switch2::Interface.new(
    username: ENV.fetch('SW2_LOGIN'),
    password: ENV.fetch('SW2_PASSWORD'),
  )

  begin
    sw2.login
    statement = sw2.download_statement
    sw2.save_statement(statement)
  ensure
    sw2.logout
  end
end
